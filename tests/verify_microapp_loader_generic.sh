#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_LOG="/tmp/verify_microapp_loader_generic_run.log"
LOADER_LOG="/tmp/verify_microapp_loader_generic_loader.log"

"$ROOT_DIR/bin/uya" run --app microapp examples/microapp/microcontainer_hello_source.uya >"$RUN_LOG" 2>&1

grep -a -q "hello microapp" "$RUN_LOG"
grep -a -q "\[microapp loader\] done" "$RUN_LOG"

"$ROOT_DIR/bin/uya" run examples/microapp/microcontainer_hello_load.uya -- examples/microapp/microcontainer_hello.uapp >"$LOADER_LOG" 2>&1

grep -a -q "\[microapp loader\] done" "$LOADER_LOG"
! grep -a -q "hello microapp" "$LOADER_LOG"

echo "microapp run x86_64 ok"
