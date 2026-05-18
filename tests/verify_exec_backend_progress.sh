#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${REPO_ROOT}/lib/"

TMP_STDOUT="$(mktemp)"
TMP_STDERR="$(mktemp)"
TMP_DUMP="$(mktemp)"
trap 'rm -f "$TMP_STDOUT" "$TMP_STDERR" "$TMP_DUMP"' EXIT

echo "验证 test --vm 基本链路..."
"$COMPILER" test --vm "$SCRIPT_DIR/test_exec_vm_if_else.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q '总计: 1 个测试' "$TMP_STDERR"
grep -q '通过: 1' "$TMP_STDERR"
echo "  test --vm smoke ✓"

echo "验证 test --exec 支持路径不发生 fallback..."
"$COMPILER" test --exec "$SCRIPT_DIR/test_exec_vm_if_else.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q '总计: 1 个测试' "$TMP_STDERR"
grep -q '通过: 1' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ supported test --exec unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  test --exec smoke ✓"

echo "验证 const pool 去重..."
"$COMPILER" run --vm --dump-bytecode "$SCRIPT_DIR/test_exec_vm_const_pool.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q '=== exec bytecode ===' "$TMP_STDERR"
grep -q 'const_pool=4' "$TMP_STDERR"
grep -q 'const\[0\]' "$TMP_STDERR"
grep -q 'const\[1\]' "$TMP_STDERR"
echo "  const pool dump ✓"

echo "验证 try/catch 错误联合路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_error_union.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  try/catch exec path ✓"

echo "验证 struct/array/slice/tuple 聚合值路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_aggregates.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  aggregate exec path ✓"

echo "验证 u8/u16/usize/isize 与通用指针 builtin 路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_scalar_pointer.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
echo "  scalar/pointer exec path ✓"

echo "验证 defer/errdefer 清理顺序..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_defer.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
tail -n 5 "$TMP_STDOUT" | diff -u <(printf 'NSIK\nOB1\nCC2\nDO7\nEDR0\n') -
echo "  defer/errdefer exec path ✓"

echo "验证 @c_import unsupported 原因..."
if "$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_c_import_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    echo "✗ @c_import unsupported case should fail under --vm"
    cat "$TMP_STDERR"
    exit 1
fi
grep -q 'exec: 当前不支持 @c_import' "$TMP_STDERR"
echo "  @c_import unsupported reason ✓"

echo "验证 SIMD unsupported 原因..."
if "$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_simd_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    echo "✗ SIMD unsupported case should fail under --vm"
    cat "$TMP_STDERR"
    exit 1
fi
grep -q 'exec: 当前不支持 SIMD' "$TMP_STDERR"
echo "  SIMD unsupported reason ✓"

echo "验证 extern ABI unsupported 原因与 fallback..."
if "$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_extern_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    echo "✗ extern unsupported case should fail under --vm"
    cat "$TMP_STDERR"
    exit 1
fi
grep -q 'exec unsupported 原因码: extern_abi' "$TMP_STDERR"
grep -q 'exec: 当前不支持 extern ABI' "$TMP_STDERR"
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_extern_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '信息: exec backend 不支持，回退 C99 (原因码: extern_abi):' "$TMP_STDERR"
echo "  extern unsupported/fallback ✓"

echo "验证 extern/libc bridge 正向路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_extern_bridge.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
grep -q 'test_exec_vm_extern_bridge.uya' "$TMP_STDOUT"
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_extern_bridge.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q '回退 C99' "$TMP_STDERR"; then
    echo "✗ extern bridge unexpectedly fell back to C99"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  extern bridge exec path ✓"

echo "验证 extern 带函数体走普通 lowering/VM 路径..."
"$COMPILER" run --vm --dump-bytecode "$SCRIPT_DIR/test_exec_vm_extern_impl.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '后端类型: EXEC' "$TMP_STDERR"
grep -q 'exec backend 构建完成' "$TMP_STDERR"
if grep -q 'BC_CALL_EXTERN' "$TMP_STDERR"; then
    echo "✗ extern impl test unexpectedly used CALL_EXTERN bridge"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  extern impl lowered as normal call ✓"

echo "验证 test --vm/test --exec 的 extern fallback 行为..."
if "$COMPILER" test --vm "$SCRIPT_DIR/test_exec_vm_extern_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    echo "✗ extern unsupported test should fail under test --vm"
    cat "$TMP_STDERR"
    exit 1
fi
grep -q 'exec unsupported 原因码: extern_abi' "$TMP_STDERR"
grep -q 'exec: 当前不支持 extern ABI' "$TMP_STDERR"
"$COMPILER" test --exec "$SCRIPT_DIR/test_exec_vm_extern_unsupported.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
grep -q '信息: exec backend 不支持，回退 C99 (原因码: extern_abi):' "$TMP_STDERR"
grep -q '后端类型: C99' "$TMP_STDERR"
grep -q '总计: 1 个测试' "$TMP_STDERR"
grep -q '通过: 1' "$TMP_STDERR"
echo "  test extern fallback ✓"

echo "✓ exec backend progress checks passed"
