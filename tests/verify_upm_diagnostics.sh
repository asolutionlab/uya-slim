#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_diagnostics.XXXXXX)"
TMP_HOME="$TMP_DIR/home"
APP_DIR="$TMP_DIR/app"
DEP_DIR="$TMP_DIR/foo_pkg"
GRAPH_LOG="$TMP_DIR/graph.log"
WHY_LOG="$TMP_DIR/why.log"
DOCTOR_LOG="$TMP_DIR/doctor.log"
CACHE_LOG="$TMP_DIR/cache.log"
VENDOR_LOG="$TMP_DIR/vendor.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

mkdir -p "$TMP_HOME" "$APP_DIR/src" "$DEP_DIR/src"
cat > "$APP_DIR/uya.toml" <<'EOF_APP'
[package]
name = "app"
module = "uya.local/app"
version = "0.1.0"
source-dir = "src"

[dependencies]
foo = { path = "../foo_pkg", module = "uya.local/foo", version = "1.2.3" }
EOF_APP
cat > "$APP_DIR/src/main.uya" <<'EOF_MAIN'
use foo.file.foo_value;

export fn main() i32 {
    return foo_value();
}
EOF_MAIN
cat > "$DEP_DIR/uya.toml" <<'EOF_DEP'
[package]
name = "foo"
module = "uya.local/foo"
version = "1.2.3"
source-dir = "src"
EOF_DEP
cat > "$DEP_DIR/src/file.uya" <<'EOF_DEP_SRC'
export fn foo_value() i32 {
    return 0;
}
EOF_DEP_SRC

HOME="$TMP_HOME" "$ROOT_DIR/bin/cmd/upm" graph "$APP_DIR" >"$GRAPH_LOG" 2>&1
grep -q 'root=app' "$GRAPH_LOG"
grep -q 'alias=foo' "$GRAPH_LOG"

HOME="$TMP_HOME" "$ROOT_DIR/bin/cmd/upm" why foo "$APP_DIR" >"$WHY_LOG" 2>&1
grep -q 'requires alias=foo' "$WHY_LOG"
grep -q 'module=uya.local/foo' "$WHY_LOG"

HOME="$TMP_HOME" "$ROOT_DIR/bin/cmd/upm" doctor "$APP_DIR" >"$DOCTOR_LOG" 2>&1
grep -q 'upm doctor: ok package=app deps=1' "$DOCTOR_LOG"

HOME="$TMP_HOME" "$ROOT_DIR/bin/cmd/upm" cache dir >"$CACHE_LOG" 2>&1
grep -q "pkg=$TMP_HOME/.uya/pkg" "$CACHE_LOG"
grep -q "vcs=$TMP_HOME/.uya/pkg/vcs" "$CACHE_LOG"
grep -q "mod=$TMP_HOME/.uya/pkg/mod" "$CACHE_LOG"

HOME="$TMP_HOME" "$ROOT_DIR/bin/cmd/upm" vendor "$APP_DIR" >"$VENDOR_LOG" 2>&1
grep -q 'vendored deps=1' "$VENDOR_LOG"
test -f "$APP_DIR/.uya/deps/foo/file.uya"
test -f "$APP_DIR/uya.lock"

echo "verify_upm_diagnostics: ok"
