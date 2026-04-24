#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GO_BIN="${GO:-}"

if [[ -z "${GO_BIN}" ]]; then
  if command -v go >/dev/null 2>&1; then
    GO_BIN="$(command -v go)"
  elif [[ -x /home/winger/work/go/bin/go ]]; then
    GO_BIN="/home/winger/work/go/bin/go"
  else
    echo "error: go not found; set GO=/path/to/go" >&2
    exit 1
  fi
fi

echo "== UyaGin Router Benchmark =="
echo
echo "-- Uya --"
(
  cd "$ROOT_DIR"
  UYA_SPLIT_C=0 ./bin/uya-hosted run benchmarks/uyagin_route_bench.uya
)

echo
echo "-- Gin --"
(
  cd "$ROOT_DIR/benchmarks"
  "$GO_BIN" test ./gin_route_bench -run '^$' -bench '^BenchmarkUyaginRouteGin$' -benchmem
)
