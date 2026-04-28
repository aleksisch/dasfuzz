/*
 * AFL++ persistent-mode fuzzing harness for daslang.
 *
 * Strategy:
 *   - __AFL_LOOP() keeps the child alive for many inputs without re-forking.
 *   - Input is injected via AFL++ shared memory (buf / len macros) — no disk I/O.
 *   - Per input: run AOT pass + JIT pass. Both internally simulate. Code is
 *     never executed.
 *
 * Build:
 *   mkdir build_fuzz && cd build_fuzz
 *   CXX=afl-clang-fast++ CC=afl-clang-fast cmake .. \
 *       -DCMAKE_BUILD_TYPE=Release \
 *       -DDAS_TESTS_DISABLED=ON \
 *       -DDAS_TUTORIAL_DISABLED=ON \
 *       -GNinja
 *   ninja das_fuzz -j$(nproc)
 *
 * Run:
 *   afl-fuzz -i corpus -o out -- ./bin/das_fuzz
 */

#include <daScript/daScript.h>
#include "daScript/daScriptModule.h"
#include "daScript/das_common.h"
#include "daScript/simulate/fs_file_info.h"
#include "daScript/misc/platform.h"
#include "daScript/misc/sysos.h"
#include "daScript/ast/aot_templates.h"
#include "daScript/ast/ast_aot_cpp.h"
#include "module_unitTest.h"

#include <unistd.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifdef DAS_FUZZ_AOT_CHECK
#include <clang-c/Index.h>
#endif

using namespace das;

// ---------------------------------------------------------------------------
// AFL++ shims — let this compile with a regular C++ compiler for local testing.
// afl-clang-fast/lto redefines these to implement the real fork server.
// ---------------------------------------------------------------------------
#ifndef __AFL_FUZZ_TESTCASE_LEN

static ssize_t       fuzz_len;
static unsigned char fuzz_buf[1 << 20];  // 1 MiB — increase if needed

#define __AFL_FUZZ_TESTCASE_LEN  fuzz_len
#define __AFL_FUZZ_TESTCASE_BUF  fuzz_buf
#define __AFL_FUZZ_INIT()
#define __AFL_LOOP(x)  ((fuzz_len = read(0, fuzz_buf, sizeof(fuzz_buf))) > 0 ? 1 : 0)
#define __AFL_INIT()

#endif

// Must be at file scope, before main().
__AFL_FUZZ_INIT();

// ---------------------------------------------------------------------------
// Null writer — suppress all compiler output during fuzzing.
// ---------------------------------------------------------------------------
struct NullWriter : public TextWriter {
    virtual void output() override { clear(); }
};

// ---------------------------------------------------------------------------
// libclang AOT C++ syntax checker.
//
// Flow:
//   1. Build a precompiled-header (PCH) once at startup that contains the
//      AOT preamble (`#include <daScript/...>` headers from AOT_INCLUDES
//      plus AOT_HEADERS' platform pragmas). Saves to /tmp.
//   2. Per fuzz input, after daslang generates AOT C++ into a TextWriter,
//      pass the text to clang_parseTranslationUnit with -fsyntax-only
//      -include-pch <preamble.pch>. PCH skips the multi-second header
//      parse; -fsyntax-only skips IR/codegen.
//   3. Count error-severity diagnostics. If DAS_FUZZ_DIAG is set, print
//      them. Otherwise just consume.
//
// libclang call cost without PCH: ~1-2 s per parse (header chain).
// With PCH: ~30-100 ms per parse.
// ---------------------------------------------------------------------------
#ifdef DAS_FUZZ_AOT_CHECK

static CXIndex   g_cxIndex   = nullptr;
static char      g_pchPath[] = "/tmp/das_fuzz_aot_XXXXXX.pch";
static bool      g_pchReady  = false;

// Common args for both PCH build and per-input parse.
static const char * kClangCommonArgs[] = {
    "-std=c++17",
    "-fno-rtti",
    "-fno-exceptions",
    "-DNDEBUG=1",
    "-DDAS_NO_ASSERTIONS",
    "-DDAS_DEBUGGER=0",
    "-DDAS_FUSION=2",
    "-Wno-everything",          // diagnostics noise — we only care about errors
    "-I", DAS_FUZZ_DAS_INCLUDE,
    "-I", DAS_FUZZ_FMT_INCLUDE,
    "-I", DAS_FUZZ_UNITTEST_INCLUDE,
};
static constexpr int kClangCommonArgc =
    sizeof(kClangCommonArgs) / sizeof(kClangCommonArgs[0]);

