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
            NullWriter tw;
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
