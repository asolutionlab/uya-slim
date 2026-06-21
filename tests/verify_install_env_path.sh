#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/configure_install_env.sh"
TMP_DIR="$(mktemp -d /tmp/uya_install_env_path.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_contains() {
    local file="$1"
    local needle="$2"
    if ! grep -F "$needle" "$file" >/dev/null 2>&1; then
        echo "missing expected text in $file: $needle" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local needle="$2"
    if grep -F "$needle" "$file" >/dev/null 2>&1; then
        echo "unexpected text in $file: $needle" >&2
        exit 1
    fi
}

home_one="$TMP_DIR/home_one"
prefix_one="$TMP_DIR/prefix_one"
mkdir -p "$home_one" "$prefix_one/bin"
: > "$home_one/.bashrc"
: > "$home_one/.profile"

HOME="$home_one" SHELL=/bin/bash PATH=/usr/bin:/bin \
    "$SCRIPT" --bindir "$prefix_one/bin" >/tmp/uya_install_env_path_one.log

assert_contains "$home_one/.bashrc" "$prefix_one/bin"
assert_contains "$home_one/.profile" "$prefix_one/bin"

bashrc_before="$(wc -l < "$home_one/.bashrc")"
profile_before="$(wc -l < "$home_one/.profile")"
HOME="$home_one" SHELL=/bin/bash PATH=/usr/bin:/bin \
    "$SCRIPT" --bindir "$prefix_one/bin" >/tmp/uya_install_env_path_idempotent.log
bashrc_after="$(wc -l < "$home_one/.bashrc")"
profile_after="$(wc -l < "$home_one/.profile")"

if [ "$bashrc_before" != "$bashrc_after" ] || [ "$profile_before" != "$profile_after" ]; then
    echo "PATH profile configuration is not idempotent" >&2
    exit 1
fi

home_two="$TMP_DIR/home_two"
mkdir -p "$home_two/.local/bin"
cat > "$home_two/.bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
EOF

HOME="$home_two" SHELL=/bin/bash PATH=/usr/bin:/bin \
    "$SCRIPT" --bindir "$home_two/.local/bin" >/tmp/uya_install_env_path_existing.log
assert_not_contains "$home_two/.bashrc" "Uya installer"

home_three="$TMP_DIR/home_three"
prefix_three="$TMP_DIR/prefix_three"
mkdir -p "$home_three" "$prefix_three/bin"
: > "$home_three/.bashrc"

HOME="$home_three" SHELL=/bin/bash PATH=/usr/bin:/bin \
    "$SCRIPT" --bindir "$prefix_three/bin" --destdir "$TMP_DIR/stage" >/tmp/uya_install_env_path_destdir.log
assert_not_contains "$home_three/.bashrc" "$prefix_three/bin"

home_four="$TMP_DIR/home_four"
prefix_four="$TMP_DIR/prefix_four"
mkdir -p "$home_four" "$prefix_four/bin"
: > "$home_four/.bashrc"

HOME="$home_four" SHELL=/bin/bash PATH=/usr/bin:/bin INSTALL_CONFIGURE_ENV=0 \
    "$SCRIPT" --bindir "$prefix_four/bin" >/tmp/uya_install_env_path_disabled.log
assert_not_contains "$home_four/.bashrc" "$prefix_four/bin"

home_five="$TMP_DIR/home_five"
prefix_five="$TMP_DIR/prefix_five"
custom_profile="$home_five/uya-env.sh"
mkdir -p "$home_five" "$prefix_five/bin"

HOME="$home_five" SHELL=/bin/zsh PATH=/usr/bin:/bin INSTALL_PROFILE="$custom_profile" \
    "$SCRIPT" --bindir "$prefix_five/bin" >/tmp/uya_install_env_path_profile.log
assert_contains "$custom_profile" "$prefix_five/bin"

echo "verify_install_env_path: ok"
