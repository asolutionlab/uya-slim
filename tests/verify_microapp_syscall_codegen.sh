#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/tests/fixtures/microapp/test_microapp_syscall_codegen.uya"
STD_SOURCE="$ROOT_DIR/tests/fixtures/microapp/test_std_microapp_io_codegen.uya"
STD_ALLOC_YIELD_SOURCE="$ROOT_DIR/tests/fixtures/microapp/test_std_microapp_alloc_yield.uya"
STD_TIME_SOURCE="$ROOT_DIR/tests/fixtures/microapp/test_std_microapp_time_runtime.uya"
MICRO_OUT="$ROOT_DIR/tests/build/microapp_syscall_codegen_microapp.c"
APP_OUT="$ROOT_DIR/tests/build/microapp_syscall_codegen_app.c"
STD_MICRO_OUT="$ROOT_DIR/tests/build/std_microapp_io_codegen_microapp.c"
STD_ALLOC_YIELD_OUT="$ROOT_DIR/tests/build/std_microapp_alloc_yield_codegen_microapp.c"
STD_TIME_OUT="$ROOT_DIR/tests/build/std_microapp_time_codegen_microapp.c"
MICRO_LOG="/tmp/verify_microapp_syscall_codegen_microapp.log"
APP_LOG="/tmp/verify_microapp_syscall_codegen_app.log"
STD_MICRO_LOG="/tmp/verify_std_microapp_io_codegen_microapp.log"
STD_ALLOC_YIELD_LOG="/tmp/verify_std_microapp_alloc_yield_codegen_microapp.log"
STD_TIME_LOG="/tmp/verify_std_microapp_time_codegen_microapp.log"

mkdir -p "$ROOT_DIR/tests/build"
rm -f "$MICRO_OUT" "$APP_OUT" "$STD_MICRO_OUT" "$STD_ALLOC_YIELD_OUT" "$STD_TIME_OUT"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export TARGET_GCC
export MICROAPP_TARGET_ARCH

"$ROOT_DIR/bin/uya" build --app microapp --no-safety-proof "$SOURCE" -o "$MICRO_OUT" >"$MICRO_LOG" 2>&1
"$ROOT_DIR/bin/uya" build --app app --no-safety-proof "$SOURCE" -o "$APP_OUT" >"$APP_LOG" 2>&1
"$ROOT_DIR/bin/uya" build --app microapp --no-safety-proof "$STD_SOURCE" -o "$STD_MICRO_OUT" >"$STD_MICRO_LOG" 2>&1
"$ROOT_DIR/bin/uya" build --app microapp --no-safety-proof "$STD_ALLOC_YIELD_SOURCE" -o "$STD_ALLOC_YIELD_OUT" >"$STD_ALLOC_YIELD_LOG" 2>&1
"$ROOT_DIR/bin/uya" build --app microapp --no-safety-proof "$STD_TIME_SOURCE" -o "$STD_TIME_OUT" >"$STD_TIME_LOG" 2>&1

if [ ! -f "$MICRO_OUT" ]; then
    cat "$MICRO_LOG"
    echo "✗ microapp syscall 代码生成未产出 microapp C 文件"
    exit 1
fi

if [ ! -f "$APP_OUT" ]; then
    cat "$APP_LOG"
    echo "✗ microapp syscall 代码生成未产出 app C 文件"
    exit 1
fi

if [ ! -f "$STD_MICRO_OUT" ]; then
    cat "$STD_MICRO_LOG"
    echo "✗ std.microapp.io 代码生成未产出 microapp C 文件"
    exit 1
fi

if [ ! -f "$STD_ALLOC_YIELD_OUT" ]; then
    cat "$STD_ALLOC_YIELD_LOG"
    echo "✗ std.microapp.mem/task 代码生成未产出 microapp C 文件"
    exit 1
fi

if [ ! -f "$STD_TIME_OUT" ]; then
    cat "$STD_TIME_LOG"
    echo "✗ std.microapp.time 代码生成未产出 microapp C 文件"
    exit 1
fi

if ! grep -q 'uya_microapp_syscall2(1,' "$MICRO_OUT"; then
    echo "✗ microapp 生成代码中缺少用户侧 microapp syscall 调用"
    exit 1
fi

if ! grep -q 'uya_syscall2(1,' "$APP_OUT"; then
    echo "✗ app 生成代码中缺少 Linux syscall 调用"
    exit 1
fi

if grep -q 'uya_microapp_syscall2(1,' "$APP_OUT"; then
    echo "✗ app 生成代码不应使用 microapp syscall shim"
    exit 1
fi

if ! grep -q 'uya_microapp_syscall2(MICROAPP_SYS_PRINT,' "$STD_MICRO_OUT"; then
    echo "✗ std.microapp.io 内部 syscall 没有走 microapp syscall shim"
    exit 1
fi

if ! grep -q 'uya_microapp_syscall2(MICROAPP_SYS_ALLOC,' "$STD_ALLOC_YIELD_OUT"; then
    echo "✗ std.microapp.mem 内部 syscall 没有走 microapp syscall shim"
    exit 1
fi

if ! grep -q 'uya_microapp_syscall2(MICROAPP_SYS_YIELD,' "$STD_ALLOC_YIELD_OUT"; then
    echo "✗ std.microapp.task 内部 syscall 没有走 microapp syscall shim"
    exit 1
fi

if ! grep -q 'uya_microapp_syscall2(MICROAPP_SYS_TIME,' "$STD_TIME_OUT"; then
    echo "✗ std.microapp.time 内部 syscall 没有走 microapp syscall shim"
    exit 1
fi

echo "microapp syscall redirection ok"
