// bridge_test.c - 测试程序桥接
// 为使用 test "..." 语法的文件提供 main 入口
// uya_main() 由编译器自动生成

#include <stdint.h>

extern int32_t uya_main(void);

int main(void) {
    return (int)uya_main();
}
