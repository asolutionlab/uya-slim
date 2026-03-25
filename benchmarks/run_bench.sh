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
UYA_SRC="${SCRIPT_DIR}/http_bench.uya"

# 编译输出
UYA_EXEC="/tmp/http_bench_uya"
GO_EXEC="/tmp/http_bench_go"

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

# 解析 wrk 输出
parse_wrk() {
    local output="$1"
    local requests=0
    local duration=0
    local p50=0
    local p95=0
    local p99=0
    local requests_per_sec=0

    # 解析 Requests/sec
    requests_per_sec=$(echo "$output" | grep "Requests/sec:" | awk '{print $2}' | head -1)

    # 解析总请求数
    requests=$(echo "$output" | grep "requests in" | awk '{print $1}' | head -1)

    # 解析耗时
    duration=$(echo "$output" | grep "requests in" | awk '{print $4}' | sed 's/s//' | head -1)

    # 解析延迟百分位 (Latency Distribution)
    # wrk 输出格式: "50.00%  <latency>    95.00%  <latency>    99.00%  <latency>"
    local lat_line=$(echo "$output" | grep -A 1 "Latency Distribution")
    if [ -n "$lat_line" ]; then
        p50=$(echo "$output" | awk '/50\.00%/{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
        p95=$(echo "$output" | awk '/95\.00%/{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
        p99=$(echo "$output" | awk '/99\.00%/{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
    else
        # 备选：直接从 Latency 行解析
        p50=$(echo "$output" | grep "50%" | awk '{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
        p95=$(echo "$output" | grep "95%" | awk '{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
        p99=$(echo "$output" | grep "99%" | awk '{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
    fi

    # 如果百分位为空，尝试解析 Avg/Stdev/Max
    if [ -z "$p50" ]; then
        p50=$(echo "$output" | grep "Latency" | awk '{print $2}' | sed 's/[a-zA-Z]//g' | head -1)
    fi

    echo "$requests|$duration|$p50|$p95|$p99|$requests_per_sec"
}

# 解析延迟值（带单位）
parse_latency() {
    local val="$1"
    # 移除单位并转换为微秒
    if [[ "$val" =~ ^[0-9.]+[a-zA-Z]+$ ]]; then
        local num=$(echo "$val" | sed 's/[a-zA-Z]//g')
        if [[ "$val" == *"ms" ]]; then
            echo "$num" | awk '{printf "%.2f", $1 * 1000}'
        elif [[ "$val" == *"s" ]]; then
            echo "$num" | awk '{printf "%.2f", $1 * 1000000}'
        elif [[ "$val" == *"us"* ]] || [[ "$val" == *"µs"* ]]; then
            echo "$num"
        else
            echo "$val"
        fi
    else
        echo "$val"
    fi
}

# 编译 Uya 版本
build_uya() {
    log_info "编译 Uya HTTP 服务器..."
    if [ ! -f "$UYA_BIN" ]; then
        log_err "找不到 Uya 编译器: $UYA_BIN"
        exit 1
    fi
    rm -f /tmp/http_bench_uya.c
    "$UYA_BIN" --c99 "$UYA_SRC" -o /tmp/http_bench_uya.c
    cc -std=c99 -no-pie -O2 -o "$UYA_EXEC" /tmp/http_bench_uya.c -lm
    log_info "Uya 版本编译完成: $UYA_EXEC"
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

# 运行服务器并执行基准测试
run_benchmark() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local url="$4"

    log_info "--- $name 基准测试 ---"

    # 启动服务器
    if [ "$name" = "Uya" ]; then
        "$exec" &
    else
        "$exec" &
    fi
    local pid=$!
    sleep 0.5  # 等待服务器启动

    # 检查服务器是否运行
    if ! kill -0 "$pid" 2>/dev/null; then
        log_err "$name 服务器启动失败"
        return 1
    fi

    # 运行 wrk
    log_info "运行 wrk -t${WRK_THREADS} -c${WRK_CONNECTIONS} -d${WRK_DURATION} $url"
    local output
    output=$(wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$WRK_DURATION" "$url" 2>&1)
    echo "$output"

    # 解析结果
    local parsed
    parsed=$(parse_wrk "$output")
    IFS='|' read -r req count dur p50 p95 p99 rps <<< "$parsed"

    # 清理服务器
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    # 输出结果摘要
    echo ""
    log_info "$name 结果:"
    echo "  QPS: ${rps:-0}"
    echo "  总请求: ${count:-0}"
    echo "  耗时: ${dur:-0}s"
    echo "  p50: ${p50:-0}us"
    echo "  p95: ${p95:-0}us"
    echo "  p99: ${p99:-0}us"
    echo ""

    # 返回结果供后续处理
    echo "$name|$req|$count|$dur|$p50|$p95|$p99|$rps"
}

# 运行单个测试路由
run_route_benchmark() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local route="$4"
    local url="http://127.0.0.1:$port$route"

    # 启动服务器
    if [ "$name" = "Uya" ]; then
        "$exec" &
    else
        "$exec" &
    fi
    local pid=$!
    sleep 0.3

    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # 运行 wrk
    local output
    output=$(wrk -t"$WRK_THREADS" -c"$WRK_CONNECTIONS" -d"$WRK_DURATION" "$url" 2>&1)

    # 解析
    local parsed
    parsed=$(parse_wrk "$output")
    IFS='|' read -r req count dur p50 p95 p99 rps <<< "$parsed"

    # 清理
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    echo "$rps|$p50|$p95|$p99"
}

# 生成 baseline.json
save_baseline() {
    local uya_root_rps="$1"
    local go_root_rps="$2"
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
      "uya_qps": ${uya_root_rps:-0},
      "go_qps": ${go_root_rps:-0}
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
    build_uya
    build_go

    # 测试端口
    local PORT=8876
    local URL="http://127.0.0.1:$PORT/"

    # 预热
    log_info "预热..."
    echo "" | wrk -t1 -c1 -d2s "$URL" >/dev/null 2>&1 || true

    # 运行基准测试
    local uya_result
    local go_result

    uya_result=$(run_benchmark "Uya" "$UYA_EXEC" "$PORT" "$URL")
    sleep 1
    go_result=$(run_benchmark "Go" "$GO_EXEC" "$PORT" "$URL")

    # 提取 QPS
    local uya_rps
    local go_rps
    uya_rps=$(echo "$uya_result" | awk -F'|' '{print $8}')
    go_rps=$(echo "$go_result" | awk -F'|' '{print $8}')

    # 对比
    echo "=========================================="
    log_info "基准测试对比结果"
    echo "=========================================="
    printf "| %-20s | %-15s | %-15s |\n" "指标" "Uya" "Go"
    echo "|--------------------|-----------------|-----------------|"
    printf "| %-20s | %-15s | %-15s |\n" "QPS" "${uya_rps:-0}" "${go_rps:-0}"
    echo "=========================================="

    # 保存基线（如果指定）
    if [ "$1" = "--baseline" ]; then
        save_baseline "$uya_rps" "$go_rps"
    fi

    # 清理
    rm -f /tmp/http_bench_uya.c "$UYA_EXEC" "$GO_EXEC"

    log_info "基准测试完成"
}

main "$@"
