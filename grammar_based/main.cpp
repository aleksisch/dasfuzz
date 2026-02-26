/*
 * AFL++ persistent-mode fuzzing harness for daslang.
 *
 * Strategy:
 *   - __AFL_LOOP() keeps the child alive for many inputs without re-forking.
 *   - Input is injected via AFL++ shared memory (buf / len macros) — no disk I/O.
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

#include <unistd.h>
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

        // Allocate a null-terminated copy.
        // das_aligned_alloc16 / das_aligned_free16 match TextFileInfo's destructor.
        char * src = static_cast<char *>(das_aligned_alloc16(len + 1));
        if (!src) continue;
        memcpy(src, buf, len);
        src[len] = '\0';

        // Create a virtual in-memory file — no disk I/O.
        // own=true: TextFileInfo takes ownership and frees src via das_aligned_free16.
        auto access = make_smart<FsFileAccess>();
        auto fileInfo = make_unique<TextFileInfo>(src, len, /*own=*/true);
        access->setFileInfo("__fuzz__.das", das::move(fileInfo));

        ModuleGroup dummyGroup;
        CodeOfPolicies policies;
        policies.version_2_syntax          = true;
        policies.fail_on_no_aot            = false;
        policies.fail_on_lack_of_aot_export = false;

        NullWriter logs;

        // Compile only — AFL++ catches any crash signal automatically.
        if ( auto program = compileDaScript("__fuzz__.das", access, logs, dummyGroup, policies) ) {
            if ( !program->failed() ) {
                // Simulate can crash as well.
                auto pctx = SimulateWithErrReport(program, logs);
            }
        }
    }

    Module::Shutdown();
    return 0;
}
