#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POBJ="$(mktemp /tmp/verify_microapp_verify.XXXXXX.pobj)"
UAPP="$(mktemp /tmp/verify_microapp_verify.XXXXXX.uapp)"
POBJ_LOG="$(mktemp /tmp/verify_microapp_verify_pobj.XXXXXX.log)"
UAPP_LOG="$(mktemp /tmp/verify_microapp_verify_uapp.XXXXXX.log)"
BAD_LOG="$(mktemp /tmp/verify_microapp_verify_bad.XXXXXX.log)"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export MICROAPP_TARGET_ARCH
export TARGET_GCC

cleanup() {
    rm -f "$POBJ" "$UAPP" "$POBJ_LOG" "$UAPP_LOG" "$BAD_LOG"
}
trap cleanup EXIT

"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$POBJ" >/tmp/verify_microapp_verify_build_pobj.log 2>&1
"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$UAPP" >/tmp/verify_microapp_verify_build_uapp.log 2>&1

"$ROOT_DIR/bin/uya" verify-image "$POBJ" >"$POBJ_LOG" 2>&1
"$ROOT_DIR/bin/uya" verify-image "$UAPP" >"$UAPP_LOG" 2>&1

grep -q '^kind=pobj$' "$POBJ_LOG"
grep -q '^verified=yes$' "$POBJ_LOG"
grep -q '^version=8$' "$POBJ_LOG"
grep -q '^target_arch=x86_64$' "$POBJ_LOG"

grep -q '^kind=uapp$' "$UAPP_LOG"
grep -q '^verified=yes$' "$UAPP_LOG"
grep -q '^format_version=2$' "$UAPP_LOG"
grep -q '^target_arch=x86_64$' "$UAPP_LOG"

if "$ROOT_DIR/bin/uya" verify-image /tmp/does_not_exist.uapp >"$BAD_LOG" 2>&1; then
    echo "✗ verify-image 对不存在文件不应成功"
    cat "$BAD_LOG"
    exit 1
fi
grep -q '错误: .uapp 太小或无法读取' "$BAD_LOG"

echo "microapp verify-image ok"
