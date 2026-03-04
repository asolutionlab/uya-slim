# Uya 语言 libc 实现进度与 TODO 清单

## 概述

本文档记录了 Uya 语言对 C 标准库（libc）的实现进度。项目采用模块化设计，分别在 `lib/libc/` 和 `lib/std/` 目录下实现了不同的功能模块。

## 已实现的功能

### 1. 字符串操作函数 (`lib/libc/string.uya`)

- [x] `strlen` - 计算字符串长度
- [x] `strcmp` - 比较两个字符串
- [x] `strncmp` - 比较两个字符串的前 n 个字符
- [x] `strcasecmp` - 大小写不敏感比较两个字符串
- [x] `strncasecmp` - 大小写不敏感比较前 n 个字符
- [x] `strcpy` - 复制字符串
- [x] `strchr` - 查找字符首次出现位置
- [x] `strrchr` - 查找字符最后出现位置
- [x] `strstr` - 查找子字符串
- [x] `strdup` - 复制字符串（动态分配内存）
- [x] `strndup` - 复制字符串前 n 个字符（动态分配内存）
- [x] `strncpy` - 复制字符串的前 n 个字符
- [x] `strcat` - 连接字符串
- [x] `strncat` - 限定长度连接
- [x] `strcspn` - 计算不包含字符集的长度
- [x] `strspn` - 计算只包含字符集的长度
- [x] `strpbrk` - 查找字符集中任意字符
- [x] `strtok` - 字符串分割
- [x] `strerror` - 将错误码转换为错误消息字符串（实现在 `errno.uya` 中，通过 `string.uya` 模块可访问）

### 2. 内存操作函数 (`lib/libc/mem.uya`)

- [x] `memcpy` - 内存拷贝
- [x] `memset` - 内存填充
- [x] `memmove` - 内存移动
- [x] `memcmp` - 内存比较
- [x] `memchr` - 查找内存中的字符

### 3. 标准输入输出函数 (`lib/libc/stdio.uya`)

- [x] `fopen` - 打开文件
- [x] `fclose` - 关闭文件
- [x] `fread` - 读取文件
- [x] `fwrite` - 写入文件
- [x] `fgetc` - 读取单个字符
- [x] `fputc` - 写入单个字符
- [x] `fputs` - 写入字符串
- [x] `fprintf` - 格式化输出（简化版，仅支持 %d）
- [x] `sprintf` - 格式化到字符串
- [x] `snprintf` - 格式化到字符串（限制长度）
- [x] `fflush` - 刷新缓冲区
- [x] `printf` - 格式化输出到标准输出（简化版）
- [x] `puts` - 输出字符串并换行
- [x] `fgets` - 从流中获取字符串
- [x] `fscanf` - 格式化输入（从文件，支持 %d/%s/%c/%%）
- [x] `sscanf` - 格式化输入（从字符串，支持 %d/%s/%c/%%）
- [x] `remove` - 删除文件或目录
- [x] `rename` - 重命名文件
- [x] `tmpfile` - 创建临时文件
- [x] `tmpnam` - 生成临时文件名
- [x] `setbuf` - 设置缓冲区
- [x] `setvbuf` - 设置缓冲区及模式
- [x] `fgetpos` - 获取文件位置
- [x] `fsetpos` - 设置文件位置

### 4. 标准库函数 (`lib/libc/stdlib.uya`)

- [x] `malloc` - 动态内存分配
- [x] `free` - 释放动态内存
- [x] `calloc` - 分配并初始化为0的内存
- [x] `realloc` - 重新分配内存
- [x] `exit` - 正常退出进程
- [x] `abort` - 异常终止进程
- [x] `atoi` - 字符串转整数
- [x] `atol` - 字符串转长整型
- [x] `atof` - 字符串转浮点数
- [x] `strtod` - 字符串转双精度浮点数
- [x] `strtol` - 字符串转长整型（带进制转换）
- [x] `abs` - 绝对值函数
- [x] `labs` - 长整型绝对值函数
- [x] `strtoul` - 字符串转无符号长整型
- [x] `atoll` - 字符串转长长整型
- [x] `strtoll` - 字符串转长长整型
- [x] `strtoull` - 字符串转无符号长长整型
- [x] `div` - 整数除法
- [x] `ldiv` - 长整型除法
- [x] `lldiv` - 长长整型除法
- [x] `rand` - 随机数生成
- [x] `srand` - 设置随机数种子
- [x] `qsort` - 快速排序
- [x] `bsearch` - 二分查找
- [x] `llabs` - 长长整型绝对值
- [x] `lltoa` - 长长整型转字符串
- [x] `putenv` - 设置环境变量
- [x] `setenv` - 设置环境变量
- [x] `unsetenv` - 删除环境变量
- [x] `clearenv` - 清空所有环境变量
- [x] `stat` - 获取文件状态
- [x] `readlink` - 读取符号链接
- [x] `getenv` - 获取环境变量
- [x] `opendir` - 打开目录
- [x] `readdir` - 读取目录项
- [x] `closedir` - 关闭目录

