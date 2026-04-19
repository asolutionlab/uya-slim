#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
POBJ="$(mktemp /tmp/verify_microapp_inspect.XXXXXX.pobj)"
UAPP="$(mktemp /tmp/verify_microapp_inspect.XXXXXX.uapp)"
POBJ_LOG="$(mktemp /tmp/verify_microapp_inspect_pobj.XXXXXX.log)"
UAPP_LOG="$(mktemp /tmp/verify_microapp_inspect_uapp.XXXXXX.log)"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export MICROAPP_TARGET_ARCH
export TARGET_GCC

cleanup() {
    rm -f "$POBJ" "$UAPP" "$POBJ_LOG" "$UAPP_LOG"
}
trap cleanup EXIT

"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$POBJ" >/tmp/verify_microapp_inspect_build_pobj.log 2>&1
"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$UAPP" >/tmp/verify_microapp_inspect_build_uapp.log 2>&1

"$ROOT_DIR/bin/uya" inspect-image "$POBJ" >"$POBJ_LOG" 2>&1
"$ROOT_DIR/bin/uya" inspect-image "$UAPP" >"$UAPP_LOG" 2>&1

grep -q '^kind=pobj$' "$POBJ_LOG"
grep -q '^version=8$' "$POBJ_LOG"
grep -q '^target_arch=x86_64$' "$POBJ_LOG"
grep -q '^profile=linux_x86_64_hardvm$' "$POBJ_LOG"
grep -q '^bridge=call_gate$' "$POBJ_LOG"

grep -q '^kind=uapp$' "$UAPP_LOG"
grep -q '^validated=yes$' "$UAPP_LOG"
grep -q '^target_arch=x86_64$' "$UAPP_LOG"
grep -q '^profile=linux_x86_64_hardvm$' "$UAPP_LOG"
grep -q '^bridge=call_gate$' "$UAPP_LOG"

echo "microapp inspect-image ok"
