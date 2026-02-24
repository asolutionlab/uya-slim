#!/bin/bash

# run_cross_platform_tests.sh - 跨平台测试脚本
# 在不同平台上测试 @asm 的兼容性

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$PROJECT_ROOT/tests"
BUILD_DIR="$PROJECT_DIR/build/cross_platform"

# 创建构建目录
mkdir -p "$BUILD_DIR"

# 检测当前平台
detect_platform() {
    local arch=$(uname -m)
    local os=$(uname -s)
    
    case "$arch" in
        x86_64|amd64)
            case "$os" in
                Linux) echo "x86_64_linux" ;;
                Darwin) echo "x86_64_macos" ;;
                *) echo "x86_64_unknown" ;;
            esac
            ;;
        aarch64|arm64)
            case "$os" in
                Linux) echo "arm64_linux" ;;
                Darwin) echo "arm64_macos" ;;
                *) echo "arm64_unknown" ;;
            esac
            ;;
        riscv64)
            echo "riscv64_linux"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 获取平台枚举值
get_platform_enum() {
    local platform=$1
    case "$platform" in
        x86_64_linux) echo "0" ;;
        x86_64_macos) echo "1" ;;
        x86_64_windows) echo "2" ;;
        arm64_linux) echo "3" ;;
        arm64_macos) echo "4" ;;
        arm64_windows) echo "5" ;;
        riscv64_linux) echo "6" ;;
        *) echo "-1" ;;
    esac
}

# 测试平台检测
test_platform_detection() {
    local platform=$(detect_platform)
    local expected_enum=$(get_platform_enum "$platform")
    
    echo -e "\n${BLUE}测试平台检测${NC}"
    echo -e "检测到平台: ${GREEN}$platform${NC}"
    echo -e "预期枚举值: ${GREEN}$expected_enum${NC}"
    
    # 创建测试程序
    local test_file="$BUILD_DIR/test_platform_detect.c"
    cat > "$test_file" << 'EOF'
#include <stdio.h>

// 平台检测宏
#if defined(__x86_64__) || defined(_M_X64)
  #if defined(__linux__)
    #define UYA_ASM_TARGET 0
    #define UYA_ASM_TARGET_NAME "x86_64_linux"
  #elif defined(__APPLE__)
    #define UYA_ASM_TARGET 1
    #define UYA_ASM_TARGET_NAME "x86_64_macos"
  #elif defined(_WIN32)
    #define UYA_ASM_TARGET 2
    #define UYA_ASM_TARGET_NAME "x86_64_windows"
  #else
    #define UYA_ASM_TARGET 0
    #define UYA_ASM_TARGET_NAME "x86_64_unknown"
  #endif
#elif defined(__aarch64__) || defined(_M_ARM64)
  #if defined(__linux__)
    #define UYA_ASM_TARGET 3
    #define UYA_ASM_TARGET_NAME "arm64_linux"
  #elif defined(__APPLE__)
    #define UYA_ASM_TARGET 4
    #define UYA_ASM_TARGET_NAME "arm64_macos"
  #elif defined(_WIN32)
    #define UYA_ASM_TARGET 5
    #define UYA_ASM_TARGET_NAME "arm64_windows"
  #else
    #define UYA_ASM_TARGET 3
    #define UYA_ASM_TARGET_NAME "arm64_unknown"
  #endif
#elif defined(__riscv) && __riscv_xlen == 64
  #define UYA_ASM_TARGET 6
  #define UYA_ASM_TARGET_NAME "riscv64_linux"
#else
  #define UYA_ASM_TARGET -1
  #define UYA_ASM_TARGET_NAME "unknown"
#endif

int main() {
    printf("Platform: %s\n", UYA_ASM_TARGET_NAME);
    printf("Enum value: %d\n", UYA_ASM_TARGET);
    
    // 验证 @asm_target() 函数
    int target = UYA_ASM_TARGET;
    if (target >= 0 && target <= 6) {
        printf("✓ Platform detection successful\n");
        return 0;
    } else {
        printf("✗ Platform detection failed\n");
        return 1;
    }
}
EOF
    
    # 编译并运行
    local exe_file="$BUILD_DIR/test_platform_detect"
    if gcc -o "$exe_file" "$test_file" 2>&1; then
        if "$exe_file"; then
            echo -e "${GREEN}✓ 平台检测测试通过${NC}"
            return 0
        else
            echo -e "${RED}✗ 平台检测测试失败${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ 编译失败${NC}"
        return 1
    fi
}

# 测试平台特定指令
test_platform_specific_instructions() {
    local platform=$(detect_platform)
    
    echo -e "\n${BLUE}测试平台特定指令${NC}"
    
    # 创建测试程序
    local test_file="$BUILD_DIR/test_platform_asm.c"
    
    if [[ "$platform" == x86_64_* ]]; then
        # x86-64 平台测试
        cat > "$test_file" << 'EOF'
#include <stdio.h>

int main() {
    int result = 0;
    
    // 测试 x86-64 nop
    __asm__ volatile (
        "nop"
        : "=r"(result)
        :
        :
    );
    
    // 测试 x86-64 cpuid
    unsigned int eax, ebx, ecx, edx;
    __asm__ volatile (
        "cpuid"
        : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx)
        : "a"(0)
        :
    );
    
    printf("CPU Vendor: %.4s%.4s%.4s\n", (char*)&ebx, (char*)&edx, (char*)&ecx);
    printf("✓ x86-64 assembly tests passed\n");
    return 0;
}
EOF
    elif [[ "$platform" == arm64_* ]]; then
        # ARM64 平台测试
        cat > "$test_file" << 'EOF'
