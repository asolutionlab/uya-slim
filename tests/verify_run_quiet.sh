#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_run_quiet.XXXXXX)"
SRC="$TMP_DIR/main.uya"
LOG="$TMP_DIR/run.log"
C_SRC="$TMP_DIR/add_impl.c"
CIMPORT_SRC="$TMP_DIR/cimport_main.uya"
CIMPORT_LOG="$TMP_DIR/cimport_run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'UYA'
export fn main() i32 {
    @println("run-output-ok");
    return 0;
}
UYA

"$COMPILER" run "$SRC" >"$LOG" 2>&1

grep -q "run-output-ok" "$LOG"

assert_no_compile_logs() {
    local log_file="$1"
    for unexpected in \
    "=== 开始编译 ===" \
    "输入文件数量:" \
    "=== 编译统计 ===" \
    "代码生成完成" \
    "编译完成" \
    "信息：调用宿主工具链链接" \
    "信息：编译对象文件" \
    "信息：CFLAGS"; do
        if grep -q "$unexpected" "$log_file"; then
            echo "FAIL: uya run emitted compile log: $unexpected"
            cat "$log_file"
            exit 1
        fi
    done
}

assert_no_compile_logs "$LOG"

cat >"$C_SRC" <<'C'
int quiet_add_i32(int a, int b) {
    return a + b;
}
C

cat >"$CIMPORT_SRC" <<'UYA'
@c_import("add_impl.c");

extern fn quiet_add_i32(a: i32, b: i32) i32;

export fn main() i32 {
    if quiet_add_i32(19, 23) != 42 {
        return 1;
    }
    @println("cimport-run-output-ok");
    return 0;
}
UYA

"$COMPILER" run "$CIMPORT_SRC" >"$CIMPORT_LOG" 2>&1

grep -q "cimport-run-output-ok" "$CIMPORT_LOG"
assert_no_compile_logs "$CIMPORT_LOG"

echo "verify_run_quiet: ok"
