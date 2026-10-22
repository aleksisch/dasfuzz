/* Disable core dumps for the target process entirely.
 *
 * The system core_pattern pipes crashes to apport, which AFL refuses to run
 * under: a slow crash handler makes a crash look like a timeout, so real
 * findings get filed as hangs. Changing core_pattern needs root.
 *
 * PR_SET_DUMPABLE(0) makes the kernel skip the dump altogether, so no handler
 * is ever spawned and the process dies immediately with its real signal.
 * waitpid() still reports WIFSIGNALED, which is all AFL needs.
 */
#include <sys/prctl.h>
#include <sys/resource.h>

__attribute__((constructor(101)))
static void disable_core_dumps(void) {
    struct rlimit rl = { 0, 0 };
    setrlimit(RLIMIT_CORE, &rl);
    prctl(PR_SET_DUMPABLE, 0, 0, 0, 0);
}
