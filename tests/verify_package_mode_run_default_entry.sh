#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
COMPILER="${UYA_COMPILER:-$ROOT_DIR/bin/uya-upm-stage2}"
SRC_FIXTURE="$ROOT_DIR/tests/fixtures/upm/basic_src"
FLAT_FIXTURE="$ROOT_DIR/tests/fixtures/upm/basic_flat"
TMP_DIR="$(mktemp -d /tmp/uya_package_mode_run_default.XXXXXX)"
SRC_WORK_DIR="$TMP_DIR/basic_src"
FLAT_WORK_DIR="$TMP_DIR/basic_flat"
SRC_RUN_LOG="$TMP_DIR/src_run.log"
FLAT_RUN_LOG="$TMP_DIR/flat_run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$ROOT_DIR/bin/cmd/upm" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

cp -R "$SRC_FIXTURE" "$SRC_WORK_DIR"
cp -R "$FLAT_FIXTURE" "$FLAT_WORK_DIR"

(
    cd "$SRC_WORK_DIR"
    "$COMPILER" run >"$SRC_RUN_LOG" 2>&1
)
grep -q "src-ok" "$SRC_RUN_LOG"
test -f "$SRC_WORK_DIR/uya.lock"

(
    cd "$FLAT_WORK_DIR"
    "$COMPILER" run >"$FLAT_RUN_LOG" 2>&1
)
grep -q "flat-ok" "$FLAT_RUN_LOG"
test -f "$FLAT_WORK_DIR/uya.lock"

echo "verify_package_mode_run_default_entry: ok"
