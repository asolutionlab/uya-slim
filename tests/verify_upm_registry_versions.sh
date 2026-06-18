#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_registry_versions.XXXXXX)"
REGISTRY_ROOT="$TMP_DIR/registry"
TEST_SRC="$TMP_DIR/check_registry_versions.uya"
TEST_BIN="$TMP_DIR/check_registry_versions"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$REGISTRY_ROOT/uya.local/foo/1.2.3" "$REGISTRY_ROOT/uya.local/foo/2.0.0" "$REGISTRY_ROOT/uya.local/foo/bad"
cat > "$REGISTRY_ROOT/uya.local/foo/1.2.3/uya.toml" <<'EOF_V1'
[package]
name = "foo"
module = "uya.local/foo"
version = "1.2.3"
EOF_V1
cat > "$REGISTRY_ROOT/uya.local/foo/2.0.0/uya.toml" <<'EOF_V2'
[package]
name = "foo"
module = "uya.local/foo"
version = "2.0.0"
EOF_V2

cat > "$TEST_SRC" <<'EOF_TEST'
use libc.fprintf;
use cmd.upm.upm_lib.registry.upm_registry_list_versions;

export fn main() i32 {
    var versions: [byte: 256] = [];
    var count: i32 = 0;
    if upm_registry_list_versions("uya.local/foo" as &byte, &versions[0] as &byte, 256usize, &count) != 0 {
        fprintf(libc.stderr, "registry list failed\n" as *byte);
        return 1;
    }
    fprintf(libc.stdout, "count=%d\n%s\n" as *byte, count, &versions[0] as *byte);
    return 0;
}
EOF_TEST

"$COMPILER" build "$TEST_SRC" -o "$TEST_BIN" --no-split-c --project-root "$ROOT_DIR/src/" >"$BUILD_LOG" 2>&1
UYA_UPM_REGISTRY_DIR="$REGISTRY_ROOT" "$TEST_BIN" >"$RUN_LOG" 2>&1
grep -q 'count=2' "$RUN_LOG"
grep -q '1.2.3' "$RUN_LOG"
grep -q '2.0.0' "$RUN_LOG"

echo "verify_upm_registry_versions: ok"
