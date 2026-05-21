#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${REPO_ROOT}/lib/"

TMP_STDOUT="$(mktemp)"
TMP_STDERR="$(mktemp)"
trap 'rm -f "$TMP_STDOUT" "$TMP_STDERR"' EXIT

echo "验证显式类型局部 + catch 标识符路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_compiler_typed_catch_local.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'typed catch local' "$TMP_STDOUT"
echo "  typed catch local ✓"

echo "验证 run --exec typed catch 路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_compiler_typed_catch_local.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ typed catch local unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  typed catch local --exec ✓"

echo "验证字段数组/指针字段/全局数组下标写入路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_compiler_field_pointer_index.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  field/pointer/global index --vm ✓"

echo "验证 run --exec 字段数组/指针字段/全局数组下标写入路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_compiler_field_pointer_index.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ field/pointer/global index unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  field/pointer/global index --exec ✓"

echo "验证 byte slice.ptr 读写与宿主桥接路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_compiler_slice_ptr.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  slice.ptr --vm ✓"

echo "验证 run --exec 下 byte slice.ptr 路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_compiler_slice_ptr.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ slice.ptr unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  slice.ptr --exec ✓"

echo "验证跨文件 shared whole-module import 的 libc.stderr 成员访问..."
"$COMPILER" run --vm \
    "$SCRIPT_DIR/exec_vm_compiler_shared_libc_import/main.uya" \
    "$SCRIPT_DIR/exec_vm_compiler_shared_libc_import/shared_imports.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'shared libc import stderr' "$TMP_STDERR"
echo "  shared libc.stderr --vm ✓"

echo "验证 run --exec 下跨文件 shared whole-module import 的 libc.stderr 成员访问不发生 fallback..."
"$COMPILER" run --exec \
    "$SCRIPT_DIR/exec_vm_compiler_shared_libc_import/main.uya" \
    "$SCRIPT_DIR/exec_vm_compiler_shared_libc_import/shared_imports.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'shared libc import stderr' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ shared libc.stderr unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  shared libc.stderr --exec ✓"

echo "验证 error union .error_id 成员读取路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_compiler_error_union_error_id.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  error union .error_id --vm ✓"

echo "验证 run --exec 下 error union .error_id 成员读取路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_compiler_error_union_error_id.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ error union .error_id unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  error union .error_id --exec ✓"

echo "验证 _ = expr; 丢弃赋值路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_discard_assign.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'discard assign' "$TMP_STDOUT"
echo "  discard assign --vm ✓"

echo "验证 run --exec 下 _ = expr; 丢弃赋值路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_discard_assign.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ discard assign unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  discard assign --exec ✓"

echo "验证 catch 前缀副作用 block 路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_catch_block_prefix.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'catch prefix return' "$TMP_STDOUT"
echo "  catch prefix block --vm ✓"

echo "验证 run --exec 下 catch 前缀副作用 block 路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_catch_block_prefix.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ catch prefix block unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  catch prefix block --exec ✓"

echo "验证 struct sizeof/alignof 在 --vm 下直接折叠..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_compiler_sizeof_struct.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  sizeof/alignof struct --vm ✓"

echo "验证 run --exec struct sizeof/alignof 路径不发生 fallback..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_compiler_sizeof_struct.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ sizeof/alignof struct unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  sizeof/alignof struct --exec ✓"

echo "✓ exec vm compiler regression checks passed"
