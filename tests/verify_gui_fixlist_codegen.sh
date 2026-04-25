#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

COMPILER="$ROOT/bin/uya"
LINKER="$ROOT/tests/link_cimports_posix.sh"
export UYA_ROOT="${ROOT}/lib/"

mkdir -p "$TMP/option_dep"

cat >"$TMP/option_dep/option_dep.uya" <<'EOF'
use std.core.option.Option;

export struct Event {
    kind: i32,
    value: i32,
}

export fn make_event(kind: i32, value: i32) Event {
    return Event{ kind: kind, value: value };
}

export fn maybe_event(kind: i32) Option<Event> {
    if kind < 0 {
        return Option<Event>.None();
    }
    return Option<Event>.Some(make_event(kind, kind + 1));
}
EOF

cat >"$TMP/option_main.uya" <<'EOF'
use option_dep.Event;
use option_dep.maybe_event;
use std.core.option.Option;
use std.testing.assert_eq_i32;
use std.testing.test_suite_begin;
use std.testing.test_suite_end;
use std.testing.run_test;

fn test_cross_module_option_struct() !void {
    const evt: Option<Event> = maybe_event(4);
    var out: i32 = -1;
    match evt {
        .Some(v) => { out = v.value; },
        .None(_) => { out = -1; },
    };
    try assert_eq_i32(out, 5);
}

export fn main() i32 {
    test_suite_begin("GUI Fixlist Codegen");
    run_test("cross module option struct", test_cross_module_option_struct);
    return test_suite_end();
}
EOF

"$COMPILER" --c99 --nostdlib "$TMP/option_dep/option_dep.uya" "$TMP/option_main.uya" -o "$TMP/option_struct.c"
CC=gcc "$LINKER" "$TMP/option_struct.c" "$TMP/option_struct"
"$TMP/option_struct" >/dev/null

"$COMPILER" build "$ROOT/tests/test_option_struct.uya" --split-c-dir "$TMP/split" -o "$TMP/split_option" --c99
"$TMP/split_option" >/dev/null

"$COMPILER" --c99 --nostdlib "$ROOT/tests/test_const_receiver_codegen.uya" -o "$TMP/const_receiver.c"
gcc --std=c99 -Werror=discarded-qualifiers -c "$TMP/const_receiver.c" -o "$TMP/const_receiver.o"

echo "verify_gui_fixlist_codegen: ok"
