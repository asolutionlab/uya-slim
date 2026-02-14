#!/bin/bash
# Uya Mini 编译器并行测试脚本（简化版）
# 使用 GNU parallel 或 xargs -P 并行执行测试
#
# 用法:
#   ./run_programs_fast.sh                    # 并行运行所有测试（默认8线程）
#   ./run_programs_fast.sh -j 4               # 并行运行所有测试（4线程）
#   ./run_programs_fast.sh --c99              # 使用 C99 后端（默认）
#   ./run_programs_fast.sh --uya              # 使用自举编译器

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPILER="$REPO_ROOT/bin/uya-c"
TEST_DIR="$SCRIPT_DIR/programs"
BUILD_DIR="$TEST_DIR/build"
USE_UYA=false
PARALLEL_JOBS=${PARALLEL_JOBS:-8}
ONLY_ERRORS=false

# 解析命令行参数
TARGET_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        -j)
            PARALLEL_JOBS="$2"
            shift 2
            ;;
        --c99)
            shift
            ;;
        --uya)
            USE_UYA=true
            COMPILER="$REPO_ROOT/bin/uya"
            shift
            ;;
        -e|--errors-only)
            ONLY_ERRORS=true
            shift
            ;;
        -h|--help)
            echo "用法: $0 [选项] [测试文件]"
            echo "  -j <N>              并行任务数（默认8）"
            echo "  --c99               使用 C99 后端（默认）"
            echo "  --uya               使用自举编译器"
            echo "  -e, --errors-only   只显示失败的测试"
            echo "  <测试文件>          指定要测试的文件（可选）"
            echo "环境变量: PARALLEL_JOBS=N"
            exit 0
            ;;
        *)
            TARGET_FILE="$1"
            shift
            ;;
    esac
done

export UYA_ROOT="${REPO_ROOT}/lib/"

# 检查编译器
if [ ! -f "$COMPILER" ]; then
    echo "错误: 编译器不存在: $COMPILER"
    exit 1
fi

# 创建构建目录
mkdir -p "$BUILD_DIR" "$BUILD_DIR/parallel_results"

# 收集测试文件
TEST_FILES=()
if [ -n "$TARGET_FILE" ]; then
    # 使用指定的测试文件
    if [ -f "$TARGET_FILE" ]; then
        echo "$TARGET_FILE" > "$BUILD_DIR/parallel_tests.txt"
    elif [ -f "$TEST_DIR/$TARGET_FILE" ]; then
        echo "$TEST_DIR/$TARGET_FILE" > "$BUILD_DIR/parallel_tests.txt"
    elif [ -f "$REPO_ROOT/$TARGET_FILE" ]; then
        echo "$REPO_ROOT/$TARGET_FILE" > "$BUILD_DIR/parallel_tests.txt"
    else
        echo "错误: 找不到测试文件: $TARGET_FILE"
        exit 1
    fi
else
    # 收集所有测试文件
    find "$TEST_DIR" -maxdepth 1 -name "*.uya" -type f 2>/dev/null | sort > "$BUILD_DIR/parallel_tests.txt"
fi
TEST_COUNT=$(wc -l < "$BUILD_DIR/parallel_tests.txt")

echo "=========================================="
echo "并行测试（$PARALLEL_JOBS 线程）"
echo "=========================================="
echo "编译器: $COMPILER"
echo "测试数量: $TEST_COUNT"
echo ""

# 导出环境变量
export COMPILER USE_UYA SCRIPT_DIR BUILD_DIR PARALLEL_JOBS ONLY_ERRORS UYA_ROOT

# 单个测试执行函数
run_test() {
    local test_file="$1"
    local base_name=$(basename "$test_file" .uya)
    local output_file="$BUILD_DIR/${base_name}.c"
    
    # 编译
    if ! "$COMPILER" --c99 --nostdlib "$test_file" -o "$output_file" >/dev/null 2>&1; then
        # 检查是否是预期失败
        if [[ "$base_name" =~ ^error_ ]]; then
            echo "PASS:$base_name"
            return
        fi
        echo "FAIL:$base_name:编译失败"
        return
    fi
    
    # 预期失败但编译成功
    if [[ "$base_name" =~ ^error_ ]]; then
        echo "FAIL:$base_name:预期失败但编译成功"
        return
    fi
    
    # 链接
    local link_cmd="gcc -std=c99 -o $BUILD_DIR/$base_name $output_file $SCRIPT_DIR/bridge.c 2>/dev/null"
    if grep -q "use.*std\.runtime" "$test_file" 2>/dev/null; then
        link_cmd="gcc -std=c99 -o $BUILD_DIR/$base_name $output_file $SCRIPT_DIR/bridge_minimal.c 2>/dev/null"
    fi
    
    if ! eval "$link_cmd"; then
        echo "FAIL:$base_name:链接失败"
        return
    fi
    
    # 运行
    if "$BUILD_DIR/$base_name" >/dev/null 2>&1; then
        echo "PASS:$base_name"
    else
        echo "FAIL:$base_name:运行失败"
    fi
}
export -f run_test

# 执行并行测试
RESULTS="$BUILD_DIR/parallel_results.txt"
if [ "$ONLY_ERRORS" = false ]; then
    echo "执行并行测试..."
fi

if command -v parallel &> /dev/null; then
    # 使用 GNU parallel
    parallel -j "$PARALLEL_JOBS" run_test {} < "$BUILD_DIR/parallel_tests.txt" > "$RESULTS" 2>/dev/null
elif command -v xargs &> /dev/null; then
    # 使用 xargs
    xargs -P "$PARALLEL_JOBS" -I {} bash -c 'run_test "$@"' _ {} < "$BUILD_DIR/parallel_tests.txt" > "$RESULTS" 2>/dev/null
else
    echo "错误: 未找到 parallel 或 xargs"
    exit 1
fi

# 统计结果
PASSED=0
FAILED=0
if [ -f "$RESULTS" ] && [ -s "$RESULTS" ]; then
    PASSED=$(grep -c "^PASS:" "$RESULTS" 2>/dev/null | tr -d '\r' || echo "0")
    FAILED=$(grep -c "^FAIL:" "$RESULTS" 2>/dev/null | tr -d '\r' || echo "0")
    PASSED=${PASSED:-0}
    FAILED=${FAILED:-0}
fi

# 显示结果
if [ "$ONLY_ERRORS" = false ] || [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "================================"
    echo "总计: $((PASSED + FAILED)) 个测试"
    echo "通过: $PASSED"
    echo "失败: $FAILED"
    echo "================================"
fi

if [ "$FAILED" -gt 0 ]; then
    echo ""
    echo "失败的测试:"
    grep "^FAIL:" "$RESULTS" | sed 's/^FAIL:/  ❌ /'
fi

if [ "$FAILED" -eq 0 ]; then
    exit 0
else
    exit 1
fi
