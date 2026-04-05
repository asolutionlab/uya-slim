#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UAPP="/tmp/microcontainer_hello_direct.uapp"

rm -f "$UAPP"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export MICROAPP_TARGET_ARCH
export TARGET_GCC

"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$UAPP" >/tmp/verify_microapp_build_uapp.log 2>&1

python3 - <<'PY'
from pathlib import Path
path = Path("/tmp/microcontainer_hello_direct.uapp")
data = path.read_bytes()
assert len(data) >= 100, len(data)
assert data[:4] == b"\x00AYU", data[:4]
assert data[4:6] == (1).to_bytes(2, "little"), data[4:6]
assert data[6:8] == (1).to_bytes(2, "little"), data[6:8]
code_size = int.from_bytes(data[16:20], "little")
rodata_size = int.from_bytes(data[20:24], "little")
entry_offset = int.from_bytes(data[12:16], "little")
build_mode = data[64]
target_arch = data[65]
assert code_size > 0, code_size
assert rodata_size == 0, rodata_size
assert entry_offset == 0, entry_offset
assert build_mode == 1, build_mode
assert target_arch == 2, target_arch
PY

echo "microapp build-to-uapp ok"