#include <stdio.h>

int main() {
    int result = 0;
    
    // 测试 ARM64 nop
    __asm__ volatile (
        "nop"
        : "=r"(result)
        :
        :
    );
    
    // 测试 ARM64 mrs (读取系统寄存器)
    unsigned long long value;
    __asm__ volatile (
        "mrs %0, cntvct_el0"
        : "=r"(value)
        :
        :
    );
    
    printf("Counter value: %llu\n", value);
    printf("✓ ARM64 assembly tests passed\n");
    return 0;
}
EOF
    else
        echo -e "${YELLOW}⊘ 跳过平台特定指令测试（未知平台）${NC}"
        return 0
    fi
    
    # 编译并运行
    local exe_file="$BUILD_DIR/test_platform_asm"
    if gcc -o "$exe_file" "$test_file" 2>&1; then
        if "$exe_file"; then
            echo -e "${GREEN}✓ 平台特定指令测试通过${NC}"
            return 0
        else
            echo -e "${RED}✗ 平台特定指令测试失败${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ 编译失败${NC}"
        return 1
    fi
}

# 测试跨平台代码生成
test_cross_platform_codegen() {
    local platform=$(detect_platform)
    
    echo -e "\n${BLUE}测试跨平台代码生成${NC}"
    
    # 测试 Uya 编译器生成的代码
    local uya_test="$TEST_DIR/test_asm_platform.uya"
    if [ ! -f "$uya_test" ]; then
        echo -e "${YELLOW}⊘ 测试文件不存在: $uya_test${NC}"
        return 0
    fi
    
    local c_file="$BUILD_DIR/test_cross_platform.c"
    local exe_file="$BUILD_DIR/test_cross_platform"
    
    # 编译 Uya 到 C
    if ! "$PROJECT_ROOT/bin/uya" --c99 "$uya_test" > "$c_file" 2>&1; then
        echo -e "${RED}✗ Uya 编译失败${NC}"
        return 1
    fi
    
    # 编译 C 到可执行文件
    if ! gcc -O2 -o "$exe_file" "$c_file" -lm 2>&1; then
        echo -e "${RED}✗ C 编译失败${NC}"
        return 1
    fi
    
    # 运行测试
    if "$exe_file"; then
        echo -e "${GREEN}✓ 跨平台代码生成测试通过${NC}"
        return 0
    else
        echo -e "${RED}✗ 跨平台代码生成测试失败${NC}"
        return 1
    fi
}

# 测试条件编译
test_conditional_compilation() {
    local platform=$(detect_platform)
    
    echo -e "\n${BLUE}测试条件编译${NC}"
    
    # 创建测试程序
    local test_file="$BUILD_DIR/test_conditional.c"
    cat > "$test_file" << 'EOF'
#include <stdio.h>

int main() {
    int target = UYA_ASM_TARGET;
    int result = 0;
    
    // 条件编译示例
    #if defined(__x86_64__) || defined(_M_X64)
        result = 100;
        printf("x86-64 path\n");
    #elif defined(__aarch64__) || defined(_M_ARM64)
        result = 200;
        printf("ARM64 path\n");
    #elif defined(__riscv)
        result = 300;
        printf("RISC-V path\n");
    #else
        result = 999;
        printf("Unknown path\n");
    #endif
    
    printf("Result: %d\n", result);
    
    if (result != 999) {
        printf("✓ Conditional compilation test passed\n");
        return 0;
    } else {
        printf("✗ Conditional compilation test failed\n");
        return 1;
    }
}
EOF
    
    # 编译并运行
    local exe_file="$BUILD_DIR/test_conditional"
    if gcc -o "$exe_file" "$test_file" 2>&1; then
        if "$exe_file"; then
            echo -e "${GREEN}✓ 条件编译测试通过${NC}"
            return 0
        else
            echo -e "${RED}✗ 条件编译测试失败${NC}"
            return 1
        fi
    else
        echo -e "${RED}✗ 编译失败${NC}"
        return 1
    fi
}

# 主函数
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}跨平台测试套件${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    
    # 检查编译器
    if [ ! -f "$PROJECT_ROOT/bin/uya" ]; then
        echo -e "${RED}错误: 未找到编译器 $PROJECT_ROOT/bin/uya${NC}"
        echo -e "${YELLOW}请先编译编译器: cd compiler-c && make build${NC}"
        exit 1
    fi
    
    # 检测平台
    local platform=$(detect_platform)
    echo -e "当前平台: ${GREEN}$platform${NC}\n"
    
    # 运行测试
    local failed=0
    
    test_platform_detection || failed=$((failed + 1))
    test_platform_specific_instructions || failed=$((failed + 1))
    test_cross_platform_codegen || failed=$((failed + 1))
    test_conditional_compilation || failed=$((failed + 1))
    
    # 生成报告
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}测试报告${NC}"
    echo -e "${BLUE}========================================${NC}\n"
    
    echo -e "平台: $platform"
    echo -e "失败测试数: $failed"
    
    # 保存报告
    cat > "$BUILD_DIR/cross_platform_report.txt" << EOF
跨平台测试报告
生成时间: $(date)
平台: $platform

失败测试数: $failed
EOF
    
    echo -e "\n${BLUE}报告已保存到: $BUILD_DIR/cross_platform_report.txt${NC}"
    
    if [ $failed -eq 0 ]; then
        echo -e "\n${GREEN}所有跨平台测试通过！${NC}"
        exit 0
    else
        echo -e "\n${RED}有 $failed 个测试失败${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@"
