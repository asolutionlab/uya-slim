#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT_DIR/tests/fixtures/microapp/test_microapp_mmu_codegen.uya"
OUT_C="$ROOT_DIR/tests/build/microapp_mmu_codegen.c"
LOG="/tmp/verify_microapp_mmu_codegen_build.log"

mkdir -p "$ROOT_DIR/tests/build"
rm -f "$OUT_C"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export TARGET_GCC
export MICROAPP_TARGET_ARCH

"$ROOT_DIR/bin/uya" build --app microapp --no-safety-proof "$SOURCE" -o "$OUT_C" >"$LOG" 2>&1

if [ ! -f "$OUT_C" ]; then
    cat "$LOG"
    echo "✗ microapp MMU 代码生成未产出 C 文件"
    exit 1
fi

if ! grep -q 'static inline void \*uya_mmu_translate(void \*addr, size_t size, unsigned int access)' "$OUT_C"; then
    echo "✗ C 预lude 中缺少 uya_mmu_translate hook"
    exit 1
fi

touch_start="$(grep -n 'touch(struct Holder' "$OUT_C" | tail -1 | cut -d: -f1 || true)"
if [ -z "$touch_start" ]; then
    echo "✗ 未找到 touch() 生成代码"
    exit 1
fi

touch_end=$((touch_start + 40))
touch_block="$(sed -n "${touch_start},${touch_end}p" "$OUT_C")"

translate_count="$(printf '%s\n' "$touch_block" | grep -o 'uya_mmu_translate' | wc -l | tr -d '[:space:]')"
if [ "$translate_count" -lt 6 ]; then
    echo "✗ touch() 生成代码中的 MMU 翻译调用太少: $translate_count"
    echo "$touch_block"
    exit 1
fi

if ! printf '%s\n' "$touch_block" | grep -q '__typeof__(_uya_obj) _uya_translated = (__typeof__(_uya_obj))uya_mmu_translate'; then
    echo "✗ 缺少成员访问的 MMU 包装"
    echo "$touch_block"
    exit 1
fi

if ! printf '%s\n' "$touch_block" | grep -q '__typeof__(_uya_base\[0\]) \*_uya_translated = (__typeof__(_uya_base\[0\]) \*)uya_mmu_translate'; then
    echo "✗ 缺少数组/切片访问的 MMU 包装"
    echo "$touch_block"
    exit 1
fi

if ! printf '%s\n' "$touch_block" | grep -q '__typeof__(\*_uya_ptr) \*_uya_translated = (__typeof__(\*_uya_ptr) \*)uya_mmu_translate'; then
    echo "✗ 缺少解引用的 MMU 包装"
    echo "$touch_block"
    exit 1
fi

echo "microapp MMU codegen ok"
