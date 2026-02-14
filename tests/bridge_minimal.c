// bridge_minimal.c - 最小运行时桥接（仅提供 main 函数）
// 用于使用 std.runtime 模块的测试，因为 std.runtime 已经提供了其他运行时函数
// 注意：Uya 的 main 函数被重命名为 uya_main，由这个文件的 main 函数调用
// std.runtime 的 get_argc/get_argv 依赖 saved_argc/saved_argv，需在调用 uya_main 前设置

#include <stdint.h>

// Uya 程序的 main 函数（被重命名为 uya_main）
extern int32_t uya_main(void);

// std.runtime 的全局变量（由编译器生成的 C 代码定义，此处声明以便初始化）
extern int32_t saved_argc;
extern uint8_t **saved_argv;

// 真正的 C main 函数（程序入口点）
int main(int argc, char **argv) {
    saved_argc = (int32_t)argc;
    saved_argv = (uint8_t **)argv;
    return (int)uya_main();
}

