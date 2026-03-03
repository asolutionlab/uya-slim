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
- [x] `fwrite` - 写入文件（已优化，使用缓冲机制）
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

### 4. 标准库函数 (`lib/libc/stdlib.uya`)

- [x] `malloc` - 动态内存分配（已优化，参考musl实现）
- [x] `free` - 释放动态内存（已优化，支持块合并）
- [x] `calloc` - 分配并初始化为0的内存
- [x] `realloc` - 重新分配内存（已优化，正确复制旧数据）
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

### 6. 文件系统相关 (`lib/libc/stdio.uya`)

- [x] `stat` - 获取文件状态
- [x] `opendir` - 打开目录
- [x] `readdir` - 读取目录项
- [x] `closedir` - 关闭目录
- [x] `readlink` - 读取符号链接
- [x] `getenv` - 获取环境变量

## 待实现功能

### 1. 字符串操作函数

- [ ] `strcat` - 字符串连接
- [ ] `strncat` - 连接字符串的前n个字符
- [ ] `strspn` - 扫描字符串
- [ ] `strcspn` - 扫描字符串补集
- [ ] `strpbrk` - 字符串中查找任一字符
- [ ] `strtok` - 字符串分割
- [ ] `strerror` - 错误信息字符串

### 2. 标准输入输出函数

- [ ] `fscanf` - 格式化输入（从文件）
- [ ] `sscanf` - 格式化输入（从字符串）
- [ ] `vfprintf` - 可变参数格式化输出
- [ ] `vprintf` - 可变参数格式化输出到标准输出
- [ ] `vsprintf` - 可变参数格式化到字符串
- [ ] `vsnprintf` - 可变参数格式化到字符串（限制长度）
- [x] `remove` - 删除文件
- [x] `rename` - 重命名文件
- [x] `tmpfile` - 创建临时文件
- [x] `tmpnam` - 生成临时文件名
- [ ] `setbuf` - 设置缓冲区
- [ ] `setvbuf` - 设置缓冲区及模式
- [ ] `fgetpos` - 获取文件位置
- [ ] `fsetpos` - 设置文件位置

### 3. 标准库函数

- [x] `div` - 整数除法
- [x] `ldiv` - 长整型除法
- [x] `lldiv` - 长长整型除法
- [x] `atoll` - 字符串转长长整型
- [x] `strtoll` - 字符串转长长整型
- [x] `strtoull` - 字符串转无符号长长整型
- [x] `strtoul` - 字符串转无符号长整型
- [x] `rand` - 随机数生成
- [x] `srand` - 设置随机数种子
- [x] `qsort` - 快速排序
- [x] `bsearch` - 二分查找
- [ ] `mbstowcs` - 多字节字符串转宽字符串
- [ ] `wcstombs` - 宽字符串转多字节字符串
- [ ] `system` - 执行系统命令（部分实现）

### 4. 字符分类函数 (`lib/libc/ctype.uya`)

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
- [x] `tolower` - 转小写
- [x] `toupper` - 转大写

### 5. 数学函数 (`lib/libc/math.uya`)

- [x] `sin`, `cos`, `tan` - 三角函数
- [x] `asin`, `acos`, `atan`, `atan2` - 反三角函数
- [x] `sinh`, `cosh`, `tanh` - 双曲函数
- [x] `asinh`, `acosh`, `atanh` - 反双曲函数
- [x] `exp`, `log`, `log10`, `log2` - 指数对数函数
- [x] `pow`, `sqrt`, `cbrt` - 幂函数
- [x] `ceil`, `floor`, `trunc`, `round`, `nearbyint`, `rint` - 舍入函数
- [x] `fabs`, `fmod`, `remainder` - 浮点数运算
- [x] `fmax`, `fmin`, `fdim` - 最值函数
- [x] `hypot` - 斜边函数
- [x] `copysign`, `nextafter`, `nan` - 浮点数操作

### 6. 时间日期函数 (`lib/libc/time.uya`)

- [x] `time` - 获取时间
- [x] `clock` - 获取处理器时间
- [x] `difftime` - 计算时间差
- [x] `mktime` - 转换为日历时间
- [x] `strftime` - 格式化时间
- [x] `asctime` - 时间转字符串
- [x] `ctime` - 日历时间转字符串
- [x] `gmtime` - UTC时间
- [x] `localtime` - 本地时间

### 7. 信号处理函数 (`lib/libc/signal.uya`)

- [x] `signal` - 信号处理
- [x] `raise` - 发送信号

