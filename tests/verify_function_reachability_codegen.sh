#!/bin/bash
# 验证函数可达性裁剪：未使用函数不输出，export extern 仍保留

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$REPO_ROOT/bin/uya"
export UYA_ROOT="$REPO_ROOT/lib/"
OUT_C="$SCRIPT_DIR/build/function_reachability_verify.c"

mkdir -p "$SCRIPT_DIR/build"

echo "验证函数可达性裁剪：编译 test_function_reachability_codegen.uya ..."
COMPILE_OUT=$("$COMPILER" --c99 "$SCRIPT_DIR/test_function_reachability_codegen.uya" -o "$OUT_C" 2>&1)
STATUS=$?
if [ $STATUS -ne 0 ]; then
    echo "✗ 编译失败"
    echo "$COMPILE_OUT"
    exit 1
fi

if grep -q 'dead_internal(' "$OUT_C"; then
    echo "✗ 未使用的内部函数仍然输出到了 C 文件"
    exit 1
fi
echo "  dead_internal 已裁剪 ✓"

if grep -q 'dead_exported(' "$OUT_C"; then
    echo "✗ 未使用的 export fn 仍然输出到了 C 文件"
    exit 1
fi
echo "  dead_exported 已裁剪 ✓"

if ! grep -q 'kept_c_api(' "$OUT_C"; then
    echo "✗ export extern 函数未保留到 C 文件"
    exit 1
fi
echo "  kept_c_api 已保留 ✓"

echo ""
echo "✓ 函数可达性裁剪验证通过"
