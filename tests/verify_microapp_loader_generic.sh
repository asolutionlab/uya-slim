#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_LOG="/tmp/verify_microapp_loader_generic_run.log"
MICROAPP_DEBUG_MMU=1 "$ROOT_DIR/bin/uya" run --app microapp examples/microapp/microcontainer_hello_source.uya >"$RUN_LOG" 2>&1

grep -a -q "\[microapp loader\] done" "$RUN_LOG"
! grep -a -q "hello microapp" "$RUN_LOG"

echo "microapp run x86_64 ok"
