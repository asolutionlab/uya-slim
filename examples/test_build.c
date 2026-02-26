// C99 代码由 Uya Mini 编译器生成
// 使用 -std=c99 编译
//
#ifndef _POSIX_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#endif

// @asm_target 平台检测
#if defined(__x86_64__) || defined(_M_X64)
  #if defined(__linux__)
    #define UYA_ASM_TARGET_X86_64_LINUX 0
  #elif defined(__APPLE__)
    #define UYA_ASM_TARGET_X86_64_LINUX 1
  #elif defined(_WIN32)
    #define UYA_ASM_TARGET_X86_64_LINUX 2
  #else
    #define UYA_ASM_TARGET_X86_64_LINUX 0
  #endif
#elif defined(__aarch64__) || defined(_M_ARM64)
  #if defined(__linux__)
    #define UYA_ASM_TARGET_X86_64_LINUX 3
  #elif defined(__APPLE__)
    #define UYA_ASM_TARGET_X86_64_LINUX 4
  #elif defined(_WIN32)
    #define UYA_ASM_TARGET_X86_64_LINUX 5
  #else
    #define UYA_ASM_TARGET_X86_64_LINUX 3
  #endif
#elif defined(__riscv) && __riscv_xlen == 64
  #define UYA_ASM_TARGET_X86_64_LINUX 6
#else
  #define UYA_ASM_TARGET_X86_64_LINUX 0
#endif

// 标准类型定义（不依赖标准库头文件）
typedef unsigned char uint8_t;
typedef unsigned short uint16_t;
typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef signed char int8_t;
typedef signed short int16_t;
typedef signed int int32_t;
typedef signed long long int64_t;
typedef unsigned long size_t;
typedef signed long ssize_t;
typedef unsigned long uintptr_t;
typedef signed long intptr_t;
typedef signed long ptrdiff_t;
#ifndef NULL
#define NULL ((void *)0)
#endif
#ifndef offsetof
#define offsetof(type, member) ((size_t)&((type *)0)->member)
#endif
#ifndef true
#define true 1
#endif
#ifndef false
#define false 0
#endif
typedef _Bool bool;
typedef __builtin_va_list va_list;
#define va_start(v, l) __builtin_va_start(v, l)
#define va_end(v) __builtin_va_end(v)
#define va_arg(v, l) __builtin_va_arg(v, l)

#include <stdio.h>
extern void *opendir(const char *);
extern void *readdir(void *);
extern int closedir(void *);

// C99 兼容的 alignof 实现
#define uya_alignof(type) offsetof(struct { char c; type t; }, t)

static inline void *__uya_memcpy(void *dest, const void *src, size_t n) {
    char *d = (char *)dest; const char *s = (const char *)src;
    for (size_t i = 0; i < n; i++) d[i] = s[i];
    return dest;
}
static inline int __uya_memcmp(const void *s1, const void *s2, size_t n) {
    const unsigned char *a = (const unsigned char *)s1, *b = (const unsigned char *)s2;
    for (size_t i = 0; i < n; i++) { if (a[i] != b[i]) return a[i] - b[i]; } return 0;
}

// 错误联合类型（用于 !i64 等）
struct err_union_int64_t { uint32_t error_id; int64_t value; };
struct err_union_void { uint32_t error_id; };


struct TypeInfo;
struct EntryRLimit;



// 内置 TypeInfo 结构体（由 @mc_type 使用）
struct TypeInfo {
    int8_t * name;
    int32_t size;
    int32_t align;
    int32_t kind;
    bool is_integer;
    bool is_float;
    bool is_bool;
    bool is_pointer;
    bool is_array;
    bool is_void;
};

struct EntryRLimit {
    uint64_t rlim_cur;
    uint64_t rlim_max;
};

