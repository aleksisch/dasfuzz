options gen2
options persistent_heap
options gc

require daslib/strings_boost
require daslib/random
require fio

require bricks
require assembler
require executor

// --- Configuration ---

struct Config {
    i_max : int = 8
    p_blk : float = 0.16
    num_tests : int = 10000
    seed : int = 0
    crash_dir : string = "crashes"
    daslang_bin : string = "bin/daslang"
    timeout_ms : int = 5000
    verbose : bool = false
}


def parse_args(var cfg : Config&) {
    var args <- get_command_line_arguments()
    var i = 1
    while (i < length(args)) {
        if (args[i] == "--num-tests" && i + 1 < length(args)) {
            cfg.num_tests = to_int(args[++i])
        } elif (args[i] == "--seed" && i + 1 < length(args)) {
            cfg.seed = to_int(args[++i])
        } elif (args[i] == "--i-max" && i + 1 < length(args)) {
            cfg.i_max = to_int(args[++i])
        } elif (args[i] == "--crash-dir" && i + 1 < length(args)) {
            cfg.crash_dir = args[++i]
        } elif (args[i] == "--bin" && i + 1 < length(args)) {
            cfg.daslang_bin = args[++i]
        } elif (args[i] == "--timeout" && i + 1 < length(args)) {
            cfg.timeout_ms = to_int(args[++i])
        } elif (args[i] == "--verbose") {
            cfg.verbose = true
        } elif (args[i] == "--help") {
            print("Usage: daslang runtime_fuzz/main.das -- [options]\n")
            print("  --num-tests N   Number of test cases (default: 10000)\n")
            print("  --seed N        Random seed (default: time-based)\n")
            print("  --i-max N       Max statements per test (default: 8)\n")
            print("  --crash-dir D   Crash output directory (default: crashes)\n")
            print("  --bin PATH      Path to daslang binary (default: bin/daslang)\n")
            print("  --timeout MS    Execution timeout in ms (default: 5000)\n")
            print("  --verbose       Print generated programs\n")
            panic("help requested")
        }
        i++
    }
}

[export]
def main() {
    var cfg = Config()
    parse_args(cfg)
    let s = cfg.seed != 0 ? cfg.seed : int(ref_time_ticks())
    rng_seed = random_seed(s)
    var pool : BrickPool
    init_arithmetic_bricks(pool)
    print("Brick pool: {length(pool.bricks)} bricks\n")
    var total_crashes = 0
    var total_compile_errors = 0
    var total_ok = 0
    mkdir(cfg.crash_dir)
    for (test_id in range(cfg.num_tests)) {
        let program = assemble(pool, cfg.i_max, cfg.p_blk)
        if (cfg.verbose) {
            print("=== Test {test_id} ===\n{program}\n")
        }
        let result = execute(program, cfg.daslang_bin, cfg.timeout_ms)
        if (result == ExecResult.CRASH) {
            total_crashes++
            let crash_file = "{cfg.crash_dir}/crash_{test_id}.das"
            fopen(crash_file, "wb") <| $(f) {
                fwrite(f, program)
            }
            print("[CRASH] Test {test_id} -> {crash_file}\n")
        } elif (result == ExecResult.COMPILE_ERROR) {
            total_compile_errors++
        } else {
            total_ok++
        }
        if ((test_id + 1) % 100 == 0) {
            print("Progress: {test_id + 1}/{cfg.num_tests} | ok={total_ok} compile_err={total_compile_errors} crashes={total_crashes}\n")
        }
    }
    print("\n=== Done ===\n")
    print("Total: {cfg.num_tests} | OK: {total_ok} | Compile errors: {total_compile_errors} | Crashes: {total_crashes}\n")
}
