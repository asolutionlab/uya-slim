#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD_BOOTSTRAP="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
CMD_BIN="$ROOT_DIR/bin/cmd/upm"
TMP_DIR="$(mktemp -d /tmp/uya_upm_init_validation.XXXXXX)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ "${UYA_UPM_SUITE_PREBUILT:-0}" != "1" ] && [ ! -x "$CMD_BIN" ]; then
    UYA_CMD_BOOTSTRAP_COMPILER="$CMD_BOOTSTRAP" make -C "$ROOT_DIR" cmd-upm >/dev/null
fi

VALID_DIR="$TMP_DIR/good_pkg-1"
"$CMD_BIN" init "$VALID_DIR" >"$TMP_DIR/valid.log" 2>&1
grep -q 'name = "good_pkg-1"' "$VALID_DIR/uya.toml"
[ -f "$VALID_DIR/main.uya" ]

set +e
(
    cd "$TMP_DIR"
    "$CMD_BIN" init --bad
) >"$TMP_DIR/flag.log" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -eq 0 ]; then
    echo "✗ upm init 接受了未知 --flag"
    cat "$TMP_DIR/flag.log"
    exit 1
fi
grep -q "upm init 不支持的参数" "$TMP_DIR/flag.log"
if [ -e "$TMP_DIR/--bad" ]; then
    echo "✗ upm init 为未知 --flag 创建了目录"
    exit 1
fi

BAD_NAME_DIR="$TMP_DIR/Bad Name"
set +e
"$CMD_BIN" init "$BAD_NAME_DIR" >"$TMP_DIR/name.log" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -eq 0 ]; then
    echo "✗ upm init 接受了非法项目名"
    cat "$TMP_DIR/name.log"
    exit 1
fi
grep -q "项目名无效" "$TMP_DIR/name.log"
if [ -e "$BAD_NAME_DIR" ]; then
    echo "✗ upm init 为非法项目名创建了目录"
    exit 1
fi

EXISTING_DIR="$TMP_DIR/existing_pkg"
mkdir -p "$EXISTING_DIR"
printf 'keep\n' >"$EXISTING_DIR/main.uya"
set +e
"$CMD_BIN" init "$EXISTING_DIR" >"$TMP_DIR/existing.log" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -eq 0 ]; then
    echo "✗ upm init 覆盖保护场景意外成功"
    cat "$TMP_DIR/existing.log"
    exit 1
fi
grep -q "源码文件已存在" "$TMP_DIR/existing.log"
grep -q '^keep$' "$EXISTING_DIR/main.uya"

NOT_DIR="$TMP_DIR/not_dir"
printf 'file\n' >"$NOT_DIR"
set +e
"$CMD_BIN" init "$NOT_DIR" >"$TMP_DIR/not_dir.log" 2>&1
STATUS=$?
set -e
if [ "$STATUS" -eq 0 ]; then
    echo "✗ upm init 接受了已存在的文件路径"
    cat "$TMP_DIR/not_dir.log"
    exit 1
fi
grep -q "不是目录" "$TMP_DIR/not_dir.log"

echo "verify_upm_init_validation: ok"
