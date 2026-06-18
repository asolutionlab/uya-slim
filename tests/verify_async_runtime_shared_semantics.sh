#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$REPO_ROOT/../uya/bin/uya"
export UYA_ROOT="${UYA_ROOT:-$REPO_ROOT/lib/}"

if [ ! -x "$COMPILER" ]; then
    echo "missing compiler: $COMPILER"
    echo "hint: run 'make uya' first"
    exit 1
fi

run_uya_test() {
    local rel="$1"
    local log
    log="$(mktemp)"
    echo "==> uya test $rel"
    if ! "$COMPILER" test "$REPO_ROOT/$rel" >"$log" 2>&1; then
        echo "uya test failed: $rel"
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
}

if [ "$(uname -s)" != "Linux" ]; then
    echo "verify_async_runtime_shared_semantics requires Linux epoll"
    exit 1
fi

runtime_tests=(
    "tests/test_std_async_scheduler.uya"
    "tests/test_async_multi_fd_concurrent.uya"
    "tests/test_async_fd.uya"
    "tests/test_std_thread.uya"
    "tests/test_async_compute_types.uya"
    "tests/test_async_shared_runtime_semantics.uya"
    "tests/test_http1_async_client.uya"
    "tests/test_std_dns_async_transport.uya"
    "tests/test_https_loopback.uya"
)

for test_file in "${runtime_tests[@]}"; do
    run_uya_test "$test_file"
done

echo "verify_async_runtime_shared_semantics: shared async runtime baseline passed"
