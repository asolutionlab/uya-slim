#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${REPO_ROOT}/lib/"

TMP_COMPILER="$(mktemp /tmp/uya_exec_stage_smoke_bin.XXXXXX)"
TMP_STDOUT="$(mktemp)"
TMP_STDERR="$(mktemp)"
trap 'rm -f "$TMP_COMPILER" "$TMP_STDOUT" "$TMP_STDERR"' EXIT

echo "重编当前源码得到 staged smoke 编译器..."
"$COMPILER" build src/main.uya -o "$TMP_COMPILER" --no-safety-proof >"$TMP_STDOUT" 2>"$TMP_STDERR"
if [ ! -x "$TMP_COMPILER" ]; then
    echo "✗ staged smoke 编译器未生成"
    cat "$TMP_STDERR"
    exit 1
fi
echo "  self-hosted smoke compiler ✓"

echo "验证默认 proof 路线已越过 frame slot blocker..."
if "$TMP_COMPILER" run --vm src/main.uya >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    grep -q '后端类型: EXEC' "$TMP_STDERR"
else
    grep -q '后端类型: EXEC' "$TMP_STDERR"
    if grep -q 'frame slot 超出上限' "$TMP_STDERR" || grep -q 'VM frame slot 超限' "$TMP_STDERR"; then
        echo "✗ default proof staged smoke still hit frame slot blocker"
        cat "$TMP_STDERR"
        exit 1
    fi
fi
echo "  default proof staged smoke ✓"

echo "验证 --no-safety-proof 路线已越过 frame slot blocker..."
if "$TMP_COMPILER" run --vm src/main.uya --no-safety-proof >"$TMP_STDOUT" 2>"$TMP_STDERR"; then
    grep -q '后端类型: EXEC' "$TMP_STDERR"
else
    grep -q '后端类型: EXEC' "$TMP_STDERR"
    if grep -q 'frame slot 超出上限' "$TMP_STDERR" || grep -q 'VM frame slot 超限' "$TMP_STDERR"; then
        echo "✗ no-safety-proof staged smoke still hit frame slot blocker"
        cat "$TMP_STDERR"
        exit 1
    fi
fi
echo "  no-safety-proof staged smoke ✓"

echo "✓ exec vm compiler staged smoke passed"
