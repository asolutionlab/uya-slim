#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/verify_microapp_payload_symbols.XXXXXX)"
HOST_NM_BIN="$(command -v nm || true)"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

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

if [ -z "$HOST_NM_BIN" ]; then
    echo "✗ microapp payload symbol audit 需要 host nm"
    exit 1
fi

: "${TARGET_GCC:=x86_64-linux-gnu-gcc}"
export TARGET_GCC
export MICROAPP_TARGET_PROFILE=linux_x86_64_hardvm
export MICROAPP_TARGET_ARCH=x86_64

# Linux hard-vm P0 要求编译器对象提取链路不依赖外部 ELF 检查/导出工具。
export READELF=false
export OBJDUMP=false
export NM=false
export OBJCOPY=false

assert_symbol_absent() {
    local symbols_path="$1"
    local symbol="$2"
    local case_name="$3"
    if grep -F -x -q "$symbol" "$symbols_path"; then
        echo "✗ $case_name payload object 不应直接依赖宿主符号: $symbol"
        echo "--- symbols ---"
        cat "$symbols_path"
        exit 1
    fi
}

assert_no_host_symbol_prefix() {
    local symbols_path="$1"
    local prefix="$2"
    local case_name="$3"
    if grep -E -q "^${prefix}" "$symbols_path"; then
        echo "✗ $case_name payload object 不应出现宿主前缀符号: $prefix"
        echo "--- symbols ---"
        cat "$symbols_path"
        exit 1
    fi
}

verify_case() {
    local name="$1"
    local source_rel="$2"
    local expected_output="$3"
    local uapp="$TMP_DIR/$name.uapp"
    local build_log="$TMP_DIR/$name.build.log"
    local run_log="$TMP_DIR/$name.run.log"
    local undefined_log="$TMP_DIR/$name.undefined.log"
    local symbols_log="$TMP_DIR/$name.symbols.log"
    local symbol_names="$TMP_DIR/$name.symbol-names.log"

    "$ROOT_DIR/bin/uya" build --app microapp \
        --microapp-profile linux_x86_64_hardvm \
        "$ROOT_DIR/$source_rel" -o "$uapp" >"$build_log" 2>&1

    grep -q "信息：microapp active profile=linux_x86_64_hardvm" "$build_log" \
        || dump_log_and_fail "$name 未使用 linux_x86_64_hardvm profile" "$build_log"
    grep -q "信息：microapp 目标 gcc 对象产物：" "$build_log" \
        || dump_log_and_fail "$name 未输出目标对象产物路径" "$build_log"
    if grep -q "信息：microapp 目标 gcc 链接：" "$build_log"; then
        dump_log_and_fail "$name 不应回退到中间 ELF 链接链路" "$build_log"
    fi
    if grep -q "信息：microapp 目标 gcc 导出 .text" "$build_log"; then
        dump_log_and_fail "$name 不应依赖 objcopy 导出 .text" "$build_log"
    fi

    local obj_path
    obj_path="$(sed -n 's/^信息：microapp 目标 gcc 对象产物：//p' "$build_log" | tail -n 1)"
    if [ -z "$obj_path" ] || [ ! -f "$obj_path" ]; then
        dump_log_and_fail "$name 目标对象文件不存在: $obj_path" "$build_log"
    fi

    "$HOST_NM_BIN" -u "$obj_path" >"$undefined_log" 2>&1 || dump_log_and_fail "$name 无法读取 undefined symbols" "$undefined_log"
    if [ -s "$undefined_log" ]; then
        dump_log_and_fail "$name payload object 不应包含未解析宿主符号" "$undefined_log"
    fi

    "$HOST_NM_BIN" -a "$obj_path" >"$symbols_log" 2>&1 || dump_log_and_fail "$name 无法读取 symbols" "$symbols_log"
    awk 'NF > 0 { print $NF }' "$symbols_log" >"$symbol_names"

    grep -F -x -q "uya_microapp_bridge_abi_v1" "$symbol_names" \
        || dump_log_and_fail "$name payload object 缺少 bridge ABI slot" "$symbols_log"

    assert_symbol_absent "$symbol_names" "write_stdout_bytes" "$name"
    assert_symbol_absent "$symbol_names" "posix_memalign" "$name"
    assert_symbol_absent "$symbol_names" "sched_yield" "$name"
    assert_symbol_absent "$symbol_names" "gettimeofday" "$name"
    assert_symbol_absent "$symbol_names" "malloc" "$name"
    assert_symbol_absent "$symbol_names" "free" "$name"
    assert_symbol_absent "$symbol_names" "fprintf" "$name"
    assert_symbol_absent "$symbol_names" "getenv" "$name"
    assert_symbol_absent "$symbol_names" "abort" "$name"
    assert_no_host_symbol_prefix "$symbol_names" "UYA_HOST_SYS_" "$name"
    assert_no_host_symbol_prefix "$symbol_names" "uya_microapp_syscall" "$name"

    "$ROOT_DIR/bin/uya" run lib/std/runtime/microapp/loader_main.uya -- "$uapp" >"$run_log" 2>&1
    grep -a -q "$expected_output" "$run_log" \
        || dump_log_and_fail "$name loader 未输出预期内容" "$run_log"
    grep -a -q "\[microapp loader\] executed mapped payload" "$run_log" \
        || dump_log_and_fail "$name loader 未命中 mapped payload 执行分支" "$run_log"
    grep -a -q "\[microapp loader\] payload result=ok" "$run_log" \
        || dump_log_and_fail "$name loader 未输出统一 ok result" "$run_log"
    if grep -a -q "\[microapp loader\] launching native payload" "$run_log"; then
        dump_log_and_fail "$name loader 意外回退 native payload" "$run_log"
    fi
    if grep -a -q "\[microapp loader\] payload result=validated" "$run_log"; then
        dump_log_and_fail "$name call-gate payload 不应停在 validated-only 结果面" "$run_log"
    fi
    if grep -a -q "\[microapp loader\] payload result=unwired" "$run_log"; then
        dump_log_and_fail "$name call-gate payload 不应输出 unwired 结果面" "$run_log"
    fi
}

verify_case "hello" "examples/microapp/microcontainer_hello_source.uya" "hello microapp"
verify_case "alloc_yield" "examples/microapp/microcontainer_alloc_yield_source.uya" "alloc yield ok"
verify_case "time" "examples/microapp/microcontainer_time_source.uya" "time ok"

echo "microapp payload symbol audit ok"
