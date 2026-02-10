// bridge_minimal.c - 最小运行时桥接（仅提供 main 函数）
// 用于使用 std.runtime 模块的测试，因为 std.runtime 已经提供了其他运行时函数
// 注意：Uya 的 main 函数被重命名为 uya_main，由这个文件的 main 函数调用

#include <stdint.h>

// Uya 程序的 main 函数（被重命名为 uya_main）
extern int32_t uya_main(void);

// 真正的 C main 函数（程序入口点）
int main(int argc, char **argv) {
    // 调用 Uya 的 main 函数
    // 注意：std.runtime 模块会自己处理命令行参数
    (void)argc;  // 未使用，避免警告
    (void)argv;  // 未使用，避免警告
    return (int)uya_main();
}

