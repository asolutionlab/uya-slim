#!/bin/bash
# benchmarks/run_bench.sh — HTTP 基准测试脚本
#
# 用法: ./run_bench.sh [--baseline]
#
# --baseline: 保存结果到 baseline.json（用于回归对比）
#
# 依赖: wrk, cc, go, bin/uya

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

UYA_BIN="${SCRIPT_DIR}/../bin/uya"
GO_SRC="${SCRIPT_DIR}/http_bench.go"
UYA_ASYNC_SRC="${SCRIPT_DIR}/http_bench_async.uya"
C_SRC="${SCRIPT_DIR}/http_bench.c"

# 编译输出
GO_EXEC="/tmp/http_bench_go"
UYA_ASYNC_EXEC="/tmp/http_bench_async"
C_EXEC="/tmp/http_bench_c"

# wrk 参数（与文档一致）
WRK_THREADS=4
WRK_CONNECTIONS=64
WRK_DURATION=10s

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查依赖
check_dep() {
    if ! command -v "$1" &> /dev/null; then
        log_err "缺少依赖: $1"
        exit 1
    fi
}

# 解析 wrk 输出，返回格式: req|count|dur|p50|p95|p99|rps
parse_wrk() {
    local output="$1"
    local req=0
    local count=0
    local dur=0
    local p50=0
    local p95=0
    local p99=0
    local rps=0

    rps=$(echo "$output" | grep "Requests/sec:" | sed 's/.*Requests\/sec: *//' | awk '{print $1}' | head -1)
    if [ -z "$rps" ]; then rps=0; fi

    req=$(echo "$output" | grep "requests in" | awk '{print $1}' | head -1)
    if [ -z "$req" ]; then req=0; fi

    count=$(echo "$output" | grep "requests in" | awk '{print $4}' | sed 's/s//' | sed 's/,//' | head -1)
    if [ -z "$count" ]; then count=0; fi

    dur=$(echo "$output" | grep "50.00%" | head -1 | awk '{print $2}' | sed 's/[a-zA-Z]//g')
    p95=$(echo "$output" | grep "95.00%" | head -1 | awk '{print $2}' | sed 's/[a-zA-Z]//g')
    p99=$(echo "$output" | grep "99.00%" | head -1 | awk '{print $2}' | sed 's/[a-zA-Z]//g')

    if [ -z "$dur" ] || [ "$dur" = "0" ]; then
        dur=$(echo "$output" | grep "Latency" | head -1 | awk '{print $2}' | sed 's/[a-zA-Z]//g')
    fi
    if [ -z "$p95" ]; then p95=0; fi
    if [ -z "$p99" ]; then p99=0; fi

    echo "$req|$count|$dur|$p50|$p95|$p99|$rps"
}

# 编译 Uya async 版本
build_uya_async() {
    log_info "编译 Uya async HTTP 服务器..."
    if [ ! -f "$UYA_BIN" ]; then
        log_err "找不到 Uya 编译器: $UYA_BIN"
        exit 1
    fi
    "$UYA_BIN" build "$UYA_ASYNC_SRC" -o /tmp/http_bench_async.c --c99 2>&1 | tail -3
    cc -std=c99 -no-pie -O2 -o "$UYA_ASYNC_EXEC" /tmp/http_bench_async.c -lm
    log_info "Uya async 版本编译完成: $UYA_ASYNC_EXEC"
}

# 编译 Go 版本
build_go() {
    log_info "编译 Go HTTP 服务器..."
    if [ ! -f "$GO_SRC" ]; then
        log_err "找不到 Go 源文件: $GO_SRC"
        exit 1
    fi
    go build -o "$GO_EXEC" "$GO_SRC"
    log_info "Go 版本编译完成: $GO_EXEC"
}

# 编译 C 版本
build_c() {
    log_info "编译 C HTTP 服务器..."
    if [ ! -f "$C_SRC" ]; then
        log_err "找不到 C 源文件: $C_SRC"
        exit 1
    fi
    cc -O3 -Wall -Wextra -pthread -o "$C_EXEC" "$C_SRC"
    log_info "C 版本编译完成: $C_EXEC"
}

