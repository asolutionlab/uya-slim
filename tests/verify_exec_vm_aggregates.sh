#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${REPO_ROOT}/lib/"

TMP_STDOUT="$(mktemp)"
TMP_STDERR="$(mktemp)"
trap 'rm -f "$TMP_STDOUT" "$TMP_STDERR"' EXIT

echo "验证 exec vm 聚合值基础路径..."
"$COMPILER" run --vm "$SCRIPT_DIR/test_exec_vm_aggregates.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
echo "  run --vm aggregates ✓"

echo "验证 exec fallback 路径..."
"$COMPILER" run --exec "$SCRIPT_DIR/test_exec_vm_aggregates.uya" >"$TMP_STDOUT" 2>"$TMP_STDERR"
echo "  run --exec aggregates ✓"

echo "✓ exec vm aggregates checks passed"
