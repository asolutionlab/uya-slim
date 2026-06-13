#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_layout_manifest.XXXXXX)"
APP_DIR="$TMP_DIR/app"
DEP_DIR="$TMP_DIR/dep"
CONFLICT_DIR="$TMP_DIR/conflict_dep"
CONFLICT_LOG="$TMP_DIR/conflict.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

mkdir -p "$APP_DIR/src" "$DEP_DIR/gui" "$DEP_DIR/gui/tests" "$DEP_DIR/gui/benchmarks" "$DEP_DIR/gui/examples" "$CONFLICT_DIR/src"

cat > "$APP_DIR/uya.toml" <<'EOF_APP_MANIFEST'
[package]
name = "app"
version = "0.1.0"
source-dir = "src"
EOF_APP_MANIFEST

cat > "$APP_DIR/src/main.uya" <<'EOF_APP_MAIN'
export fn main() i32 {
    return 0;
}
EOF_APP_MAIN

cat > "$DEP_DIR/uya.toml" <<'EOF_DEP_MANIFEST'
[package]
name = "layout_dep"
version = "0.1.0"
description = "layout compatibility test"

[layout]
source_dir = "gui"
test_dir = "gui/tests"
bench_dir = "gui/benchmarks"
example_dir = "gui/examples"

[tool.make]
default_target = "test"
EOF_DEP_MANIFEST

cat > "$DEP_DIR/gui/lib.uya" <<'EOF_DEP_LIB'
export fn hello() &byte {
    return "ok" as &byte;
}
EOF_DEP_LIB

"$ROOT_DIR/bin/cmd/upm" add layout_dep --path "$DEP_DIR" --manifest-path "$APP_DIR/uya.toml" >/dev/null 2>&1

grep -q '\[dependencies\]' "$APP_DIR/uya.toml"
grep -q 'layout_dep = { path = "' "$APP_DIR/uya.toml"
test -f "$APP_DIR/uya.lock"

cat > "$CONFLICT_DIR/uya.toml" <<'EOF_CONFLICT_MANIFEST'
[package]
name = "conflict_dep"
version = "0.1.0"
source-dir = "src"

[layout]
source_dir = "gui"
EOF_CONFLICT_MANIFEST

cat > "$CONFLICT_DIR/src/lib.uya" <<'EOF_CONFLICT_LIB'
export fn hello() &byte {
    return "bad" as &byte;
}
EOF_CONFLICT_LIB

set +e
"$ROOT_DIR/bin/cmd/upm" add conflict_dep --path "$CONFLICT_DIR" --manifest-path "$APP_DIR/uya.toml" >"$CONFLICT_LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "✗ conflicting source-dir unexpectedly succeeded"
    cat "$CONFLICT_LOG"
    exit 1
fi

grep -q 'package.source-dir 与 layout.source_dir 冲突' "$CONFLICT_LOG"

echo "verify_upm_layout_manifest: ok"
