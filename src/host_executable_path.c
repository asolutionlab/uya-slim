/*
 * 宿主可执行文件解析路径（供 Uya get_compiler_dir / UYA_ROOT 推导）。
 * - macOS: _NSGetExecutablePath + realpath
 * - Linux hosted: readlink("/proc/self/exe")
 * - Linux nostdlib 静态链: 原始 readlink  syscall（仅 x86_64，与 compile.sh 一致）
 */
#include <stddef.h>

#if defined(__APPLE__) && defined(__MACH__)

#include <mach-o/dyld.h>
#include <stdlib.h>
#include <string.h>

int uya_host_executable_path(char *buf, size_t cap) {
    uint32_t sz;
    char *resolved;

    if (buf == NULL || cap < 2) {
        return -1;
    }
    sz = cap > (uint32_t)-1 ? (uint32_t)-1 : (uint32_t)cap;
    if (_NSGetExecutablePath(buf, &sz) != 0) {
        return -1;
    }
    resolved = realpath(buf, NULL);
    if (resolved == NULL) {
        return -1;
    }
    {
        size_t n = strlen(resolved);
        if (n + 1 > cap) {
            free(resolved);
            return -1;
        }
        memcpy(buf, resolved, n + 1);
    }
    free(resolved);
    return 0;
}

#elif defined(__linux__) && defined(UYA_HOST_EXE_PATH_SYSCALL)

static long uya_syscall3(long n, long a1, long a2, long a3) {
    long ret;
    __asm__ volatile("syscall"
                     : "=a"(ret)
                     : "a"(n), "D"(a1), "S"(a2), "d"(a3)
                     : "rcx", "r11", "memory");
    return ret;
}

static const char uya_proc_self_exe[] = "/proc/self/exe";

int uya_host_executable_path(char *buf, size_t cap) {
    long n;

    if (buf == NULL || cap < 2) {
        return -1;
    }
    n = uya_syscall3(89, (long)uya_proc_self_exe, (long)buf, (long)(cap - 1));
    if (n < 0 || (size_t)n >= cap) {
        return -1;
    }
    buf[n] = '\0';
    return 0;
}

#elif defined(__linux__)

#include <unistd.h>

int uya_host_executable_path(char *buf, size_t cap) {
    ssize_t n;

    if (buf == NULL || cap < 2) {
        return -1;
    }
    n = readlink("/proc/self/exe", buf, cap - 1);
    if (n < 0) {
        return -1;
    }
    buf[n] = '\0';
    return 0;
}

#else

int uya_host_executable_path(char *buf, size_t cap) {
    (void)buf;
    (void)cap;
    return -1;
}

#endif
