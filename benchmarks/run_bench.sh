#!/bin/bash
# benchmarks/run_bench.sh — HTTP 基准测试脚本
#
# 用法: ./run_bench.sh [--baseline]
#
# --baseline: 保存结果到 baseline.json（用于回归对比）
#
# 依赖: wrk, cc, go, cargo（可选 Rust Tokio 对照）, bin/uya

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

UYA_BIN="${SCRIPT_DIR}/../bin/uya"
GO_SRC="${SCRIPT_DIR}/http_bench.go"
UYA_FORK_SRC="${SCRIPT_DIR}/http_bench_fork.uya"
UYA_ASYNC_EPOLL_SRC="${SCRIPT_DIR}/http_bench_async_epoll.uya"
UYA_FORK_ENTRY="http_bench_fork.uya"
UYA_ASYNC_EPOLL_ENTRY="http_bench_async_epoll.uya"
C_SRC="${SCRIPT_DIR}/http_bench.c"
export UYA_ROOT="${UYA_ROOT:-${SCRIPT_DIR}/../lib/}"

# 编译输出
GO_EXEC="/tmp/http_bench_go"
UYA_FORK_EXEC="/tmp/http_bench_fork"
UYA_ASYNC_EPOLL_EXEC="/tmp/http_bench_async_epoll"
C_EXEC="/tmp/http_bench_c"
TOKIO_DIR="${SCRIPT_DIR}/http_bench_tokio"
TOKIO_EXEC="/tmp/http_bench_tokio"

# wrk 参数（与文档一致）
WRK_THREADS=4
WRK_CONNECTIONS=64
WRK_DURATION=10s
AB_KEEPALIVE_REQUESTS=20000
AB_KEEPALIVE_CONCURRENCY=100

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

# 编译 Uya fork 版本
build_uya_fork() {
    log_info "编译 Uya fork HTTP 服务器..."
    if [ ! -f "$UYA_BIN" ]; then
        log_err "找不到 Uya 编译器: $UYA_BIN"
        exit 1
    fi
    if [ ! -f "$UYA_FORK_SRC" ]; then
        log_err "找不到 Uya fork 源文件: $UYA_FORK_SRC"
        exit 1
    fi
    if ! "$UYA_BIN" build "$UYA_FORK_ENTRY" -o /tmp/http_bench_fork.c --c99 >/tmp/uya_fork_build.log 2>&1; then
        log_err "Uya fork 编译失败，日志:"
        cat /tmp/uya_fork_build.log >&2
        exit 1
    fi
    if ! cc -std=c99 -no-pie -O2 -fno-builtin -o "$UYA_FORK_EXEC" /tmp/http_bench_fork.c -lm >/tmp/uya_fork_cc.log 2>&1; then
        log_err "Uya fork C 编译失败，日志:"
        cat /tmp/uya_fork_cc.log >&2
        exit 1
    fi
    log_info "Uya fork 版本编译完成: $UYA_FORK_EXEC"
}