// 系统调用辅助函数（Linux x86-64）
#ifdef __x86_64__
static inline long uya_syscall0(long nr) {
    register long rax __asm__("rax") = nr;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall1(long nr, long a1) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall2(long nr, long a1, long a2) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    register long rsi __asm__("rsi") = a2;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi), "r"(rsi) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall3(long nr, long a1, long a2, long a3) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    register long rsi __asm__("rsi") = a2;
    register long rdx __asm__("rdx") = a3;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi), "r"(rsi), "r"(rdx) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall4(long nr, long a1, long a2, long a3, long a4) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    register long rsi __asm__("rsi") = a2;
    register long rdx __asm__("rdx") = a3;
    register long r10 __asm__("r10") = a4;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi), "r"(rsi), "r"(rdx), "r"(r10) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall5(long nr, long a1, long a2, long a3, long a4, long a5) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    register long rsi __asm__("rsi") = a2;
    register long rdx __asm__("rdx") = a3;
    register long r10 __asm__("r10") = a4;
    register long r8 __asm__("r8") = a5;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi), "r"(rsi), "r"(rdx), "r"(r10), "r"(r8) : "rcx", "r11", "memory");
    return rax;
}

static inline long uya_syscall6(long nr, long a1, long a2, long a3, long a4, long a5, long a6) {
    register long rax __asm__("rax") = nr;
    register long rdi __asm__("rdi") = a1;
    register long rsi __asm__("rsi") = a2;
    register long rdx __asm__("rdx") = a3;
    register long r10 __asm__("r10") = a4;
    register long r8 __asm__("r8") = a5;
    register long r9 __asm__("r9") = a6;
    __asm__ volatile("syscall" : "=r"(rax) : "r"(rax), "r"(rdi), "r"(rsi), "r"(rdx), "r"(r10), "r"(r8), "r"(r9) : "rcx", "r11", "memory");
    return rax;
}
#else
#error "@syscall currently only supports Linux x86-64"
#endif

int32_t main();
extern int32_t main_main();
int32_t main(int32_t argc, uint8_t * * argv);
int32_t std_runtime_get_argc();
uint8_t * std_runtime_get_argv(int32_t index);
int32_t std_runtime_ptr_diff(uint8_t * ptr1, uint8_t * ptr2);
void std_runtime__uya_exit(int32_t code);

extern struct FILE _stdin, _stdout, _stderr;
int32_t saved_argc = 0;
uint8_t * * saved_argv = NULL;

int32_t std_runtime_get_argc() {
    int32_t _uya_ret = saved_argc;
    return _uya_ret;
}

uint8_t * std_runtime_get_argv(int32_t index) {
    (void)index;
    if (((index < 0) || (index >= saved_argc))) {
        uint8_t * _uya_ret = NULL;
        return _uya_ret;
    }
    if ((saved_argv == NULL)) {
        uint8_t * _uya_ret = NULL;
        return _uya_ret;
    }
    uint8_t * _uya_ret = saved_argv[index];
    return _uya_ret;
}

int32_t std_runtime_ptr_diff(uint8_t * ptr1, uint8_t * ptr2) {
    (void)ptr1;
    (void)ptr2;
    if (((ptr1 == NULL) || (ptr2 == NULL))) {
        int32_t _uya_ret = 0;
        return _uya_ret;
    }
    const size_t addr1 = (uintptr_t)((void *)ptr1);
    const size_t addr2 = (uintptr_t)((void *)ptr2);
    if ((addr1 >= addr2)) {
        int32_t _uya_ret = (int32_t)(addr1 - addr2);
        return _uya_ret;
    } else {
        int32_t _uya_ret = (0 - (int32_t)(addr2 - addr1));
        return _uya_ret;
    }
        return 0;
}


void std_runtime__uya_exit(int32_t code) {
    (void)code;
    exit(code);
}


int32_t main_main(void) {
int32_t _uya_ret = 42;
return _uya_ret;
}
int32_t main(int32_t argc, uint8_t * * argv) {
const int64_t SYS_setrlimit = 160;
const int32_t RLIMIT_STACK = 3;
struct EntryRLimit rlim = (struct EntryRLimit){.rlim_cur = ((16 * 1024) * 1024), .rlim_max = ((16 * 1024) * 1024)};
(void)(({ long _uya_syscall_ret = uya_syscall2(SYS_setrlimit, (int64_t)RLIMIT_STACK, (int64_t)(&rlim)); struct err_union_int64_t _uya_result; if (_uya_syscall_ret < 0) { _uya_result.error_id = (int)(-_uya_syscall_ret); } else { _uya_result.error_id = 0; _uya_result.value = _uya_syscall_ret; } _uya_result; }));
saved_argc = argc;
saved_argv = argv;
int32_t _uya_ret = main_main();
return _uya_ret;
}
