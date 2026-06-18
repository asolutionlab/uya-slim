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

expect_check_fail() {
    local rel="$1"
    local pattern="$2"
    local log
    log="$(mktemp)"
    if "$COMPILER" check "$REPO_ROOT/$rel" >"$log" 2>&1; then
        echo "expected checker failure but succeeded: $rel"
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    if ! grep -Fq "$pattern" "$log"; then
        echo "missing expected diagnostic for $rel: $pattern"
        cat "$log"
        rm -f "$log"
        exit 1
    fi
    rm -f "$log"
}

expect_compile_fail() {
    local rel="$1"
    local pattern="$2"
    local work_dir
    local log
    work_dir="$(mktemp -d)"
    log="$(mktemp)"
    if (cd "$work_dir" && UYA_ROOT="$UYA_ROOT" "$COMPILER" --c99 --safety-proof "$REPO_ROOT/$rel") >"$log" 2>&1; then
        echo "expected compile failure but succeeded: $rel"
        cat "$log"
        rm -rf "$work_dir"
        rm -f "$log"
        exit 1
    fi
    if ! grep -Fq "$pattern" "$log"; then
        echo "missing expected compile diagnostic for $rel: $pattern"
        cat "$log"
        rm -rf "$work_dir"
        rm -f "$log"
        exit 1
    fi
    rm -rf "$work_dir"
    rm -f "$log"
}

# 当前已存在、且对 async 语法主链路最有代表性的回归。
# 这组通过只能证明“当前已覆盖的子集仍成立”，不能证明完整语法已完成。
baseline_tests=(
    "tests/test_async_await_parse.uya"
    "tests/test_async_fn_basic.uya"
    "tests/test_async_await.uya"
    "tests/test_async_await_ready.uya"
    "tests/test_async_multiple_await.uya"
    "tests/test_async_state_machine.uya"
    "tests/test_async_if_await.uya"
    "tests/test_async_else_if_await.uya"
    "tests/test_async_for_await.uya"
    "tests/test_async_while_multi_await.uya"
    "tests/test_async_bug_a_two_while.uya"
    "tests/test_async_bug_b_sync_between.uya"
    "tests/test_async_bug_d_nested_block.uya"
    "tests/test_async_await_direct_err_union.uya"
    "tests/test_async_return_error_direct.uya"
    "tests/test_async_compound_try_await.uya"
    "tests/test_async_catch_await.uya"
    "tests/test_async_fn_multi_segment_unwrap.uya"
    "tests/test_async_await_limits_and_segments.uya"
    "tests/test_async_sync_body_matrix.uya"
    "tests/test_async_method_interface.uya"
    "tests/test_async_local_interface_await.uya"
    "tests/test_async_nested.uya"
    "tests/test_async_macro_expand.uya"
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

# 规范明确禁止的 @await 位置，必须继续保持失败。
expect_check_fail "tests/error_await_outside_async.uya" "@await 只能在 @async_fn 函数内使用"
expect_check_fail "tests/error_async_await_in_while_cond.uya" "@async_fn 状态机结构验证失败"
expect_check_fail "tests/error_async_await_in_return.uya" "@async_fn 状态机结构验证失败"
expect_compile_fail "tests/error_async_for_iterator_interface_await.uya" "接口类型变量的 for 迭代目前不支持；请使用具体实现迭代器类型"

# 2026-06-18: struct 迭代器 ref 绑定现已支持，转为正向回归。
run_uya_test "tests/test_async_for_iterator_ref_await.uya"

# nested future 真实边界专项验证（正向编译边界）
echo "==> verify_async_nested_future_boundary"
bash "$SCRIPT_DIR/verify_async_nested_future_boundary.sh" >/dev/null

# 宏展开 async lowering 程序级回归
echo "==> test_ai_prompt_async_macro_combo build/run"
macro_log="$(mktemp)"
if ! (
    cd "$REPO_ROOT"
    UYA_ROOT="$UYA_ROOT" "$COMPILER" run "tests/programs/test_ai_prompt_async_macro_combo.uya" >"$macro_log" 2>&1
); then
    echo "macro combo build/run failed"
    cat "$macro_log"
    rm -f "$macro_log"
    exit 1
fi
rm -f "$macro_log"

echo "verify_async_full_language_matrix: positive matrix (30 tests), iterator for boundaries, forbidden @await positions, nested future boundary, and macro combo passed"