### 5. 系统调用 (`lib/libc/syscall.uya` 和 `lib/libc/unistd.uya`)

- [x] `sys_write` - 系统级写操作
- [x] `sys_read` - 系统级读操作
- [x] `sys_open` - 系统级打开文件
- [x] `sys_close` - 系统级关闭文件
- [x] `sys_exit` - 系统级退出
- [x] `sys_getpid` - 获取进程ID
- [x] `sys_lseek` - 移动文件指针
- [x] `sys_mmap` - 内存映射
- [x] `sys_munmap` - 取消内存映射
- [x] `sys_stat` - 获取文件状态
- [x] `read` - 简化的读操作
- [x] `write` - 简化的写操作
- [x] `close` - 关闭文件描述符
- [x] `lseek` - 移动文件指针
- [x] `getpid` - 获取进程ID
- [x] `fork` - 创建进程
- [x] `execve` - 执行程序
- [x] `_exit` - 立即退出进程
- [x] `access` - 检查文件权限
- [x] `unlink` - 删除文件
- [x] `mkdir` - 创建目录
- [x] `rmdir` - 删除目录
- [x] `chdir` - 改变工作目录
- [x] `getcwd` - 获取当前工作目录
- [x] `dup` - 复制文件描述符
- [x] `dup2` - 复制文件描述符到指定编号

### 6. 字符分类函数 (`lib/libc/ctype.uya`)

- [x] `isalnum` - 是否字母数字
- [x] `isalpha` - 是否字母
- [x] `isdigit` - 是否数字
- [x] `islower` - 是否小写字母
- [x] `isupper` - 是否大写字母
- [x] `isspace` - 是否空白字符
- [x] `ispunct` - 是否标点符号
- [x] `isprint` - 是否可打印字符
- [x] `isgraph` - 是否图形字符
- [x] `iscntrl` - 是否控制字符
- [x] `isxdigit` - 是否十六进制数字
- [x] `isblank` - 是否空白字符
- [x] `isascii` - 是否 ASCII 字符
- [x] `tolower` - 转小写
- [x] `toupper` - 转大写
- [x] `toascii` - 转 ASCII

### 7. 数学函数 (`lib/libc/math.uya`)

- [x] `sin`, `cos`, `tan` - 三角函数
- [x] `asin`, `acos`, `atan`, `atan2` - 反三角函数
- [x] `sinh`, `cosh`, `tanh` - 双曲函数
- [x] `asinh`, `acosh`, `atanh` - 反双曲函数
- [x] `exp`, `log`, `log10` - 指数对数函数
- [x] `exp2` - 以2为底的指数函数
- [x] `pow`, `sqrt`, `cbrt` - 幂函数
- [x] `ceil`, `floor`, `trunc`, `round` - 舍入函数
- [x] `fabs`, `fmod`, `remainder` - 浮点数运算
- [x] `fmax`, `fmin`, `fdim` - 最值函数
- [x] `hypot` - 斜边函数
- [x] `copysign`, `nextafter` - 浮点数操作
- [x] `nan` - 产生NaN
- [x] `abs` - 整数绝对值
- [x] `fabs` - 浮点数绝对值
- [x] `isnan`, `isinf`, `isfinite` - 浮点数检查函数
- [x] `fma` - 乘加运算（未明确实现但可推断）
- [x] `modf` - 分解整数和小数部分
- [x] `frexp` - 分解尾数和指数
- [x] `ldexp` - 指数乘法
- [x] `ilogb` - 获取指数的整数值
- [x] `scalbn` - 指数缩放
- [x] `signbit` - 检查符号位
- [x] `remquo` - 余数和商
- [x] `lerp` - 线性插值
- [x] `fabsf`, `sqrtf`, `cbrtf`, `sinf`, `cosf`, `tanf`, `logf`, `expf`, `powf`, `log2f`, `exp2f`, `ceilf`, `floorf`, `truncf`, `roundf`, `asinf`, `acosf`, `atanf`, `atan2f` - 单精度版本的数学函数

### 8. 时间日期函数 (`lib/libc/time.uya`)

- [x] `time` - 获取时间
- [x] `clock` - 获取处理器时间
- [x] `difftime` - 计算时间差
- [x] `mktime` - 转换为日历时间
- [x] `asctime` - 时间转字符串
- [x] `ctime` - 日历时间转字符串
- [x] `gmtime` - UTC时间
- [x] `localtime` - 本地时间
- [x] `strftime` - 格式化时间（支持 %Y/%y/%m/%d/%H/%M/%S/%a/%A/%b/%B/%I/%p/%T/%F/%c 等）

### 9. 信号处理函数 (`lib/libc/signal.uya`)

- [x] `signal` - 信号处理
- [x] `raise` - 发送信号