static void buildAotPch() {
    g_cxIndex = clang_createIndex(/*excludeDeclarations*/0, /*displayDiagnostics*/0);
    if (!g_cxIndex) return;

    // Pick a unique filename. mkstemps wants suffix length.
    int fd = mkstemps(g_pchPath, /*suffixlen=*/4);
    if (fd < 0) return;
    close(fd);
    unlink(g_pchPath);  // libclang will recreate it.

    // Preamble: just the AOT_INCLUDES header chain. Anything per-program
    // (namespaces, function bodies) goes after the PCH on the per-input
    // parse.
    std::string preamble;
    preamble.append(AOT_INCLUDES);
    preamble.append("\n");

    CXUnsavedFile unsaved;
    unsaved.Filename = "preamble.h";
    unsaved.Contents = preamble.data();
    unsaved.Length   = (unsigned long)preamble.size();

    // -x c++-header makes clang treat input as a header to be precompiled.
    const char * args[kClangCommonArgc + 2];
    args[0] = "-x";
    args[1] = "c++-header";
    for (int i = 0; i < kClangCommonArgc; ++i) args[2 + i] = kClangCommonArgs[i];

    CXTranslationUnit tu = nullptr;
    CXErrorCode rc = clang_parseTranslationUnit2(
        g_cxIndex, "preamble.h",
        args, kClangCommonArgc + 2,
        &unsaved, 1,
        CXTranslationUnit_ForSerialization,
        &tu);
    if (rc != CXError_Success || !tu) {
        if (tu) clang_disposeTranslationUnit(tu);
        return;
    }
    int sv = clang_saveTranslationUnit(tu, g_pchPath, clang_defaultSaveOptions(tu));
    clang_disposeTranslationUnit(tu);
    if (sv == CXSaveError_None) {
        g_pchReady = true;
        atexit([]{ if (g_pchReady) unlink(g_pchPath); });
    }
}

// Returns number of error-severity diagnostics; 0 means "compiles".
static unsigned aotCheckCpp(const char * src, unsigned len) {
    if (!g_cxIndex) return 0;
    CXUnsavedFile unsaved;
    unsaved.Filename = "fuzz_aot.cpp";
    unsaved.Contents = src;
    unsaved.Length   = len;

    // -x c++ -fsyntax-only -include-pch <pch> + common args.
    const char * args[kClangCommonArgc + 6];
    int n = 0;
    args[n++] = "-x";
    args[n++] = "c++";
    args[n++] = "-fsyntax-only";
    if (g_pchReady) {
        args[n++] = "-include-pch";
        args[n++] = g_pchPath;
    }
    for (int i = 0; i < kClangCommonArgc; ++i) args[n++] = kClangCommonArgs[i];

    CXTranslationUnit tu = nullptr;
    CXErrorCode rc = clang_parseTranslationUnit2(
        g_cxIndex, "fuzz_aot.cpp",
        args, n,
        &unsaved, 1,
        CXTranslationUnit_None,
        &tu);
    if (rc != CXError_Success || !tu) {
        if (tu) clang_disposeTranslationUnit(tu);
        return 1;  // treat parser bail as one error
    }
    unsigned errors = 0;
    unsigned ndiag  = clang_getNumDiagnostics(tu);
    bool diagOn = getenv("DAS_FUZZ_DIAG") != nullptr;
    for (unsigned i = 0; i < ndiag; ++i) {
        CXDiagnostic d = clang_getDiagnostic(tu, i);
        CXDiagnosticSeverity sev = clang_getDiagnosticSeverity(d);
        if (sev >= CXDiagnostic_Error) {
            ++errors;
            if (diagOn) {
                CXString s = clang_formatDiagnostic(d, clang_defaultDiagnosticDisplayOptions());
                fprintf(stdout, "[aot-cc] %s\n", clang_getCString(s));
                clang_disposeString(s);
            }
        }
        clang_disposeDiagnostic(d);
    }
    clang_disposeTranslationUnit(tu);
    return errors;
}

#else

static inline void     buildAotPch()                                        {}
static inline unsigned aotCheckCpp(const char * /*src*/, unsigned /*len*/) { return 0; }

#endif // DAS_FUZZ_AOT_CHECK

// ---------------------------------------------------------------------------
// Mode-specific per-input compile passes.
// ---------------------------------------------------------------------------

// own=true: TextFileInfo takes ownership and frees src via das_aligned_free16.
static FileAccessPtr makeAccess(const unsigned char * buf, uint32_t len) {
    char * src = static_cast<char *>(das_aligned_alloc16(len + 1));
    if (!src) return nullptr;
    memcpy(src, buf, len);
    src[len] = '\0';
    auto access = make_smart<FsFileAccess>();
    auto fileInfo = make_unique<TextFileInfo>(src, len, /*own=*/true);
    access->setFileInfo("__fuzz__.das", das::move(fileInfo));
    return access;
}

