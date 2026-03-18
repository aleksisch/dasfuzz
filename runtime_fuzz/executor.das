options gen2
module executor shared

require fio
require strings

enum ExecResult {
    OK
    COMPILE_ERROR
    CRASH
    TIMEOUT
}

def execute(program : string; daslang_bin : string; timeout_ms : int) : ExecResult {
    let tmp_file = "_codealchemist_tmp.das"
    fopen(tmp_file, "wb") <| $(f) {
        fwrite(f, program)
    }
    let cmd = daslang_bin + " " + tmp_file + " 2>/dev/null"
    var exit_code = -1
    unsafe {
        exit_code = popen_timeout(cmd, float(timeout_ms) / 1000.0) <| $(f) {
        }
    }
    if (exit_code == popen_timed_out) {
        return ExecResult.TIMEOUT
    } elif (exit_code == 0) {
        return ExecResult.OK
    } elif (exit_code < 128) {
        return ExecResult.COMPILE_ERROR
    } else {
        return ExecResult.CRASH
    }
}