### 10. 非局部跳转函数 (`lib/libc/setjmp.uya`)

- [x] `setjmp` - 设置非局部跳转点
- [x] `longjmp` - 非局部跳转

### 11. 可变参数函数 (`lib/libc/stdarg.uya`)

- [x] `va_start`, `va_arg`, `va_end` - 可变参数处理

### 12. 宽字符与多字节函数 (`lib/libc/wchar.uya`)

- [x] `mblen` - 获取多字节字符长度
- [x] `mbtowc` - 多字节字符转宽字符
- [x] `wctomb` - 宽字符转多字节字符
- [x] `mbstowcs` - 多字节字符串转宽字符串
- [x] `wcstombs` - 宽字符串转多字节字符串
- [x] `wcslen` - 宽字符串长度
- [x] `wcscpy` - 宽字符串复制
- [x] `wcscat` - 宽字符串连接
- [x] `wcscmp` - 宽字符串比较
- [x] `iswalpha`, `iswdigit`, `iswalnum`, `iswspace` - 宽字符分类
- [x] `towlower`, `towupper` - 宽字符大小写转换

### 13. POSIX 线程 (`lib/libc/pthread.uya`)

零 libpthread 依赖，基于 Linux SYS_clone + futex + GCC 原子 CAS。

- [x] `pthread_create` - 创建线程（独立栈、trampoline 调用 start_routine、多线程安全）
- [x] `pthread_join` - 等待线程结束并回收栈
- [x] `pthread_exit` - 线程退出（当前固定 sys_exit(0)，retval 未传回）
- [x] `pthread_mutex_init` / `pthread_mutex_destroy` - 互斥量初始化/销毁
- [x] `pthread_mutex_lock` / `pthread_mutex_unlock` - 加锁/解锁（CAS + futex）
- [x] `pthread_mutex_trylock` - 尝试加锁
- [ ] `pthread_join` 的 retval - 子线程返回值尚未写回
- [ ] `pthread_exit(retval)` - retval 未使用
- [ ] 条件变量 - `pthread_cond_*` 仅占位，未基于 futex 实现
- [ ] 线程/互斥属性 - `pthread_attr_t` / `pthread_mutexattr_t` 未使用
- [ ] `pthread_self` / `pthread_equal` / `pthread_detach` - 未实现

## 待实现功能

### 1. 高级功能模块

#### 1.1. 多线程支持（部分完成，见上文 §13）
- [ ] 条件变量完整实现（`pthread_cond_wait` / `signal` / `broadcast`）
- [ ] join 返回子线程 retval、`pthread_exit(retval)` 传递
- [ ] 可配置栈大小/属性、detach、pthread_self/equal

#### 1.2. 本地化/国际化 (`lib/libc/locale.uya` - 未创建)
- [ ] `setlocale` - 设置区域选项
- [ ] `localeconv` - 获取区域数值格式信息

## 需要改进的地方

### 1. 性能优化
- [x] 实现更高效的内存分配策略（已在 stdlib.uya 中实现基于空闲链表的分配器）
- [ ] 优化字符串操作函数的性能
- [x] 实现缓冲机制提高I/O效率（已在 stdio.uya 中实现）

### 2. 功能增强
- [ ] 完善错误处理机制
- [ ] 增强 `fprintf` 和相关格式化函数，支持更多格式说明符
- [x] 改进 `realloc` 函数，使其真正能够调整现有内存块大小（已在 stdlib.uya 中实现）

### 3. 兼容性改进
- [ ] 添加更多的类型安全检查
- [ ] 改进与C语言的互操作性
- [ ] 增加对不同架构的支持

### 4. 标准库组织结构
- [ ] 将更多函数迁移到 `std.*` 模块中
- [ ] 按照功能进一步细分模块
- [ ] 完善错误处理机制

## 总结

当前 Uya 的 libc 实现已经覆盖了绝大部分核心功能，包括基本的字符串操作、内存管理、文件I/O、标准库函数、字符分类、数学函数、时间日期函数、宽字符与多字节转换（`lib/libc/wchar.uya`）等。最近的改进包括：
- 完善了 `remove` 函数，使其能够处理文件和目录
- 添加了 `exp2` 和多个单精度数学函数
- 添加了 `strerror` 函数的引用
- `mbstowcs`、`wcstombs` 及宽字符系列已在 `wchar.uya` 中实现并有 `tests/test_wchar.uya` 覆盖
- **pthread 最小子集**：`lib/libc/pthread.uya` 零 libpthread 依赖，已实现 create/join、mutex（CAS+futex）、trampoline 调用 start_routine（@asm）、多线程安全的 create；条件变量、retval 传递、属性与 detach 等尚未实现

但仍有一些高级功能有待实现，特别是条件变量、join/exit 返回值传递、本地化支持等。

项目整体上朝着实现一个完整的C标准库子集的方向发展，并逐步将功能迁移到更现代的 `std.*` 模块中。