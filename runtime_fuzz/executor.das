options gen2
module executor shared

require fio
require strings

enum ExecResult {
    OK
    COMPILE_ERROR
    CRASH
    TIMEOUT
    HASH_MISMATCH
}

struct RunResult {
    exit_code : int
    output : string
}

def run_one(cmd : string; timeout_ms : int) : RunResult {
    var res = RunResult()
    res.exit_code = -1
    unsafe {
        res.exit_code = popen_timeout(cmd, float(timeout_ms) / 1000.0) <| $(f) {
            res.output = fread(f)
        }
    }
    return res
}

def execute(program : string; daslang_bin : string; timeout_ms : int) : ExecResult {
    let tmp_file = "_codealchemist_tmp.das"
    fopen(tmp_file, "wb") <| $(f) {
        fwrite(f, program)
    }
    // Run 1: interpreter
    let cmd_interp = daslang_bin + " " + tmp_file + " 2>/dev/null"
    let r1 = run_one(cmd_interp, timeout_ms)
    if (r1.exit_code == popen_timed_out) {
        return ExecResult.TIMEOUT
    } elif (r1.exit_code != 0 && r1.exit_code >= 128) {
        return ExecResult.CRASH
    } elif (r1.exit_code != 0) {
        return ExecResult.COMPILE_ERROR
    }
    // Run 2: JIT
    let cmd_jit = daslang_bin + " -jit " + tmp_file + " 2>/dev/null"
    let r2 = run_one(cmd_jit, timeout_ms)
    if (r2.exit_code == popen_timed_out) {
        return ExecResult.TIMEOUT
    } elif (r2.exit_code != 0 && r2.exit_code >= 128) {
        return ExecResult.CRASH
    } elif (r2.exit_code != 0) {
        return ExecResult.COMPILE_ERROR
    }
    // Compare outputs
    if (r1.output != r2.output) {
        return ExecResult.HASH_MISMATCH
    }
    return ExecResult.OK
}
