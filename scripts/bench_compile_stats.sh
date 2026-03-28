#!/usr/bin/env bash

set -euo pipefail

RUNS=1
MODE="nostdlib"
VERBOSE=0

usage() {
    cat <<'EOF'
用法: bash scripts/bench_compile_stats.sh [选项]

选项:
  --runs N     运行 N 次并输出逐次结果与平均值（默认: 1）
  --hosted     使用 hosted 链接路径（默认: nostdlib）
  --verbose    打印每次编译的完整输出
  -h, --help   显示帮助

示例:
  bash scripts/bench_compile_stats.sh
  bash scripts/bench_compile_stats.sh --runs 3
  bash scripts/bench_compile_stats.sh --hosted --runs 2
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --hosted)
            MODE="hosted"
            shift
            ;;
        --verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "错误: 未知参数: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || [[ "$RUNS" -lt 1 ]]; then
    echo "错误: --runs 必须是大于等于 1 的整数" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$REPO_ROOT/src"

if [[ ! -x "$REPO_ROOT/bin/uya" ]]; then
    echo "bin/uya 不存在，先执行 make from-c ..." >&2
    make -C "$REPO_ROOT" from-c >/dev/null
fi

extract_stat() {
    local label="$1"
    local text="$2"
    local value
    value="$(printf '%s\n' "$text" | awk -F': ' -v label="$label" '
        $1 == label {
            split($2, parts, " ");
            result = parts[1];
        }
        END {
            if (result == "") {
                exit 1;
            }
            print result;
        }
    ')"
    printf '%s\n' "$value"
}

run_once() {
    local run_index="$1"
    local -a cmd=(./compile.sh --c99 -e -v)
    if [[ "$MODE" == "nostdlib" ]]; then
        cmd+=(--nostdlib)
    fi

    local output
    if ! output="$(cd "$SRC_DIR" && "${cmd[@]}" 2>&1)"; then
        printf '%s\n' "$output" >&2
        return 1
    fi

    if [[ "$VERBOSE" -ne 0 ]]; then
        printf '===== run %s raw output =====\n%s\n' "$run_index" "$output" >&2
    fi

    local files parse_ms merge_ms check_ms opt_ms codegen_ms total_ms
    files="$(extract_stat "文件数" "$output")"
    parse_ms="$(extract_stat "解析耗时" "$output")"
    merge_ms="$(extract_stat "合并耗时" "$output")"
    check_ms="$(extract_stat "检查耗时" "$output")"
    opt_ms="$(extract_stat "优化耗时" "$output")"
    codegen_ms="$(extract_stat "生成耗时" "$output")"
    total_ms="$(extract_stat "总耗时" "$output")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$files" "$parse_ms" "$merge_ms" "$check_ms" "$opt_ms" "$codegen_ms" "$total_ms"
}

sum_files=0
sum_parse=0
sum_merge=0
sum_check=0
sum_opt=0
sum_codegen=0
sum_total=0

printf 'run\tfiles\tparse_ms\tmerge_ms\tcheck_ms\topt_ms\tcodegen_ms\ttotal_ms\n'

run=1
while [[ "$run" -le "$RUNS" ]]; do
    result_line="$(run_once "$run")"
    IFS=$'\t' read -r files parse_ms merge_ms check_ms opt_ms codegen_ms total_ms <<< "$result_line"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$run" "$files" "$parse_ms" "$merge_ms" "$check_ms" "$opt_ms" "$codegen_ms" "$total_ms"

    sum_files=$((sum_files + files))
    sum_parse=$((sum_parse + parse_ms))
    sum_merge=$((sum_merge + merge_ms))
    sum_check=$((sum_check + check_ms))
    sum_opt=$((sum_opt + opt_ms))
    sum_codegen=$((sum_codegen + codegen_ms))
    sum_total=$((sum_total + total_ms))
    run=$((run + 1))
done

if [[ "$RUNS" -gt 1 ]]; then
    printf 'avg\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$((sum_files / RUNS))" \
        "$((sum_parse / RUNS))" \
        "$((sum_merge / RUNS))" \
        "$((sum_check / RUNS))" \
        "$((sum_opt / RUNS))" \
        "$((sum_codegen / RUNS))" \
        "$((sum_total / RUNS))"
fi
