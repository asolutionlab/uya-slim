#!/usr/bin/env bash
# 压测 tests/test_pthread.uya（全量编译+运行）。失败即停，退出码非 0。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UYA="${UYA:-./bin/uya}"
N="${1:-100}"
failed=0
for i in $(seq 1 "$N"); do
  if ! "$UYA" test tests/test_pthread.uya >/dev/null 2>&1; then
    echo "fail at iteration $i (exit $?)"
    failed=1
    break
  fi
done
if [[ "$failed" -eq 0 ]]; then
  echo "ok: $N iterations"
fi
exit "$failed"
