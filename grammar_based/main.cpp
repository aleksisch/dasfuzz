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
#include "daScript/misc/das_common.h"
#include "daScript/simulate/fs_file_info.h"
#include "daScript/misc/platform.h"
#include "daScript/misc/sysos.h"
#include "daScript/ast/aot_templates.h"
#include "daScript/ast/ast_aot_cpp.h"
#include "daScript/ast/dyn_modules.h"
#include "module_unitTest.h"

// upstream requires custom modules be forward-declared before NEED_MODULE
DECLARE_MODULE(Module_UnitTest);

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
static pid_t     g_pchOwner  = 0;

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
        g_pchOwner = getpid();
        // Only the creating process may remove it. atexit handlers survive
        // fork(), so without this guard the first AFL child to finish its
        // __AFL_LOOP budget unlinks the PCH that every later child needs —
        // they then all fail the -include-pch parse and abort() on any input.
        atexit([]{ if (g_pchReady && getpid() == g_pchOwner) unlink(g_pchPath); });
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
        // libclang could not even build a TU (missing PCH, OOM, ...). That is
        // our own infrastructure failing, not AOT C++ daslang got wrong —
        // reporting it as an error would abort() and save a bogus crash.
        fprintf(stderr, "fuzz: libclang failed to parse (rc=%d) — not a daslang error\n", (int)rc);
        return 0;
    }
    // Known-bug suppression: JIT-then-AOT in one process loses the daslib/ast
    // includes. A program that quotes requires daslib/ast; once such a program
    // has been through the LLVM JIT, a later AOT compile in the same process
    // emits C++ that still uses that module's types (TArray<Expression *>) but
    // no longer emits its includes, so clang reports a wall of "unknown type
    // name 'Expression'". Proven by toggling the JIT pass alone: with JIT the
    // sequence aborts, with DAS_FUZZ_NO_JIT=1 the same 80 inputs run clean.
    //
    // It is a real daslang bug and reported as such, but every hit produces
    // the same crash, so leaving it live buries every other finding. Suppress
    // only this exact shape: the TU lacks the ast include AND every error is
    // about one of that module's type names.
    const bool astIncludeMissing =
        strstr(src, "aot_builtin_ast.h") == nullptr &&
        strstr(src, "ast_core::") != nullptr;
    unsigned astNameErrors = 0;

    unsigned errors = 0;
    unsigned ndiag  = clang_getNumDiagnostics(tu);
    bool diagOn = getenv("DAS_FUZZ_DIAG") != nullptr;
    for (unsigned i = 0; i < ndiag; ++i) {
        CXDiagnostic d = clang_getDiagnostic(tu, i);
        CXDiagnosticSeverity sev = clang_getDiagnosticSeverity(d);
        if (sev >= CXDiagnostic_Error) {
            ++errors;
            CXString s = clang_formatDiagnostic(d, clang_defaultDiagnosticDisplayOptions());
            const char * msg = clang_getCString(s);
            if (astIncludeMissing && msg &&
                (strstr(msg, "'Expression'")  || strstr(msg, "'TypeDecl'")  ||
                 strstr(msg, "'MakeStruct'")  || strstr(msg, "'LineInfo'")  ||
                 strstr(msg, "'Function'")    || strstr(msg, "'Structure'") ||
                 strstr(msg, "expected expression") ||
                 strstr(msg, "unexpected type name"))) {
                ++astNameErrors;
            }
            if (diagOn) fprintf(stdout, "[aot-cc] %s\n", msg);
            clang_disposeString(s);
        }
        clang_disposeDiagnostic(d);
    }
    clang_disposeTranslationUnit(tu);
    if (errors > 0 && astIncludeMissing && astNameErrors == errors) {
        fprintf(stderr, "fuzz: KNOWN missing daslib/ast include after JIT — suppressed\n");
        return 0;
    }
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

// AOT driver — pre-loaded daslib/aot_cpp.das. Mirrors utils/daScript/main.cpp's
// aot_compile(): compile the script once, simulate to a context, find aot(),
// then per fuzz input restart() + evalWithCatch() to regenerate C++.
// AOT C++ emitter is no longer a C++ method on Program; lives in daslib.
static ProgramPtr  g_aotDriverProgram;
static ContextPtr  g_aotDriverCtx;
static SimFunction * g_aotFn = nullptr;
static CodeOfPolicies g_aotInputCop;
static char g_fuzzPath[64];   // /dev/shm/__fuzz_<pid>__.das — set in main

static void setupAotDriver() {
    auto access = make_smart<FsFileAccess>();
    ModuleGroup dummyGroup;
    CodeOfPolicies stub;
    stub.version_2_syntax = true;
    stub.aot_module       = true;
    NullWriter logs;
    string aotCppPath = getDasRoot() + "/daslib/aot_cpp.das";
    g_aotDriverProgram = compileDaScript(aotCppPath, access, logs, dummyGroup, stub);
    if ( !g_aotDriverProgram || g_aotDriverProgram->failed() ) {
        fprintf(stdout, "fuzz: failed to compile daslib/aot_cpp.das\n");
        if ( g_aotDriverProgram ) for ( auto & err : g_aotDriverProgram->errors ) {
            fprintf(stdout, "%s\n",
                reportError(err.at, err.what, err.extra, err.fixme, err.cerr).c_str());
        }
        return;
    }
    g_aotDriverCtx = SimulateWithErrReport(g_aotDriverProgram, logs);
    if ( !g_aotDriverCtx ) return;
    bool isUnique = false;
    g_aotFn = g_aotDriverCtx->findFunction("aot", isUnique);
    if ( !g_aotFn ) {
        fprintf(stdout, "fuzz: daslib aot() not found\n");
        return;
    }

    // Policies that daslib aot() will pass when (re)compiling the fuzz input.
    g_aotInputCop.aot                        = false;
    g_aotInputCop.aot_lib                    = false;
    g_aotInputCop.ignore_shared_modules      = false;
    g_aotInputCop.fail_on_no_aot             = false;
    g_aotInputCop.fail_on_lack_of_aot_export = false;
    g_aotInputCop.version_2_syntax           = true;
    g_aotInputCop.export_all                 = false;
    // aot_macros turns on quote LOWERING, which is not what a plain
    // `daslang -aot` does. With it on, repeatedly AOT-compiling quote
    // programs in one process eventually emits C++ that uses daslib/ast
    // types (TArray<Expression *>) without emitting that module's includes,
    // and aotCheckCpp() aborts -- a crash no standalone run reproduces,
    // because the state, not the input, is what carries it. Same class as
    // the export_all=true that used to manufacture remove_unused_symbols
    // bugs: a non-default policy only produces findings nobody can act on.
    g_aotInputCop.aot_macros                 = false;
    g_aotInputCop.stack                      = 1 * 1024 * 1024;
}

