# libc 改进计划

**版本**: v0.4.0
**日期**: 2026-02-15
**参考**: musl-libc (https://musl.libc.org)

## 当前实现状态

### 已实现模块

| 模块 | 文件 | 主要函数 |
|------|------|----------|
| stdio | `lib/libc/stdio.uya` | fprintf, sprintf, snprintf, fopen, fclose, fread, fwrite, fgetc, fputc, fputs, fflush |
| string | `lib/libc/string.uya` | strlen, strcmp, strncmp, strcpy, strncpy, strcat, strchr, strrchr, strstr |
| mem | `lib/libc/mem.uya` | memcpy, memset, memmove, memcmp, memchr |
| stdlib | `lib/libc/stdlib.uya` | malloc, free, calloc, realloc, exit, abort, atoi, atol, atof, strtod, strtol, stat, opendir, readdir, closedir |
| syscall | `lib/libc/syscall.uya` | sys_read, sys_write, sys_open, sys_close, sys_exit, sys_lseek, sys_mmap, sys_munmap 等 |

---

## 缺失函数分析（参考 musl）

### 1. string.h 缺失函数

| 函数 | 说明 | 优先级 |
|------|------|--------|
| strcasecmp | 大小写不敏感比较 | 高 |
| strncasecmp | 大小写不敏感比较（限定长度） | 高 |
| strcspn | 计算不包含字符集的长度 | 中 |
| strspn | 计算只包含字符集的长度 | 中 |
| strpbrk | 查找字符集中任意字符 | 中 |
| strtok | 字符串分割 | 中 |
| strtok_r | 线程安全的字符串分割 | 低 |
| strerror | 错误码转消息字符串 | 高 |
| strdup | 复制字符串（malloc 分配） | 高 |
| strndup | 复制字符串（限定长度） | 中 |
| strncat | 限定长度连接 | 中 |
| stpcpy | 复制并返回末尾指针 | 低 |
| stpncpy | 限定长度复制并返回末尾指针 | 低 |
| strlcpy | 安全复制（BSD 风格） | 低 |
| strlcat | 安全连接（BSD 风格） | 低 |
| memmem | 在内存中查找子串 | 低 |
| memrchr | 从后往前查找字符 | 低 |
| mempcpy | 复制并返回末尾指针 | 低 |
| bcmp, bcopy, bzero | BSD 兼容函数 | 低 |

### 2. stdio.h 缺失函数

| 函数 | 说明 | 优先级 |
|------|------|--------|
| printf | 标准输出格式化 | 高 |
| vprintf | va_list 版 printf | 高 |
| vfprintf | va_list 版 fprintf | 高 |
| vsprintf | va_list 版 sprintf | 高 |
| vsnprintf | va_list 版 snprintf | 高 |
| scanf | 标准输入格式化 | 中 |
| fscanf | 文件输入格式化 | 中 |
| sscanf | 字符串输入格式化 | 中 |
| fgets | 读取一行 | 高 |
| gets_s | 安全读取一行 | 低 |
| puts | 输出字符串并换行 | 高 |
| rename | 重命名文件 | 中 |
| remove | 删除文件 | 中 |
| tmpfile | 创建临时文件 | 低 |
| tmpnam | 生成临时文件名 | 低 |
| freopen | 重新打开文件 | 低 |
| setbuf, setvbuf | 设置缓冲区 | 低 |
| clearerr | 清除错误标志 | 低 |
| feof | 检查文件结束 | 低 |
| ferror | 检查文件错误 | 低 |
| fileno | 获取文件描述符 | 中 |
| fdopen | 从文件描述符创建流 | 中 |
| perror | 输出错误信息 | 高 |
| dprintf | 格式化输出到文件描述符 | 中 |
| asprintf | 格式化到动态分配内存 | 低 |

### 3. stdlib.h 缺失函数

| 函数 | 说明 | 优先级 |
|------|------|--------|
| getenv | 获取环境变量（需实现） | 高 |
| setenv | 设置环境变量 | 中 |
| unsetenv | 删除环境变量 | 中 |
| putenv | 设置环境变量（POSIX） | 中 |
| system | 执行 shell 命令 | 低 |
| rand | 生成随机数 | 中 |
| srand | 设置随机数种子 | 中 |
| abs | 整数绝对值 | 高 |
| labs | 长整数绝对值 | 高 |
| llabs | 长长整数绝对值 | 中 |
| div | 整数除法 | 低 |
| ldiv | 长整数除法 | 低 |
| lldiv | 长长整数除法 | 低 |
| qsort | 快速排序 | 高 |
| bsearch | 二分搜索 | 中 |
| realpath | 解析绝对路径 | 中 |
| strtoul | 字符串转无符号长整数 | 高 |
| strtoull | 字符串转无符号长长整数 | 中 |
| strtof | 字符串转浮点数 | 中 |
| strtold | 字符串转长双精度 | 低 |
| atoll | 字符串转长长整数 | 中 |
| lltostr | 长长整数转字符串（非标准） | 低 |

### 4. ctype.h 缺失模块

需要新建 `lib/libc/ctype.uya`：

| 函数 | 说明 | 优先级 |
|------|------|--------|
| isalpha | 是否字母 | 高 |
| isdigit | 是否数字 | 高 |
| isalnum | 是否字母或数字 | 高 |
| isspace | 是否空白字符 | 高 |
| isupper | 是否大写字母 | 高 |
| islower | 是否小写字母 | 高 |
| isprint | 是否可打印字符 | 中 |
| ispunct | 是否标点符号 | 中 |
| iscntrl | 是否控制字符 | 低 |
| isxdigit | 是否十六进制数字 | 中 |
| isgraph | 是否图形字符 | 低 |
| isblank | 是否空白 | 低 |
| toupper | 转大写 | 高 |
| tolower | 转小写 | 高 |
| isascii | 是否 ASCII 字符 | 低 |
| toascii | 转 ASCII | 低 |

### 5. unistd.h 缺失模块

需要新建 `lib/libc/unistd.uya`，封装系统调用：

| 函数 | 说明 | 优先级 |
|------|------|--------|
| read | 读文件 | 高 |
| write | 写文件 | 高 |
| close | 关闭文件 | 高 |
| lseek | 移动文件指针 | 高 |
| access | 检查文件权限 | 中 |
| unlink | 删除文件 | 中 |
| mkdir | 创建目录 | 中 |
| rmdir | 删除目录 | 中 |
| chdir | 切换目录 | 中 |
| getcwd | 获取当前目录 | 中 |
| fork | 创建进程 | 中 |
| execve | 执行程序 | 中 |
| execl, execv, execlp, execvp | exec 族函数 | 中 |
| dup | 复制文件描述符 | 中 |
| dup2 | 复制文件描述符到指定位置 | 中 |
| pipe | 创建管道 | 中 |
| sleep | 休眠 | 中 |
| usleep | 微秒休眠 | 低 |
| getpid | 获取进程 ID | 高 |
| getppid | 获取父进程 ID | 中 |
| getuid, geteuid | 获取用户 ID | 低 |
| getgid, getegid | 获取组 ID | 低 |
| isatty | 是否终端 | 中 |
| ttyname | 终端名称 | 低 |

### 6. fcntl.h 缺失模块

需要新建 `lib/libc/fcntl.uya`：

| 函数 | 说明 | 优先级 |
|------|------|--------|
| open | 打开文件 | 高 |
| openat | 相对路径打开 | 低 |
| creat | 创建文件 | 中 |
| fcntl | 文件控制 | 中 |
| flock | 文件锁 | 低 |

### 7. errno.h 缺失模块

需要新建 `lib/libc/errno.uya`：

| 内容 | 说明 | 优先级 |
|------|------|--------|
| errno 变量 | 全局错误码 | 高 |
| 错误码常量 | EPERM, ENOENT 等 | 高 |
| strerror | 错误消息 | 高 |

### 8. time.h 缺失模块

需要新建 `lib/libc/time.uya`：

| 函数 | 说明 | 优先级 |
|------|------|--------|
| time | 获取时间 | 中 |
| clock | 获取时钟 | 低 |
| difftime | 时间差 | 低 |
| mktime | 时间转时间戳 | 低 |
| strftime | 时间格式化 | 中 |
| localtime | 时间戳转本地时间 | 中 |
| gmtime | 时间戳转 UTC 时间 | 中 |
| asctime | 时间转字符串 | 低 |
| ctime | 时间戳转字符串 | 低 |
| nanosleep | 纳秒休眠 | 低 |
| clock_gettime | 高精度时间 | 中 |
| gettimeofday | 获取时间（BSD） | 中 |

---

## 实现优先级

### 第一阶段：核心完善（高优先级）

1. **ctype.uya** - 字符分类函数
2. **errno.uya** - 错误处理
3. **unistd.uya** - POSIX 系统调用封装
4. **完善 string.uya** - strcasecmp, strdup, strerror
5. **完善 stdio.uya** - printf, vfprintf, fgets, puts, perror
6. **完善 stdlib.uya** - getenv, abs, qsort, strtoul

### 第二阶段：功能扩展（中优先级）

1. **fcntl.uya** - 文件控制
2. **time.uya** - 时间函数
3. 完善 scanf 族函数
4. 完善 exec 族函数
5. 完善 string 函数（strtok, strcspn, strspn）

### 第三阶段：完善补充（低优先级）

1. BSD 兼容函数
2. 非标准扩展函数
3. 性能优化（参考 musl 优化实现）

---

## 参考资源

- **musl-libc 源码**: `musl-src/` 目录
- **musl 官网**: https://musl.libc.org
- **POSIX 标准**: https://pubs.opengroup.org/onlinepubs/9699919799/
- **Linux man pages**: https://man7.org/linux/man-pages/

---

## 测试目标

### musl 测试套件兼容

最终目标：**通过 musl 官方测试套件**

- **musl 测试源码**: `musl-src/crt/` 和 `musl-src/src/*/`
- **测试方法**: 编译 musl 测试程序，链接 Uya libc，验证行为一致性
- **关键测试项**:
  - string 函数：边界条件、重叠区域、NULL 处理
  - stdio 函数：格式化输出、文件操作、缓冲管理
  - ctype 函数：字符分类正确性、EOF 处理
  - stdlib 函数：内存分配、字符串转换、排序算法
  - errno 设置：各函数错误码正确性

### TDD 开发流程

1. **先写测试**: 每个函数先编写测试用例 `tests/programs/test_*.uya`
2. **编译验证**: 使用 `bin/uya --c99 --nostdlib` 编译测试
3. **运行测试**: 链接 musl 测试套件或自定义测试
4. **实现函数**: 根据测试失败情况实现函数
5. **回归测试**: 确保新实现不破坏现有功能

### 测试框架设计

#### 设计理念

充分利用 Uya 的 error 类型系统：

1. **`!T` 错误联合类型**：测试函数返回 `!void`，失败时返回 error
2. **`try` 自动传播**：断言失败自动传播，无需手动检查
3. **`errdefer` 资源清理**：错误时自动清理资源
4. **统一错误码约定**：返回失败数（0=全部通过）

#### 测试框架核心 (`lib/std/testing.uya`)

```uya
use std.testing.*;

// 测试函数签名：返回 !void
fn test_feature() !void {
    const result: i32 = compute(2, 3);
    try assert_eq_i32(result, 5, "2 + 3 should equal 5");
}

fn test_with_resource() !void {
    var resource: Resource = try create_resource();
    
    // 错误时自动清理
    errdefer {
        cleanup_on_error(resource);
    }
    
    // 正常时也清理
    defer {
        cleanup(resource);
    }
    
    try assert_not_null(resource.data, "resource should have data");
}

// 主函数：运行测试套件
fn main() i32 {
    test_suite_begin("Feature Tests");
    
    run_test("basic feature", test_feature);
    run_test("with resource", test_with_resource);
    
    return test_suite_end();  // 返回失败数
}
```

#### 断言函数列表

| 函数 | 说明 |
|------|------|
| `assert(condition, message)` | 基本断言 |
| `assert_eq_i32(actual, expected, msg)` | i32 相等 |
| `assert_eq_bool(actual, expected, msg)` | bool 相等 |
| `assert_ne_i32(actual, expected, msg)` | i32 不等 |
| `assert_gt_i32(actual, expected, msg)` | i32 大于 |
| `assert_lt_i32(actual, expected, msg)` | i32 小于 |
| `assert_null(ptr, msg)` | 空指针 |
| `assert_not_null(ptr, msg)` | 非空指针 |
| `expect(condition)` | 简写断言 |
| `expect_eq(actual, expected)` | 简写相等 |
| `expect_true(value)` | 期望 true |
| `expect_false(value)` | 期望 false |

#### 测试输出格式

```
=== Test Suite: libc.string ===
  TEST: strlen ... OK
  TEST: strcmp ... FAILED
    ASSERT FAILED: strcmp should return 0 for equal strings
      Expected: 0
      Actual:   1
  TEST: strcpy ... OK

=== Results ===
  Passed:  2
  Failed:  1
  Skipped: 0
==================
```

#### 编译运行

```bash
# 编译
bin/uya-c --c99 tests/programs/test_xxx.uya -o /tmp/test_xxx.c

# 构建
gcc -std=c99 -no-pie -o /tmp/test_xxx /tmp/test_xxx.c tests/bridge.c -lm

# 运行
/tmp/test_xxx
echo $?  # 0=全部通过，非零=失败数
```

---

## 实现注意事项

1. **零依赖原则**: 所有函数基于系统调用实现，不依赖外部 C 库
2. **C 标准兼容**: 函数签名与 C 标准库一致，使用 `export extern "libc" fn`
3. **简化实现**: 优先实现正确性，性能优化后续迭代
4. **错误处理**: 使用 `!T` 错误联合类型，与 Uya 错误处理机制一致
5. **线程安全**: 注意全局状态管理，优先实现线程安全版本
