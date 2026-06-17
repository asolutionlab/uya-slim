#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER="${UYA_COMPILER:-$REPO_ROOT/bin/uya}"
export UYA_ROOT="${UYA_ROOT:-$REPO_ROOT/lib/}"

if [ ! -x "$COMPILER" ]; then
    echo "missing compiler: $COMPILER"
    echo "hint: run 'make uya' first"
    exit 1
fi

run_uya_test() {
    local rel="$1"
    echo "==> uya test $rel"
    "$COMPILER" test "$REPO_ROOT/$rel" >/dev/null
}

# 当前已存在、且对 async 语法主链路最有代表性的回归。
# 这组通过只能证明“当前已覆盖的子集仍成立”，不能证明完整语法已完成。
baseline_tests=(
    "tests/test_async_await_parse.uya"
    "tests/test_async_fn_basic.uya"
    "tests/test_async_await.uya"
    "tests/test_async_await_ready.uya"
    "tests/test_async_multiple_await.uya"
    "tests/test_async_if_await.uya"
    "tests/test_async_else_if_await.uya"
    "tests/test_async_for_await.uya"
    "tests/test_async_while_multi_await.uya"
    "tests/test_async_bug_a_two_while.uya"
    "tests/test_async_bug_b_sync_between.uya"
    "tests/test_async_bug_d_nested_block.uya"
    "tests/test_async_compound_try_await.uya"
    "tests/test_async_fn_multi_segment_unwrap.uya"
    "tests/test_async_await_limits_and_segments.uya"
    "tests/test_async_method_interface.uya"
    "tests/test_async_local_interface_await.uya"
    "tests/test_async_frame_inline_temp.uya"
    "tests/test_async_frame_inline_temp2.uya"
    "tests/test_async_fn_local_fixed_array.uya"
    "tests/test_async_codegen_edge_paths.uya"
    "tests/test_std_async_scheduler.uya"
    "tests/test_async_compute_types.uya"
    "tests/test_http1_async_client.uya"
)

for test_file in "${baseline_tests[@]}"; do
    run_uya_test "$test_file"
done

# 这些测试对应权威 TODO 中仍然缺失或计划新增的“完整语法”覆盖。
# 如果文件还不存在，本脚本应显式失败，提醒矩阵尚未完整。
required_future_tests=(
    "tests/test_async_match_await.uya"
    "tests/test_async_catch_await.uya"
    "tests/test_async_defer_errdefer.uya"
    "tests/test_async_iterator_for_await.uya"
    "tests/test_async_array_ref_for_await.uya"
    "tests/test_async_macro_expand.uya"
    "tests/test_async_nested_future_poll.uya"
    "tests/test_async_large_state_machine_syntax.uya"
)

missing_tests=()
present_future_tests=()
for test_file in "${required_future_tests[@]}"; do
    if [ -f "$REPO_ROOT/$test_file" ]; then
        present_future_tests+=("$test_file")
    else
        missing_tests+=("$test_file")
    fi
done

for test_file in "${present_future_tests[@]}"; do
    run_uya_test "$test_file"
done

if [ "${#missing_tests[@]}" -ne 0 ]; then
    echo
    echo "async full-language matrix is still incomplete"
    echo "missing dedicated tests:"
    for test_file in "${missing_tests[@]}"; do
        echo "  - $test_file"
    done
    echo
    echo "note: legacy limit probes such as tests/error_async_too_many_awaits.uya"
    echo "and tests/error_async_too_many_params.uya are not accepted as proof of"
    echo "the target state, because they encode the old fixed-cap behavior."
    exit 2
fi

echo "verify_async_full_language_matrix: current matrix files present and baseline passed"