- [x] `kill` - 发送信号到进程
- [x] `sigprocmask` - 设置信号掩码
- [x] `sigpending` - 检查挂起信号
- [x] `sigsuspend` - 原子地替换信号掩码并挂起
- [x] `alarm` - 设置定时器
- [x] `pause` - 挂起进程直到信号
- [x] `sigemptyset` - 初始化空信号集
- [x] `sigfillset` - 初始化满信号集
- [x] `sigaddset` - 添加信号到集合
- [x] `sigdelset` - 从集合删除信号
- [x] `sigismember` - 测试信号是否在集合中
- [x] `atexit` - 注册退出处理函数
- [x] `on_exit` - 注册退出处理函数（带参数）
### 8. 非局部跳转函数 (`lib/libc/setjmp.uya`)

- [x] `setjmp` - 设置非局部跳转点
- [x] `longjmp` - 非局部跳转
- [x] `sigsetjmp` - 设置非局部跳转点（保存信号掩码）
- [x] `siglongjmp` - 非局部跳转（恢复信号掩码）
- [x] `_setjmp` - 简化版设置跳转点
- [x] `_longjmp` - 简化版非局部跳转

### 9. 可变参数函数 (`lib/libc/stdarg.uya`)

- [x] `va_start`, `va_arg`, `va_end` - 可变参数处理

- [x] `va_copy` - 复制 va_list
## 优化建议

### 1. 性能优化

- [x] **内存分配器优化**: [malloc](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L15-L32)/[free](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L34-L40)/[realloc](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L63-L81)现在参考musl实现，使用空闲链表和块合并策略
- [ ] **字符串操作优化**: 优化[strlen](file:///media/winger/_dde_home/winger/uya/lib/libc/string.uya#L15-L22)等函数，考虑使用SIMD指令或一次处理多个字节
- [x] **I/O缓冲机制**: 实现缓冲机制以减少系统调用次数，提升[fwrite](file:///media/winger/_dde_home/winger/uya/lib/libc/stdio.uya#L678-L688)、[fread](file:///media/winger/_dde_home/winger/uya/lib/libc/stdio.uya#L335-L356)等函数的性能
- [ ] **格式化函数优化**: 改进[printf](file:///media/winger/_dde_home/winger/uya/lib/libc/stdio.uya#L989-L993)系列函数，支持更多格式化选项和更好的性能

### 2. 功能增强

- [x] **完善realloc实现**: 现在的[realloc](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L63-L81)已能正确复制旧数据
- [ ] **错误处理机制**: 为所有函数实现适当的错误报告机制，设置errno
- [ ] **边界检查**: 为字符串和内存函数增加边界检查，防止缓冲区溢出
- [ ] **线程安全性**: 添加必要的同步机制，使函数在多线程环境下安全使用

### 3. 代码结构优化

- [ ] **模块分离**: 将功能更细致地拆分到不同的模块中，提高可维护性
- [ ] **API统一**: 确保所有相似功能的API保持一致的命名和行为
- [ ] **文档完善**: 为所有函数添加详细文档说明
- [ ] **单元测试**: 为所有函数编写充分的单元测试

### 4. 兼容性改进

- [ ] **C ABI兼容**: 确保函数签名与C标准库完全兼容
- [ ] **错误值一致性**: 确保错误返回值与C标准库一致
- [ ] **行为一致性**: 确保函数行为与C标准库一致，包括边界情况

## 长期规划

### 1. 完成标准库迁移

- [ ] 将更多功能迁移到`std.*`模块
- [ ] 提供现代化的API，同时保留传统的libc接口
- [ ] 实现泛型容器和算法

### 2. 性能基准测试

- [ ] 建立性能基准测试套件
- [ ] 与系统libc进行性能对比
- [ ] 持续优化热点函数

### 3. 跨平台支持

- [ ] 抽象系统调用层，支持不同操作系统
- [ ] 实现POSIX兼容层
- [ ] 添加Windows支持

## 总结

当前 Uya 的 libc 实现已经覆盖了核心功能，包括基本的字符串操作、内存管理、文件I/O、标准库函数和系统调用等。我们已经完成了几个重要的优化：

1. **内存分配器优化**：重构了[malloc](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L15-L32)、[free](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L34-L40)和[realloc](file:///media/winger/_dde_home/winger/uya/lib/libc/stdlib.uya#L63-L81)函数，参考musl实现，使用空闲链表和块合并策略，提高了内存利用率
2. **I/O缓冲机制**：为stdio函数添加了缓冲机制，减少了系统调用的频率

目前，数学函数、时间日期函数、字符分类函数、信号处理、非局部跳转和可变参数函数等模块已经实现。但仍有一些字符串操作函数（如 strcat、strncat、strtok 等）、标准输入输出函数（如 fscanf、sscanf、vfprintf 等）以及部分高级功能有待完善。

项目整体上朝着实现一个完整的C标准库子集的方向发展，并逐步将功能迁移到更现代的 `std.*` 模块中。未来的工作重点应放在性能优化、功能完整性和跨平台支持上。