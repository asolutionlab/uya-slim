#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/verify_microapp_profile_matrix.XXXXXX)"
SOURCE="$ROOT_DIR/examples/microapp/microcontainer_hello_source.uya"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

dump_and_fail() {
    local title="$1"
    local path="${2:-}"
    echo "✗ $title"
    if [ -n "$path" ] && [ -f "$path" ]; then
        echo "--- $path ---"
        cat "$path"
    fi
    exit 1
}

verify_profile_compile_to_c() {
    local profile="$1"
    local expected_bridge="$2"
    local expected_arch="$3"
    local out_c="$TMP_DIR/${profile}.c"
    local log="$TMP_DIR/${profile}.log"

    if ! "$ROOT_DIR/bin/uya" build --app microapp \
        --microapp-profile "$profile" \
        "$SOURCE" -o "$out_c" >"$log" 2>&1; then
        dump_and_fail "profile matrix 编译失败: $profile" "$log"
    fi
    if [ ! -s "$out_c" ]; then
        dump_and_fail "profile matrix 未生成 C 输出: $profile" "$log"
    fi

    grep -q "信息：microapp active profile=${profile}, bridge=${expected_bridge}," "$log" \
        || dump_and_fail "profile matrix 未命中 profile/bridge 诊断: $profile" "$log"
    grep -q "目标架构=${expected_arch}" "$log" \
        || dump_and_fail "profile matrix 未命中目标架构诊断: $profile" "$log"
}

verify_profile_compile_to_c "linux_x86_64_hardvm" "call_gate" "x86_64"
verify_profile_compile_to_c "linux_aarch64_hardvm" "call_gate" "aarch64"
verify_profile_compile_to_c "macos_arm64_hardvm" "call_gate" "aarch64"
verify_profile_compile_to_c "rv32_baremetal_softvm" "trap" "rv32"
verify_profile_compile_to_c "xtensa_baremetal_softvm" "trap" "xtensa"

X86_UAPP="$TMP_DIR/linux_x86_64_hardvm.uapp"
X86_INSPECT="$TMP_DIR/linux_x86_64_hardvm.inspect.log"
if ! TARGET_GCC=x86_64-linux-gnu-gcc \
    "$ROOT_DIR/bin/uya" build --app microapp \
    --microapp-profile linux_x86_64_hardvm \
    "$SOURCE" -o "$X86_UAPP" >"$TMP_DIR/linux_x86_64_hardvm.uapp.log" 2>&1; then
    dump_and_fail "profile matrix x86_64 .uapp 构建失败" "$TMP_DIR/linux_x86_64_hardvm.uapp.log"
fi

"$ROOT_DIR/bin/uya" inspect-image "$X86_UAPP" >"$X86_INSPECT" 2>&1
grep -q '^profile=linux_x86_64_hardvm$' "$X86_INSPECT" \
    || dump_and_fail "profile matrix x86_64 .uapp inspect 未命中 profile" "$X86_INSPECT"
grep -q '^bridge=call_gate$' "$X86_INSPECT" \
    || dump_and_fail "profile matrix x86_64 .uapp inspect 未命中 bridge" "$X86_INSPECT"

echo "microapp profile example matrix ok"
