#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
COMPILER="${UYA_COMPILER:-$ROOT_DIR/bin/uya-upm-stage2}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_runtime_tree.XXXXXX)"
APP_DIR="$TMP_DIR/app"
DEP_DIR="$TMP_DIR/dep"
OUT_BIN="$TMP_DIR/runtime_tree.out"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

mkdir -p "$APP_DIR/src" "$DEP_DIR/tests"

cat > "$APP_DIR/uya.toml" <<'EOF_APP_MANIFEST'
[package]
name = "runtime_tree_app"
version = "0.1.0"
source-dir = "src"

[dependencies]
runtime_dep = { path = "../dep" }
EOF_APP_MANIFEST

cat > "$APP_DIR/src/main.uya" <<'EOF_APP_MAIN'
use runtime_dep.message_text;
use runtime_dep.tests;

export fn main() i32 {
    @println("${message_text()}");
    return 0;
}
EOF_APP_MAIN

cat > "$DEP_DIR/uya.toml" <<'EOF_DEP_MANIFEST'
[package]
name = "runtime_tree_dep"
version = "0.1.0"
source-dir = "."
EOF_DEP_MANIFEST

cat > "$DEP_DIR/lib.uya" <<'EOF_DEP_LIB'
export fn message_text() &byte {
    return "runtime-tree-ok" as &byte;
}
EOF_DEP_LIB

cat > "$DEP_DIR/tests/compile_should_ignore.uya" <<'EOF_DEP_TEST'
this is not valid uya
EOF_DEP_TEST

if ! "$COMPILER" build "$APP_DIR" -o "$OUT_BIN" --no-split-c >"$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG"
    exit 1
fi

test -x "$OUT_BIN"
if [ -d "$APP_DIR/.uya/deps/runtime_dep/tests" ]; then
    echo "development tests directory was materialized during build"
    find "$APP_DIR/.uya/deps/runtime_dep" -maxdepth 2 -type d | sort
    exit 1
fi
"$OUT_BIN" >"$RUN_LOG" 2>&1
grep -q "runtime-tree-ok" "$RUN_LOG"

echo "verify_upm_runtime_tree_excludes_dev_dirs: ok"
