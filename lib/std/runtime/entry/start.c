/*
 * start.c - 自定义程序入口（无 C 标准库）
 * 
 * 用于 -nostdlib 构建，替代 C 运行时的 crt1.o
 * 直接调用 main(argc, argv)，不依赖 __libc_start_main
 * 
 * Linux x86_64 调用约定：
 *   栈顶: [argc] [argv[0]] [argv[1]] ... [NULL] [envp[0]] ...
 */

/* 声明 main 函数 */
extern int main(int argc, char **argv);

/* 使用内联汇编实现 _start 入口点 */
__attribute__((naked)) void _start(void) {
    __asm__ volatile (
        /* 栈布局：
         *   (%rsp)      = argc
         *   8(%rsp)     = argv[0] (程序名)
         *   16(%rsp)    = argv[1]
         *   ...
         */
        
        /* 获取 argc 和 argv */
        "movq (%%rsp), %%rdi\n\t"    /* argc → 第一个参数 */
        "leaq 8(%%rsp), %%rsi\n\t"   /* argv → 第二个参数 */
        
        /* 调用 main(argc, argv) */
        "call main\n\t"
        
        /* main 返回值在 %rax 中，作为 exit 状态码 */
        "movq %%rax, %%rdi\n\t"
        
        /* 调用 exit 系统调用 */
        "movq $60, %%rax\n\t"        /* syscall number for exit */
        "syscall\n\t"
        
        /* 不应该到达这里 */
        "hlt\n\t"
        :
        :
        : "memory"
    );
}