// AOT pass — write fuzz input to tmpfs, invoke daslib aot() on it, feed the
// generated C++ to libclang. daslib/aot_cpp.das opens its own FsFileAccess
// from the path we pass — no in-memory overlay possible, so we go through
// /dev/shm (RAM-backed, ~µs per write).
static void runAotPass(const unsigned char * buf, uint32_t len) {
    if ( !g_aotFn || !g_aotDriverCtx ) return;

    FILE * f = fopen(g_fuzzPath, "wb");
    if ( !f ) return;
    fwrite(buf, 1, len, f);
    fclose(f);

    daScriptEnvironment::getBound()->g_isInAot = true;

    string inputStr = g_fuzzPath;
    vec4f args[4];
    args[0] = cast<char *>::from((char *)inputStr.c_str());
    args[1] = cast<bool>::from(false);   // paranoid_validation
    args[2] = cast<bool>::from(false);   // cross_platform
    args[3] = cast<CodeOfPolicies *>::from(&g_aotInputCop);

    g_aotDriverCtx->restart();
    vec4f ret = g_aotDriverCtx->evalWithCatch(g_aotFn, args);
    if ( !g_aotDriverCtx->getException() ) {
        const char * resultStr = cast<char *>::to(ret);
        if ( resultStr && resultStr[0] ) {
            unsigned errs = aotCheckCpp(resultStr, (unsigned)strlen(resultStr));
            // Errors here mean daslang produced AOT C++ that clang rejects —
            // a daslang bug. Crash so AFL saves the input under crashes/.
            if ( errs > 0 ) {
                if ( getenv("DAS_FUZZ_DIAG") ) {
                    fprintf(stdout, "[aot-cc] %u error(s); generated C++:\n%s\n",
                            errs, resultStr);
                }
                fflush(stdout);
                abort();
            }
        }
    }

    daScriptEnvironment::getBound()->g_isInAot = false;
}

// Plain compile pass — gate for the AOT/JIT passes. If this rejects the
// input, no point spending time in the heavier paths.
static bool runCompilePass(const unsigned char * buf, uint32_t len) {
    auto access = makeAccess(buf, len);
    if ( !access ) return false;

    ModuleGroup dummyGroup;
    CodeOfPolicies policies;
    policies.fail_on_no_aot             = false;
    policies.fail_on_lack_of_aot_export = false;
    policies.version_2_syntax           = true;

    NullWriter logs;
    auto program = compileDaScript("__fuzz__.das", access, logs, dummyGroup, policies);
    return program && !program->failed();
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

    // das_fuzz binary doesn't live under <root>/bin/, so the auto-resolve in
    // getDasRoot() falls back to ".". Override explicitly: env DAS_ROOT, or
    // a compile-time fallback at the source tree.
    if ( const char * env = getenv("DAS_ROOT") ) {
        setDasRoot(env);
    } else {
#ifdef DAS_FUZZ_DAS_ROOT
        setDasRoot(DAS_FUZZ_DAS_ROOT);
#endif
    }

    Module::Initialize();

    // Register dynamic module mappings (llvm/* -> modules/dasLLVM/*, etc.) by
    // walking <dasRoot>/modules/*/.das_module — same thing daslang main does.
    {
        TextWriter dynLog;
        auto dynAccess = make_smart<FsFileAccess>();
        require_dynamic_modules(dynAccess, getDasRoot(), "", {}, dynLog);
    }

    if ( !getenv("DAS_FUZZ_NO_AOT") ) {
        // Build the libclang PCH preamble before AFL forks so every child
        // inherits the read-only PCH file via the filesystem.
        buildAotPch();

        // Compile + simulate daslib/aot_cpp.das once. Children inherit ctx via fork.
        setupAotDriver();
    }

    // -----------------------------------------------------------------------
    // Deferred fork point.  AFL++ forks here; each child already has all
    // modules registered and initialised.
    // -----------------------------------------------------------------------
    __AFL_INIT();

    // Per-fuzzer tmpfs path. After __AFL_INIT the persistent child has its
    // own pid — 20 parallel das_fuzz instances now write distinct files.
    snprintf(g_fuzzPath, sizeof(g_fuzzPath), "/dev/shm/__fuzz_%d__.das", (int)getpid());

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
        if ( !runCompilePass(buf, len) ) continue;
        if ( !getenv("DAS_FUZZ_NO_AOT") ) runAotPass(buf, len);
        if ( !getenv("DAS_FUZZ_NO_JIT") ) runJitPass(buf, len);
    }

    Module::Shutdown();
    return 0;
}