# 运行服务器并执行基准测试
run_benchmark() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local url="$4"

    echo "--- $name 基准测试 ---" >&2

    # 启动服务器
    "$exec" &
    local pid=$!
    sleep 2

    # 检查服务器是否运行
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: $name 服务器启动失败" >&2
        return 1
    fi

    # 运行 wrk
    echo "运行 wrk -t${WRK_THREADS} -c${WRK_CONNECTIONS} -d${WRK_DURATION} $url" >&2
    local output
    output=$(wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$WRK_DURATION" "$url" 2>&1)
    echo "$output" >&2

    # 解析结果
    local parsed
    parsed=$(parse_wrk "$output")
    IFS='|' read -r req count dur p50 p95 p99 rps <<< "$parsed"

    # 清理服务器
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # 输出结果摘要
    echo "" >&2
    echo "$name 结果:" >&2
    echo "  QPS: ${rps:-0}" >&2
    echo "  总请求: ${count:-0}" >&2
    echo "  耗时: ${dur:-0}s" >&2
    echo "  p50: ${p50:-0}us" >&2
    echo "  p95: ${p95:-0}us" >&2
    echo "  p99: ${p99:-0}us" >&2
    echo "" >&2

    echo "$name|$req|$count|$dur|$p50|$p95|$p99|$rps"
}

# 生成 baseline.json
save_baseline() {
    local uya_root_rps="$1"
    local go_root_rps="$2"
    local c_root_rps="$3"
    local timestamp
    timestamp=$(date -Iseconds)

    log_info "保存基线数据到 baseline.json..."

    cat > "${SCRIPT_DIR}/baseline.json" << EOF
{
  "timestamp": "${timestamp}",
  "machine": {
    "cpu": "Intel(R) Core(TM) i7-14700 (20C/28T)",
    "memory_gb": 31,
    "os": "Deepin 25 (crimson)",
    "kernel": "6.12.65-amd64-desktop-rolling",
    "cc": "Deepin 12.3.0-17deepin15",
    "go": "1.24.2"
  },
  "wrk_params": {
    "threads": ${WRK_THREADS},
    "connections": ${WRK_CONNECTIONS},
    "duration": "${WRK_DURATION}"
  },
  "results": {
    "root": {
      "uya_async_qps": ${uya_root_rps:-0},
      "go_qps": ${go_root_rps:-0},
      "c_qps": ${c_root_rps:-0}
    }
  }
}
EOF
    log_info "基线数据已保存"
}

# 主函数
main() {
    log_info "HTTP 基准测试开始"
    echo ""

    check_dep wrk
    check_dep cc
    check_dep go

    # 编译
    build_uya_async
    build_go
    build_c

    # 测试端口
    local PORT=8876
    local URL="http://127.0.0.1:$PORT/"

    # 预热
    log_info "预热..."
    echo "" | wrk -t1 -c1 -d2s "$URL" >/dev/null 2>&1 || true

    # 运行基准测试
    local uya_result
    local go_result
    local c_result

    uya_result=$(run_benchmark "Uya-async" "$UYA_ASYNC_EXEC" "$PORT" "$URL")
    sleep 1
    go_result=$(run_benchmark "Go" "$GO_EXEC" "$PORT" "$URL")
    sleep 1
    c_result=$(run_benchmark "C" "$C_EXEC" "$PORT" "$URL")

    # 提取 QPS
    local uya_rps
    local go_rps
    local c_rps
    uya_rps=$(echo "$uya_result" | awk -F'|' '{print $8}')
    go_rps=$(echo "$go_result" | awk -F'|' '{print $8}')
    c_rps=$(echo "$c_result" | awk -F'|' '{print $8}')
    if [ -z "$uya_rps" ]; then uya_rps=0; fi
    if [ -z "$go_rps" ]; then go_rps=0; fi
    if [ -z "$c_rps" ]; then c_rps=0; fi

    # 对比
    echo "=========================================="
    log_info "基准测试对比结果"
    echo "=========================================="
    printf "| %-20s | %-15s | %-15s | %-15s |\n" "指标" "Uya-async" "Go" "C"
    echo "|--------------------|-----------------|-----------------|-----------------|"
    printf "| %-20s | %-15s | %-15s | %-15s |\n" "QPS" "${uya_rps:-0}" "${go_rps:-0}" "${c_rps:-0}"
    echo "=========================================="

    # 保存基线（如果指定）
    if [ "$1" = "--baseline" ]; then
        save_baseline "$uya_rps" "$go_rps" "$c_rps"
    fi

    # 清理
    rm -f "$GO_EXEC" "$C_EXEC" "$UYA_ASYNC_EXEC"

    log_info "基准测试完成"
}

main "$@"
