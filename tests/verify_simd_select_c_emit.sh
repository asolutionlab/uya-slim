#!/bin/bash
# TDD：SIMD @vector.select 助手按需写入 C（无 select 则无定义；仅 i32×4 则无 u32/f32 定义）
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${UYA_ROOT:-$REPO_ROOT/lib/}"
BUILD_DIR="$SCRIPT_DIR/build"
mkdir -p "$BUILD_DIR"

no_sel_c="$BUILD_DIR/simd_emit_no_select.c"
i32_only_c="$BUILD_DIR/simd_emit_select_i32_only.c"

echo "验证：无 @vector.select 的 SIMD 程序不应输出 select 助手定义 ..."
if ! "$COMPILER" --c99 "$SCRIPT_DIR/test_simd_sse_lower_i32x4.uya" -o "$no_sel_c" 2>&1; then
    echo "✗ 编译 test_simd_sse_lower_i32x4.uya 失败"
    exit 1
fi
if grep -q 'static inline void uya_simd_sse_select_' "$no_sel_c"; then
    echo "✗ 未使用 select 时仍生成了 uya_simd_sse_select_* 定义"
    exit 1
fi
echo "  无 select 时无助手定义 ✓"

echo "验证：仅 i32×4 select 时不生成 u32/f32 的 select 助手定义 ..."
if ! "$COMPILER" --c99 "$SCRIPT_DIR/test_simd_c99_select_emit_i32_only.uya" -o "$i32_only_c" 2>&1; then
    echo "✗ 编译 test_simd_c99_select_emit_i32_only.uya 失败"
    exit 1
fi
if ! grep -q 'static inline void uya_simd_sse_select_i32x4' "$i32_only_c"; then
    echo "✗ 缺少 uya_simd_sse_select_i32x4 定义"
    exit 1
fi
if grep -q 'static inline void uya_simd_sse_select_u32x4' "$i32_only_c"; then
    echo "✗ 不应生成 uya_simd_sse_select_u32x4"
    exit 1
fi
if grep -q 'static inline void uya_simd_sse_select_f32x4' "$i32_only_c"; then
    echo "✗ 不应生成 uya_simd_sse_select_f32x4"
    exit 1
fi
echo "  仅 i32×4 select 时无 u32/f32 助手 ✓"

echo ""
echo "✓ SIMD select C 按需生成验证通过"
