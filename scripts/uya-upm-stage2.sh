#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_STAGE2_COMPILER:-$ROOT_DIR/bin/uya}"
UPM_BIN="${UYA_STAGE2_UPM_BIN:-$ROOT_DIR/bin/cmd/upm}"

if [ ! -x "$COMPILER" ]; then
    echo "错误: 缺少编译器 $COMPILER" >&2
    exit 1
fi

if [ -z "${UYA_ROOT:-}" ]; then
    export UYA_ROOT="$ROOT_DIR/lib/"
fi

if [ "$#" -gt 0 ]; then
    case "$1" in
        upm)
            if [ ! -x "$UPM_BIN" ]; then
                echo "错误: 缺少可执行子命令 $UPM_BIN；请先运行 make cmds" >&2
                exit 1
            fi
            shift
            exec "$UPM_BIN" "$@"
            ;;
        build)
            if [ -x "$UPM_BIN" ]; then
                exec "$UPM_BIN" "$@"
            fi
            ;;
    esac
fi

exec "$COMPILER" "$@"
