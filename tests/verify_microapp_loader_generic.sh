#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN_LOG="/tmp/verify_microapp_loader_generic_run.log"
LOADER_LOG="/tmp/verify_microapp_loader_generic_loader.log"
LOADER_UAPP="/tmp/verify_microapp_loader_generic.uapp"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export TARGET_GCC
export MICROAPP_TARGET_ARCH

dump_log_and_fail() {
    local title="$1"
    local path="$2"
    echo "✗ $title"
    if [ -f "$path" ]; then
        echo "--- $path ---"
        cat "$path"
    fi
    exit 1
}

"$ROOT_DIR/bin/uya" run --app microapp examples/microapp/microcontainer_hello_source.uya >"$RUN_LOG" 2>&1

grep -a -q "hello microapp" "$RUN_LOG" || dump_log_and_fail "microapp payload 未输出 hello microapp" "$RUN_LOG"
grep -a -q "\[microapp loader\] done" "$RUN_LOG" || dump_log_and_fail "microapp loader 未输出 done" "$RUN_LOG"

rm -f "$LOADER_UAPP"
"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$LOADER_UAPP" >/tmp/verify_microapp_loader_generic_build.log 2>&1
"$ROOT_DIR/bin/uya" run examples/microapp/microcontainer_hello_load.uya -- "$LOADER_UAPP" >"$LOADER_LOG" 2>&1

grep -a -q "\[microapp loader\] done" "$LOADER_LOG" || dump_log_and_fail "loader-only 路径未输出 done" "$LOADER_LOG"
if grep -a -q "hello microapp" "$LOADER_LOG"; then
    dump_log_and_fail "loader-only 路径意外输出了 payload 文本" "$LOADER_LOG"
fi

echo "microapp run x86_64 ok"
