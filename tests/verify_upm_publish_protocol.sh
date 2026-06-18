#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
COMPILER="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_publish_protocol.XXXXXX)"
REGISTRY_ROOT="$TMP_DIR/registry"
OK_DIR="$TMP_DIR/ok_pkg"
DUP_DIR="$TMP_DIR/dup_pkg"
RECEIPT="$TMP_DIR/publish.receipt"
TEST_SRC="$TMP_DIR/check_publish.uya"
TEST_BIN="$TMP_DIR/check_publish"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

mkdir -p "$OK_DIR/src" "$DUP_DIR/src" "$REGISTRY_ROOT/uya.local/foo/0.9.0"
cat > "$OK_DIR/uya.toml" <<'EOF_OK_MANIFEST'
[package]
name = "foo"
module = "uya.local/foo"
version = "1.2.3"
source-dir = "src"
EOF_OK_MANIFEST
cat > "$OK_DIR/src/file.uya" <<'EOF_OK_SRC'
export fn value() i32 {
    return 1;
}
EOF_OK_SRC
cat > "$DUP_DIR/uya.toml" <<'EOF_DUP_MANIFEST'
[package]
name = "foo"
module = "uya.local/foo"
version = "0.9.0"
source-dir = "src"
EOF_DUP_MANIFEST
cat > "$DUP_DIR/src/file.uya" <<'EOF_DUP_SRC'
export fn value() i32 {
    return 2;
}
EOF_DUP_SRC
cat > "$REGISTRY_ROOT/uya.local/foo/0.9.0/uya.toml" <<'EOF_REGISTRY_MANIFEST'
[package]
name = "foo"
module = "uya.local/foo"
version = "0.9.0"
EOF_REGISTRY_MANIFEST

cat > "$TEST_SRC" <<EOF_TEST
use libc.fprintf;
use cmd.upm.upm_lib.publish.UPMPublishPlan;
use cmd.upm.upm_lib.publish.upm_publish_plan_init;
use cmd.upm.upm_lib.publish.upm_publish_prepare_plan;
use cmd.upm.upm_lib.publish.upm_publish_write_metadata;

export fn main() i32 {
    var plan: UPMPublishPlan = upm_publish_plan_init();
    if upm_publish_prepare_plan("$OK_DIR/uya.toml" as &byte, &plan) != 0 {
        fprintf(libc.stderr, "prepare ok package failed\\n" as *byte);
        return 1;
    }
    if plan.content_hash[0] == 0 as byte {
        fprintf(libc.stderr, "missing publish checksum\\n" as *byte);
        return 2;
    }
    if upm_publish_write_metadata(&plan, "$RECEIPT" as &byte) != 0 {
        fprintf(libc.stderr, "write publish metadata failed\\n" as *byte);
        return 3;
    }
    var duplicate: UPMPublishPlan = upm_publish_plan_init();
    if upm_publish_prepare_plan("$DUP_DIR/uya.toml" as &byte, &duplicate) == 0 {
        fprintf(libc.stderr, "duplicate version unexpectedly accepted\\n" as *byte);
        return 4;
    }
    return 0;
}
EOF_TEST

"$COMPILER" build "$TEST_SRC" -o "$TEST_BIN" --no-split-c --project-root "$ROOT_DIR/src/" >"$BUILD_LOG" 2>&1
UYA_UPM_REGISTRY_DIR="$REGISTRY_ROOT" "$TEST_BIN" >"$RUN_LOG" 2>&1
grep -q 'module = "uya.local/foo"' "$RECEIPT"
grep -q 'version = "1.2.3"' "$RECEIPT"
grep -q 'content_hash = "' "$RECEIPT"

"$ROOT_DIR/bin/cmd/upm" publish "$OK_DIR" >>"$RUN_LOG" 2>&1
grep -q 'publish metadata:' "$RUN_LOG"
grep -q 'module = "uya.local/foo"' "$OK_DIR/.uya/publish.receipt"
grep -q 'version = "1.2.3"' "$OK_DIR/.uya/publish.receipt"
grep -q 'content_hash = "' "$OK_DIR/.uya/publish.receipt"

echo "verify_upm_publish_protocol: ok"
