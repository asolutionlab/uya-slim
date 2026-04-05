#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/tests"
BUILD_DIR="$TEST_DIR/build"
SRC="$TEST_DIR/microapp_mode_gate.uya"
OUT_C="$BUILD_DIR/microapp_mode_gate.c"

mkdir -p "$BUILD_DIR"

cat > "$SRC" <<'UYA'
use std.runtime.entry;

extern fn host_touch() i32;

export fn main() i32 {
    return 0;
}
UYA

"$ROOT_DIR/bin/uya" --c99 --nostdlib "$SRC" -o "$OUT_C"

if "$ROOT_DIR/bin/uya" --c99 --nostdlib --app microapp "$SRC" -o "$OUT_C" >/dev/null 2>&1; then
    echo "expected microapp build to reject extern"
    exit 1
fi

echo "microapp mode gate ok"
