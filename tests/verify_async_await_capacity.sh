#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$(cd "$REPO_ROOT" && pwd)/../uya/bin/uya"
export UYA_ROOT="${UYA_ROOT:-$REPO_ROOT/lib/}"

if [ ! -x "$COMPILER" ]; then
    echo "missing compiler: $COMPILER"
    echo "hint: run 'make uya' first"
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

src="$work_dir/test_async_await_capacity_300.uya"
{
    cat <<'UYA_HEAD'
use std.async;
use std.testing.assert_eq_i32;

fn ready(v: i32) Future<!i32> {
    const p: Poll<!i32> = Poll<!i32>.Ready(ok<i32>(v));
    return Future<!i32>{ state: p };
}

@async_fn
fn await_300_segments() Future<!i32> {
UYA_HEAD
    i=0
    while [ "$i" -lt 300 ]; do
        echo "    const a$i: i32 = try @await ready($i);"
        i=$((i + 1))
    done
    cat <<'UYA_TAIL'
    return a299;
}

test "async_await_capacity_300_segments" {
    const f: Future<!i32> = await_300_segments();
    const bo: !i32 = block_on<i32>(f);
    const v: i32 = bo catch { 0 - 1; };
    try assert_eq_i32(v, 299);
}
UYA_TAIL
} >"$src"

"$COMPILER" test "$src"
