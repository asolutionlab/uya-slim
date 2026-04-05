#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/tests"
OUT_POBJ="/tmp/microcontainer_hello.pobj"

rm -f "$OUT_POBJ"

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
: "${MICROAPP_TARGET_ARCH:=x86_64}"
export MICROAPP_TARGET_ARCH
export TARGET_GCC

"$ROOT_DIR/bin/uya" build --app microapp examples/microapp/microcontainer_hello_source.uya -o "$OUT_POBJ" >/tmp/verify_microapp_pobj_manifest.log 2>&1

python3 - <<'PY'
from pathlib import Path
path = Path("/tmp/microcontainer_hello.pobj")
data = path.read_bytes()
source_path = b"examples/microapp/microcontainer_hello_source.uya"
assert len(data) >= 40, len(data)
assert data[:4] == b"POBJ", data[:4]
assert data[4:6] == (5).to_bytes(2, "little"), data[4:6]
assert data[6:8] == (0).to_bytes(2, "little"), data[6:8]
assert int.from_bytes(data[8:12], "little") == 2, data[8:12]
assert int.from_bytes(data[12:16], "little") == 1, data[12:16]
assert int.from_bytes(data[16:20], "little") == 0, data[16:20]
assert int.from_bytes(data[20:24], "little") == 0, data[20:24]
assert int.from_bytes(data[24:28], "little") == len(source_path), data[24:28]
code_len = int.from_bytes(data[28:32], "little")
rodata_len = int.from_bytes(data[32:36], "little")
reloc_count = int.from_bytes(data[36:40], "little")
assert code_len > 0, code_len
assert rodata_len == 0, rodata_len
assert reloc_count == 0, reloc_count
assert data[40:40 + len(source_path)] == source_path, data[40:40 + len(source_path)]
code_off = 40 + len(source_path)
assert len(data) == code_off + code_len, (len(data), code_off, code_len)
PY

echo "microapp pobj manifest ok"
