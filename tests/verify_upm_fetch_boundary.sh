#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT_DIR/src/cmd/upm/upm_lib/resolver.uya"
FETCHER="$ROOT_DIR/src/cmd/upm/upm_lib/git_fetch.uya"

grep -q 'export fn upm_fetch_prepare_checkout' "$FETCHER"
grep -q 'use cmd.upm.upm_lib.git_fetch.upm_fetch_prepare_checkout;' "$RESOLVER"
if grep -q 'upm_git_prepare_checkout' "$RESOLVER"; then
    echo "resolver must use the generic fetch boundary" >&2
    exit 1
fi

echo "verify_upm_fetch_boundary: ok"
