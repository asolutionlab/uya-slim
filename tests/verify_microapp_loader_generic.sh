#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UAPP="/tmp/microcontainer_hello_generic.uapp"

rm -f "$UAPP"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export MICROAPP_TARGET_ARCH
export TARGET_GCC

"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$UAPP" >/tmp/verify_microapp_loader_generic_build.log 2>&1
"$ROOT_DIR/bin/uya" run examples/microapp/microcontainer_hello_load.uya -- "$UAPP" >/tmp/verify_microapp_loader_generic_run.log 2>&1

echo "microapp generic loader ok"
