#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_module_manifest.XXXXXX)"
WORK_DIR="$TMP_DIR/app"
LOG_FILE="$TMP_DIR/build.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

mkdir -p "$WORK_DIR/src"
cat > "$WORK_DIR/uya.toml" <<'EOF_MANIFEST'
[package]
name = "app"
module = "uya.local/app"
version = "0.1.0"
source-dir = "src"

[dependencies]
foo = { module = "uya.local/foo", version = "1.2.3" }
EOF_MANIFEST
cat > "$WORK_DIR/src/main.uya" <<'EOF_MAIN'
export fn main() i32 {
    return 0;
}
EOF_MAIN

set +e
"$ROOT_DIR/bin/uya-upm-stage2" build "$WORK_DIR" --no-split-c >"$LOG_FILE" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "✗ module+version 依赖当前应尚未实现解析"
    cat "$LOG_FILE"
    exit 1
fi

grep -q 'module+version 依赖解析尚未实现' "$LOG_FILE"
grep -q 'module=uya.local/foo' "$LOG_FILE"
grep -q 'version=1.2.3' "$LOG_FILE"

echo "verify_upm_module_manifest_parse: ok"