# 编译 Uya async epoll 版本
build_uya_async_epoll() {
    log_info "编译 Uya async epoll HTTP 服务器..."
    if [ ! -f "$UYA_BIN" ]; then
        log_err "找不到 Uya 编译器: $UYA_BIN"
        exit 1
    fi
    if [ ! -f "$UYA_ASYNC_EPOLL_SRC" ]; then
        log_err "找不到 Uya async epoll 源文件: $UYA_ASYNC_EPOLL_SRC"
        exit 1
    fi
    # 这里使用 --c99 直出路径，和 verify_http_bench_async_epoll_runtime.sh 保持一致，避免 build 子命令路径差异
    if ! "$UYA_BIN" --c99 "$UYA_ASYNC_EPOLL_ENTRY" -o /tmp/http_bench_async_epoll.c >/tmp/uya_async_epoll_build.log 2>&1; then
        log_err "Uya async epoll 编译失败，日志:"
        cat /tmp/uya_async_epoll_build.log >&2
        exit 1
    fi
    # 注意：当前编译器生成的 C 代码在 -O2 下存在 UB，会导致启动时 SIGSEGV，
    # 临时降级到 -O1 以保证 benchmark 能正常跑完。
    if ! cc -std=c99 -no-pie -O1 -fno-builtin -o "$UYA_ASYNC_EPOLL_EXEC" /tmp/http_bench_async_epoll.c -lm >/tmp/uya_async_epoll_cc.log 2>&1; then
        log_err "Uya async epoll C 编译失败，日志:"
        cat /tmp/uya_async_epoll_cc.log >&2
        exit 1
    fi
    log_info "Uya async epoll 版本编译完成: $UYA_ASYNC_EPOLL_EXEC"
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

# 编译 Rust Tokio 版本（与 http_bench.go 路由一致）
build_tokio() {
    if ! command -v cargo &> /dev/null; then
        log_warn "未找到 cargo，跳过 Tokio 版本编译与压测"
        return 1
    fi
    if [ ! -f "${TOKIO_DIR}/Cargo.toml" ]; then
        log_warn "未找到 ${TOKIO_DIR}/Cargo.toml，跳过 Tokio"
        return 1
    fi
    log_info "编译 Rust Tokio HTTP 服务器..."
    (cd "$TOKIO_DIR" && cargo build --release -q)
    cp "${TOKIO_DIR}/target/release/http_bench_tokio" "$TOKIO_EXEC"
    log_info "Tokio 版本编译完成: $TOKIO_EXEC"
    return 0
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

    # 启动服务器前强制清理同名旧进程并等待端口释放
    pkill -9 -f "http_bench_fork" 2>/dev/null || true
    pkill -9 -f "http_bench_async_epoll" 2>/dev/null || true
    pkill -9 -f "http_bench_go" 2>/dev/null || true
    pkill -9 -f "http_bench_c" 2>/dev/null || true
    pkill -9 -f "http_bench_tokio" 2>/dev/null || true
    sleep 2

    # 启动服务器
    local server_log="/tmp/http_bench_${name//[^a-zA-Z0-9_]/_}.server.log"
    rm -f "$server_log"
    "$exec" >"$server_log" 2>&1 &
    local pid=$!
    sleep 2

    # 检查服务器是否运行
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: $name 服务器启动失败" >&2
        if [ -f "$server_log" ]; then
            echo "---- $name 启动日志 ----" >&2
            sed -n '1,80p' "$server_log" >&2
            echo "-----------------------" >&2
        fi
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

    # 清理服务器（Uya fork 会 fork 子进程，需要用 pkill）
    pkill -9 -f "http_bench_fork" 2>/dev/null || true
    pkill -9 -f "http_bench_async_epoll" 2>/dev/null || true
    pkill -9 -f "http_bench_go" 2>/dev/null || true
    pkill -9 -f "http_bench_c" 2>/dev/null || true
    pkill -9 -f "http_bench_tokio" 2>/dev/null || true
    sleep 2

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

run_benchmark_safe() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local url="$4"
    local result
    if result=$(run_benchmark "$name" "$exec" "$port" "$url"); then
        echo "$result"
        return 0
    fi
    log_err "$name 基准测试失败，按 0 计入结果"
    echo "$name|0|0|0|0|0|0|0"
    return 0
}

run_keepalive_probe() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local url="$4"

    echo "--- $name Keep-Alive 验证（ab -k）---" >&2

    pkill -9 -f "http_bench_fork" 2>/dev/null || true
    pkill -9 -f "http_bench_async_epoll" 2>/dev/null || true
    pkill -9 -f "http_bench_go" 2>/dev/null || true
    pkill -9 -f "http_bench_c" 2>/dev/null || true
    pkill -9 -f "http_bench_tokio" 2>/dev/null || true
    sleep 2

    local server_log="/tmp/http_bench_${name//[^a-zA-Z0-9_]/_}.keepalive.log"
    rm -f "$server_log"
    "$exec" >"$server_log" 2>&1 &
    local pid=$!
    sleep 2

    if ! kill -0 "$pid" 2>/dev/null; then
        echo "ERROR: $name Keep-Alive 验证服务启动失败" >&2
        if [ -f "$server_log" ]; then
            echo "---- $name Keep-Alive 启动日志 ----" >&2
            sed -n '1,80p' "$server_log" >&2
            echo "-----------------------" >&2
        fi
        return 1
    fi

    local output
    output=$(ab -k -n "$AB_KEEPALIVE_REQUESTS" -c "$AB_KEEPALIVE_CONCURRENCY" "$url" 2>&1 || true)
    echo "$output" >&2

    local ka
    local failed
    local rps
    ka=$(echo "$output" | awk '/Keep-Alive requests/ {print $3}' | tr -d '\r\n ')
    failed=$(echo "$output" | awk '/Failed requests/ {print $3}' | tr -d '\r\n ')
    rps=$(echo "$output" | awk '/Requests per second/ {print $4}' | tr -d '\r\n ')
    if [ -z "$ka" ]; then ka=0; fi
    if [ -z "$failed" ]; then failed=0; fi
    if [ -z "$rps" ]; then rps=0; fi

    pkill -9 -f "http_bench_fork" 2>/dev/null || true
    pkill -9 -f "http_bench_async_epoll" 2>/dev/null || true
    pkill -9 -f "http_bench_go" 2>/dev/null || true
    pkill -9 -f "http_bench_c" 2>/dev/null || true
    pkill -9 -f "http_bench_tokio" 2>/dev/null || true
    sleep 2

    echo "$name Keep-Alive 结果: keep_alive=${ka}, failed=${failed}, rps=${rps}" >&2
    echo "$name|$ka|$failed|$rps"
}

