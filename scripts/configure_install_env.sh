#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: configure_install_env.sh --bindir DIR [--destdir DIR] [--profile FILE]

Configure the user's shell startup files so installed Uya binaries are
available from new shells.
EOF
}

INSTALL_BINDIR=""
INSTALL_DESTDIR="${DESTDIR:-}"
INSTALL_PROFILE="${INSTALL_PROFILE:-}"
INSTALL_CONFIGURE_ENV="${INSTALL_CONFIGURE_ENV:-1}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bindir)
            INSTALL_BINDIR="${2:-}"
            shift 2
            ;;
        --destdir)
            INSTALL_DESTDIR="${2:-}"
            shift 2
            ;;
        --profile)
            INSTALL_PROFILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "configure_install_env: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$INSTALL_CONFIGURE_ENV" = "0" ] || [ "$INSTALL_CONFIGURE_ENV" = "false" ]; then
    echo "跳过 PATH 配置: INSTALL_CONFIGURE_ENV=$INSTALL_CONFIGURE_ENV"
    exit 0
fi

if [ -n "$INSTALL_DESTDIR" ]; then
    echo "跳过 PATH 配置: DESTDIR 打包安装不会修改用户 shell 配置"
    exit 0
fi

if [ -z "$INSTALL_BINDIR" ]; then
    echo "configure_install_env: --bindir is required" >&2
    exit 2
fi

abs_path() {
    local input="$1"
    local dir
    local base

    if [ -d "$input" ]; then
        (cd "$input" && pwd -P)
        return
    fi

    dir="$(dirname "$input")"
    base="$(basename "$input")"
    if [ -d "$dir" ]; then
        printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
        return
    fi

    case "$input" in
        /*) printf '%s\n' "$input" ;;
        *) printf '%s/%s\n' "$(pwd -P)" "$input" ;;
    esac
}

shell_quote() {
    printf "'"
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

path_is_standard() {
    case "$1" in
        /bin|/usr/bin|/usr/local/bin|/sbin|/usr/sbin)
            return 0
            ;;
    esac
    return 1
}

path_has_entry() {
    case ":${PATH:-}:" in
        *":$1:"*) return 0 ;;
    esac
    return 1
}

profile_has_path() {
    local profile="$1"
    local bindir="$2"
    local rel=""

    [ -f "$profile" ] || return 1

    if grep -F "$bindir" "$profile" >/dev/null 2>&1; then
        return 0
    fi

    if [ -n "${HOME:-}" ] && [ "$bindir" != "$HOME" ] && [[ "$bindir" == "$HOME"/* ]]; then
        rel="${bindir#"$HOME"/}"
        if grep -F "\$HOME/$rel" "$profile" >/dev/null 2>&1; then
            return 0
        fi
        if grep -F "\${HOME}/$rel" "$profile" >/dev/null 2>&1; then
            return 0
        fi
        if grep -F "~/$rel" "$profile" >/dev/null 2>&1; then
            return 0
        fi
    fi

    return 1
}

append_profile_path() {
    local profile="$1"
    local bindir="$2"
    local quoted_bindir
    local profile_dir

    profile_dir="$(dirname "$profile")"
    mkdir -p "$profile_dir"
    touch "$profile"

    quoted_bindir="$(shell_quote "$bindir")"
    cat >> "$profile" <<EOF

# Uya installer: add installed binaries to PATH.
_uya_install_bindir=$quoted_bindir
case ":\$PATH:" in
    *":\$_uya_install_bindir:"*) ;;
    *) export PATH="\$_uya_install_bindir:\$PATH" ;;
esac
unset _uya_install_bindir
EOF
}

add_profile() {
    local profile="$1"
    local existing

    [ -n "$profile" ] || return
    for existing in "${PROFILES[@]}"; do
        if [ "$existing" = "$profile" ]; then
            return
        fi
    done
    PROFILES+=("$profile")
}

INSTALL_BINDIR_ABS="$(abs_path "$INSTALL_BINDIR")"

if path_is_standard "$INSTALL_BINDIR_ABS" && path_has_entry "$INSTALL_BINDIR_ABS"; then
    echo "PATH 已包含标准安装目录: $INSTALL_BINDIR_ABS"
    exit 0
fi

PROFILES=()
if [ -n "$INSTALL_PROFILE" ]; then
    add_profile "$(abs_path "$INSTALL_PROFILE")"
else
    shell_name="$(basename "${SHELL:-}")"
    if [ "$shell_name" = "bash" ] || [ -f "${HOME:-}/.bashrc" ]; then
        add_profile "${HOME:?HOME is required}/.bashrc"
    fi
    if [ "$shell_name" = "zsh" ] || [ -f "${HOME:-}/.zshrc" ]; then
        add_profile "${HOME:?HOME is required}/.zshrc"
    fi
    if [ -f "${HOME:-}/.profile" ] || [ "${#PROFILES[@]}" -eq 0 ]; then
        add_profile "${HOME:?HOME is required}/.profile"
    fi
fi

changed=0
for profile in "${PROFILES[@]}"; do
    if profile_has_path "$profile" "$INSTALL_BINDIR_ABS"; then
        echo "PATH 已配置: $profile -> $INSTALL_BINDIR_ABS"
        continue
    fi

    append_profile_path "$profile" "$INSTALL_BINDIR_ABS"
    echo "已添加 PATH 配置: $profile -> $INSTALL_BINDIR_ABS"
    changed=1
done

if [ "$changed" -eq 1 ]; then
    echo "提示: 重新打开终端或执行 source ~/.bashrc 后即可直接使用 uya"
fi