// AOT pass — mirror utils/daScript/main.cpp's compile() but write to NullWriter
// (no disk I/O). Exercises aotCpp / registerAotCpp / validateAotCpp codegen.
static void runAotPass(const unsigned char * buf, uint32_t len) {
    auto access = makeAccess(buf, len);
    if (!access) return;

    ModuleGroup dummyGroup;
    CodeOfPolicies policies;
    policies.aot                       = true;
    policies.aot_module                = true;
    policies.aot_macros                = true;
    policies.export_all                = true;          // needed for aot to export macros
    policies.stack                     = 1 * 1024 * 1024; // aot macros need huge stack
    policies.fail_on_no_aot            = false;
    policies.fail_on_lack_of_aot_export = false;
    policies.version_2_syntax          = true;

    NullWriter logs;
    daScriptEnvironment::getBound()->g_isInAot = true;
    auto program = compileDaScript("__fuzz__.das", access, logs, dummyGroup, policies);
    if ( program && program->failed() && getenv("DAS_FUZZ_DIAG") ) {
        for ( auto & err : program->errors ) {
            fprintf(stdout, "%s\n",
                reportError(err.at, err.what, err.extra, err.fixme, err.cerr).c_str());
        }
    }
    if ( program && !program->failed() ) {
        auto pctx = SimulateWithErrReport(program, logs);
        if ( pctx ) {
            // Capture the AOT C++ in a real TextWriter so we can hand it
            // to libclang. The previous NullWriter dropped the bytes.
            TextWriter tw;
            tw << AOT_INCLUDES;
            bool noAotModule = false;
            program->library.foreach_in_order([&](Module * mod){
                if ( !mod->name.empty() ) {
                    if ( mod->aotRequire(tw) == ModuleAotType::no_aot ) {
                        noAotModule = true;
                    }
                }
                return true;
            }, program->getThisModule());
            if ( !program->options.getBoolOption("no_aot", false) && !noAotModule ) {
                tw << AOT_HEADERS;
                {
                    NamespaceGuard das_guard(tw, "das");
                    {
                        NamespaceGuard anon_guard(tw, program->thisNamespace);
                        daScriptEnvironment::getBound()->g_Program = program;
                        program->aotCpp(*pctx, tw, /*cross_platform=*/false);
                        daScriptEnvironment::getBound()->g_Program.reset();
                        program->registerAotCpp(tw, *pctx, false);
                        program->validateAotCpp(tw, *pctx);
                    }
                }
                tw << AOT_FOOTER;

                // Send the generated C++ through clang's frontend. Detects
                // codegen / template / hash-mismatch bugs in daslang's AOT
                // output that simulate alone won't catch.
                aotCheckCpp(tw.data(), (unsigned)tw.tellp());
            }
        }
    }
    daScriptEnvironment::getBound()->g_isInAot = false;
}

// JIT pass — mirror utils/daScript/main.cpp's compile_and_run() JIT branch
// minus the execution step. Compile + simulate with JIT enabled.
static void runJitPass(const unsigned char * buf, uint32_t len) {
    auto access = makeAccess(buf, len);
    if (!access) return;
    access->addExtraModule("just_in_time", getDasRoot() + "/daslib/just_in_time.das");

    ModuleGroup dummyGroup;
    CodeOfPolicies policies;
    policies.jit_enabled               = true;
    policies.fail_on_no_aot            = false;
    policies.fail_on_lack_of_aot_export = false;
    policies.version_2_syntax          = true;
    policies.dll_search_paths.emplace_back(getDasRoot() + "/lib");

    NullWriter logs;
    auto program = compileDaScript("__fuzz__.das", access, logs, dummyGroup, policies);
    if ( program && !program->failed() ) {
        SimulateWithErrReport(program, logs);
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

// Keep O0 so AFL++ instrumentation survives optimisation passes.
#pragma clang optimize off
#pragma GCC optimize("O0")

int main(int /*argc*/, char ** /*argv*/) {

    // -----------------------------------------------------------------------
    // Expensive one-time setup — runs ONCE per AFL++ process, before the fork.
    // -----------------------------------------------------------------------
    NEED_ALL_DEFAULT_MODULES;
    NEED_MODULE(Module_UnitTest);

    Module::Initialize();

    // Build the libclang PCH preamble before AFL forks so every child
    // inherits the read-only PCH file via the filesystem.
    buildAotPch();

    // -----------------------------------------------------------------------
    // Deferred fork point.  AFL++ forks here; each child already has all
    // modules registered and initialised.
    // -----------------------------------------------------------------------
    __AFL_INIT();

    // Must be assigned before __AFL_LOOP (AFL++ shared-memory protocol).
    unsigned char * buf = __AFL_FUZZ_TESTCASE_BUF;

    // -----------------------------------------------------------------------
    // Persistent loop — reuse the same process for up to 10 000 inputs.
    // -----------------------------------------------------------------------
    while (__AFL_LOOP(10000)) {

        uint32_t len = (uint32_t)__AFL_FUZZ_TESTCASE_LEN;
        if (len == 0) continue;

        // AFL++ catches any crash signal automatically. Each pass has its
        // own access object because TextFileInfo owns the source buffer.
        runAotPass(buf, len);
        if ( !getenv("DAS_FUZZ_DIAG") ) runJitPass(buf, len);
    }

    Module::Shutdown();
    return 0;
}