run_keepalive_probe_safe() {
    local name="$1"
    local exec="$2"
    local port="$3"
    local url="$4"
    local result
    if result=$(run_keepalive_probe "$name" "$exec" "$port" "$url"); then
        echo "$result"
        return 0
    fi
    log_err "$name Keep-Alive 验证失败，按 0 计入结果"
    echo "$name|0|0|0"
    return 0
}

# 生成 baseline.json
save_baseline() {
    local uya_root_rps="$1"
    local uya_epoll_root_rps="$2"
    local go_root_rps="$3"
    local c_root_rps="$4"
    local tokio_root_rps="$5"
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
      "uya_fork_qps": ${uya_root_rps:-0},
        "uya_async_epoll_qps": ${uya_epoll_root_rps:-0},
      "go_qps": ${go_root_rps:-0},
      "c_qps": ${c_root_rps:-0},
      "tokio_qps": ${tokio_root_rps:-0}
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
    build_uya_fork
    build_uya_async_epoll
    build_go
    build_c
    local have_tokio=0
    if build_tokio; then
        have_tokio=1
    fi

    # 测试端口
    local PORT=8876
    local URL="http://127.0.0.1:$PORT/"

    # 预热
    log_info "预热..."
    echo "" | wrk -t1 -c1 -d2s "$URL" >/dev/null 2>&1 || true

    # 运行基准测试
    local uya_fork_result
    local go_result
    local c_result
    local uya_epoll_result
    local tokio_result
    local tokio_rps=0

    uya_fork_result=$(run_benchmark_safe "Uya-fork" "$UYA_FORK_EXEC" "$PORT" "$URL")
    sleep 1
    uya_epoll_result=$(run_benchmark_safe "Uya-async-epoll" "$UYA_ASYNC_EPOLL_EXEC" "$PORT" "$URL")
    sleep 1
    go_result=$(run_benchmark_safe "Go" "$GO_EXEC" "$PORT" "$URL")
    sleep 1
    c_result=$(run_benchmark_safe "C" "$C_EXEC" "$PORT" "$URL")
    sleep 1
    if [ "$have_tokio" -eq 1 ]; then
        tokio_result=$(run_benchmark_safe "Tokio" "$TOKIO_EXEC" "$PORT" "$URL")
        tokio_rps=$(echo "$tokio_result" | awk -F'|' '{print $8}')
        if [ -z "$tokio_rps" ]; then tokio_rps=0; fi
    fi

    # 提取 QPS
    local uya_fork_rps
    local go_rps
    local c_rps
    local uya_epoll_rps
    uya_fork_rps=$(echo "$uya_fork_result" | awk -F'|' '{print $8}' | tr -d '\r\n ')
    uya_epoll_rps=$(echo "$uya_epoll_result" | awk -F'|' '{print $8}' | tr -d '\r\n ')
    go_rps=$(echo "$go_result" | awk -F'|' '{print $8}' | tr -d '\r\n ')
    c_rps=$(echo "$c_result" | awk -F'|' '{print $8}' | tr -d '\r\n ')
    if [ -z "$uya_fork_rps" ]; then uya_fork_rps=0; fi
    if [ -z "$uya_epoll_rps" ]; then uya_epoll_rps=0; fi
    if [ -z "$go_rps" ]; then go_rps=0; fi
    if [ -z "$c_rps" ]; then c_rps=0; fi

    echo ""
    log_info "Keep-Alive 对比（ab -k -n${AB_KEEPALIVE_REQUESTS} -c${AB_KEEPALIVE_CONCURRENCY}）"
    local uya_fork_ka_result
    local uya_epoll_ka_result
    local go_ka_result
    local c_ka_result
    local tokio_ka_result
    local tokio_ka=0
    local tokio_ka_failed=0
    local tokio_ka_rps=0
    local uya_fork_ka
    local uya_epoll_ka
    local go_ka
    local c_ka
    local uya_fork_ka_failed
    local uya_epoll_ka_failed
    local go_ka_failed
    local c_ka_failed
    local uya_fork_ka_rps
    local uya_epoll_ka_rps
    local go_ka_rps
    local c_ka_rps
    uya_fork_ka_result=$(run_keepalive_probe_safe "Uya-fork" "$UYA_FORK_EXEC" "$PORT" "$URL")
    uya_epoll_ka_result=$(run_keepalive_probe_safe "Uya-async-epoll" "$UYA_ASYNC_EPOLL_EXEC" "$PORT" "$URL")
    go_ka_result=$(run_keepalive_probe_safe "Go" "$GO_EXEC" "$PORT" "$URL")
    c_ka_result=$(run_keepalive_probe_safe "C" "$C_EXEC" "$PORT" "$URL")
    if [ "$have_tokio" -eq 1 ]; then
        tokio_ka_result=$(run_keepalive_probe_safe "Tokio" "$TOKIO_EXEC" "$PORT" "$URL")
        tokio_ka=$(echo "$tokio_ka_result" | awk -F'|' '{print $2}' | tr -d '\r\n ')
        tokio_ka_failed=$(echo "$tokio_ka_result" | awk -F'|' '{print $3}' | tr -d '\r\n ')
        tokio_ka_rps=$(echo "$tokio_ka_result" | awk -F'|' '{print $4}' | tr -d '\r\n ')
        if [ -z "$tokio_ka" ]; then tokio_ka=0; fi
        if [ -z "$tokio_ka_failed" ]; then tokio_ka_failed=0; fi
        if [ -z "$tokio_ka_rps" ]; then tokio_ka_rps=0; fi
    fi
    uya_fork_ka=$(echo "$uya_fork_ka_result" | awk -F'|' '{print $2}' | tr -d '\r\n ')
    uya_epoll_ka=$(echo "$uya_epoll_ka_result" | awk -F'|' '{print $2}' | tr -d '\r\n ')
    go_ka=$(echo "$go_ka_result" | awk -F'|' '{print $2}' | tr -d '\r\n ')
    c_ka=$(echo "$c_ka_result" | awk -F'|' '{print $2}' | tr -d '\r\n ')
    uya_fork_ka_failed=$(echo "$uya_fork_ka_result" | awk -F'|' '{print $3}' | tr -d '\r\n ')
    uya_epoll_ka_failed=$(echo "$uya_epoll_ka_result" | awk -F'|' '{print $3}' | tr -d '\r\n ')
    go_ka_failed=$(echo "$go_ka_result" | awk -F'|' '{print $3}' | tr -d '\r\n ')
    c_ka_failed=$(echo "$c_ka_result" | awk -F'|' '{print $3}' | tr -d '\r\n ')
    uya_fork_ka_rps=$(echo "$uya_fork_ka_result" | awk -F'|' '{print $4}' | tr -d '\r\n ')
    uya_epoll_ka_rps=$(echo "$uya_epoll_ka_result" | awk -F'|' '{print $4}' | tr -d '\r\n ')
    go_ka_rps=$(echo "$go_ka_result" | awk -F'|' '{print $4}' | tr -d '\r\n ')
    c_ka_rps=$(echo "$c_ka_result" | awk -F'|' '{print $4}' | tr -d '\r\n ')
    if [ -z "$uya_fork_ka" ]; then uya_fork_ka=0; fi
    if [ -z "$uya_epoll_ka" ]; then uya_epoll_ka=0; fi
    if [ -z "$go_ka" ]; then go_ka=0; fi
    if [ -z "$c_ka" ]; then c_ka=0; fi
    if [ -z "$uya_fork_ka_failed" ]; then uya_fork_ka_failed=0; fi
    if [ -z "$uya_epoll_ka_failed" ]; then uya_epoll_ka_failed=0; fi
    if [ -z "$go_ka_failed" ]; then go_ka_failed=0; fi
    if [ -z "$c_ka_failed" ]; then c_ka_failed=0; fi
    if [ -z "$uya_fork_ka_rps" ]; then uya_fork_ka_rps=0; fi
    if [ -z "$uya_epoll_ka_rps" ]; then uya_epoll_ka_rps=0; fi
    if [ -z "$go_ka_rps" ]; then go_ka_rps=0; fi
    if [ -z "$c_ka_rps" ]; then c_ka_rps=0; fi

    log_info "统一对比结果"
    echo "=========================================="
    if [ "$have_tokio" -eq 1 ]; then
        printf "| %-20s | %-12s | %-12s | %-12s | %-12s | %-12s |\n" "指标" "Uya-fork" "Uya-epoll" "Go" "C" "Tokio"
        echo "|--------------------|--------------|--------------|--------------|--------------|--------------|"
        printf "| %-20s | %-12s | %-12s | %-12s | %-12s | %-12s |\n" "QPS(wrk)" "${uya_fork_rps:-0}" "${uya_epoll_rps:-0}" "${go_rps:-0}" "${c_rps:-0}" "${tokio_rps:-0}"
        printf "| %-20s | %-12s | %-12s | %-12s | %-12s | %-12s |\n" "KA-Req(ab -k)" "${uya_fork_ka}" "${uya_epoll_ka}" "${go_ka}" "${c_ka}" "${tokio_ka}"
        printf "| %-20s | %-12s | %-12s | %-12s | %-12s | %-12s |\n" "KA-Failed" "${uya_fork_ka_failed}" "${uya_epoll_ka_failed}" "${go_ka_failed}" "${c_ka_failed}" "${tokio_ka_failed}"
        printf "| %-20s | %-12s | %-12s | %-12s | %-12s | %-12s |\n" "KA-RPS(ab -k)" "${uya_fork_ka_rps}" "${uya_epoll_ka_rps}" "${go_ka_rps}" "${c_ka_rps}" "${tokio_ka_rps}"
    else
        printf "| %-20s | %-14s | %-14s | %-14s | %-14s |\n" "指标" "Uya-fork" "Uya-epoll" "Go" "C"
        echo "|--------------------|----------------|----------------|----------------|----------------|"
        printf "| %-20s | %-14s | %-14s | %-14s | %-14s |\n" "QPS(wrk)" "${uya_fork_rps:-0}" "${uya_epoll_rps:-0}" "${go_rps:-0}" "${c_rps:-0}"
        printf "| %-20s | %-14s | %-14s | %-14s | %-14s |\n" "KA-Req(ab -k)" "${uya_fork_ka}" "${uya_epoll_ka}" "${go_ka}" "${c_ka}"
        printf "| %-20s | %-14s | %-14s | %-14s | %-14s |\n" "KA-Failed" "${uya_fork_ka_failed}" "${uya_epoll_ka_failed}" "${go_ka_failed}" "${c_ka_failed}"
        printf "| %-20s | %-14s | %-14s | %-14s | %-14s |\n" "KA-RPS(ab -k)" "${uya_fork_ka_rps}" "${uya_epoll_ka_rps}" "${go_ka_rps}" "${c_ka_rps}"
    fi
    echo "=========================================="

    # 保存基线（如果指定）
    if [ "$1" = "--baseline" ]; then
        save_baseline "$uya_fork_rps" "$uya_epoll_rps" "$go_rps" "$c_rps" "${tokio_rps:-0}"
    fi

    # 清理
    rm -f "$GO_EXEC" "$C_EXEC" "$UYA_FORK_EXEC" "$UYA_ASYNC_EPOLL_EXEC" "$TOKIO_EXEC"

    log_info "基准测试完成"
}

main "$@"
