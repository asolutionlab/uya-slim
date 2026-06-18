#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="$(cd "$REPO_ROOT" && pwd)/../uya/bin/uya"
export UYA_ROOT="${UYA_ROOT:-$REPO_ROOT/lib/}"

if [ ! -x "$COMPILER" ]; then
    echo "missing compiler: $COMPILER"
    echo "hint: run 'make uya' first"
    exit 1
fi

run_stage() {
    local name="$1"
    shift
    echo "==> $name"
    "$@"
}

run_uya_test() {
    local rel="$1"
    local log
    log="$(mktemp)"
    if ! "$COMPILER" test "$REPO_ROOT/$rel" >"$log" 2>&1; then
        echo "uya test failed: $rel"
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
}

run_stage "async language and unit matrix" \
    bash "$SCRIPT_DIR/verify_async_full_language_matrix.sh"

run_stage "dynamic resource capacity tests" \
    run_uya_test "tests/test_async_await_capacity_dynamic.uya"
run_stage "async param dynamic capacity" \
    run_uya_test "tests/test_async_param_capacity_dynamic.uya"
run_stage "async frame pool dynamic growth" \
    run_uya_test "tests/test_async_frame_pool_dynamic_growth.uya"
run_stage "async thread pool dynamic growth" \
    run_uya_test "tests/test_async_thread_pool_dynamic_growth.uya"
run_stage "async event config" \
    run_uya_test "tests/test_async_event_config.uya"
run_stage "async multi fd concurrency" \
    run_uya_test "tests/test_async_multi_fd_concurrent.uya"

run_stage "compiler fixed-limit scan" \
    python3 "$SCRIPT_DIR/verify_async_compiler_no_fixed_limits.py"

run_stage "async C99 frame descriptors" \
    bash "$SCRIPT_DIR/verify_c99_async_frame_descriptors.sh"
run_stage "async C99 empty frame descriptors" \
    bash "$SCRIPT_DIR/verify_c99_async_frame_empty_descriptors.sh"
run_stage "async nested split-C codegen" \
    bash "$SCRIPT_DIR/verify_async_nested_split_codegen.sh"
run_stage "async production smoke" \
    bash "$SCRIPT_DIR/verify_async_production_smoke.sh"
run_stage "http async epoll C99 compile" \
    bash "$SCRIPT_DIR/verify_http_bench_async_epoll_compile.sh"

run_stage "pthread stress" \
    bash "$SCRIPT_DIR/stress_pthread.sh"
run_stage "epoll server stress" \
    bash "$SCRIPT_DIR/stress_epoll_server.sh"
run_stage "http async epoll runtime stress" \
    bash "$SCRIPT_DIR/stress_http_async_epoll.sh"
run_stage "http async epoll runtime verify" \
    bash "$SCRIPT_DIR/verify_http_bench_async_epoll_runtime.sh"

run_stage "clean before backup-all" \
    make -C "$REPO_ROOT" clean
run_stage "backup-all" \
    make -C "$REPO_ROOT" backup-all

echo "verify_async_full_dynamic_resources_gate: all stages passed"
