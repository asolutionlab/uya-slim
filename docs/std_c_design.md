# std/libc 标准库设计文档

## 核心目标

1. **编译器完全不依赖外部 C 标准库**
   - Uya 编译器自身使用 libc（自己实现的标准库）
   - 编译器构建时不需要链接 glibc/musl
   - 实现真正的自举：用 Uya 实现的编译器 + 用 Uya 实现的标准库

2. **生成无依赖的 libc 给第三方使用**
   - 通过 `--outlibc` 生成单文件 C 库（libuya.c + libuya.h）
   - 生成的库零外部依赖，可替代 musl/glibc
   - 支持 freestanding 编译（-nostdlib）

---

## 架构概览

```
lib/
├── std/                          # Uya 风格标准库（使用现代特性）
│   ├── core/                     # 核心类型和 trait（v0.6.0 Sprint 6）
│   │   ├── error.uya             # 错误类型定义（使用 union）
│   │   ├── option.uya            # Option<T> = union { Some: T, None }
│   │   ├── result.uya            # Result<T, E> = union { Ok: T, Err: E }
│   │   └── traits.uya            # 核心接口（Clone, Eq, Ord, Hash）
│   ├── io/                       # I/O 抽象（v0.6.0 Sprint 7）
│   │   ├── writer.uya            # interface Writer
│   │   ├── reader.uya            # interface Reader
│   │   └── file.uya              # struct File : Writer, Reader
│   ├── string/                   # 字符串操作（v0.6.0 Sprint 8）
│   │   └── string.uya            # 安全字符串函数
│   ├── mem/                      # 内存操作
│   │   └── mem.uya               # 内存函数
│   ├── collections/              # 泛型容器（v0.6.0 Sprint 9）
│   │   ├── vec.uya               # struct Vec<T>
│   │   └── string_buf.uya        # struct StringBuf
│   ├── syscall/                  # 系统调用封装
│   │   └── linux.uya             # Linux syscall 封装
│   ├── fmt/                      # 格式化
│   │   └── fmt.uya               # format<T: Display>
│   └── runtime/                  # 运行时支持
│       └── runtime.uya           # 程序入口、panic 处理
│
└── libc/                         # C 兼容层（薄封装，v0.6.0 Sprint 10）
    ├── syscall.uya               # syscall 封装（调用 std.syscall）
    ├── string.uya                # C 签名：strlen, strcmp...（调用 std.string）
    ├── stdio.uya                 # C 签名：printf, fopen...（调用 std.io）
    ├── stdlib.uya                # C 签名：malloc, free...（调用 std.mem）
    ├── mem.uya                   # C 签名：memcpy, memset...
    └── unistd.uya                # C 签名：read, write...
```

**分层依赖**：
```
libc/  →  std/  →  syscall/
(C ABI)  (Uya)    (底层)
```

---

## 已实现模块（v0.5.x）

### 1. libc.syscall - 系统调用封装

**文件**：`lib/libc/syscall.uya`

**已实现**：
- ✅ `@syscall` 内置函数封装
- ✅ Linux x86-64 系统调用号常量
- ✅ 系统调用封装：`sys_write`, `sys_read`, `sys_open`, `sys_close`, `sys_exit`, `sys_mmap`, `sys_munmap`, `sys_lseek`, `sys_access`, `sys_unlink`, `sys_mkdir`, `sys_rmdir`, `sys_chdir`, `sys_getcwd`, `sys_getpid`, `sys_getdents64`, `sys_stat`, `sys_readlink`

### 2. libc.string - 字符串操作

**文件**：`lib/libc/string.uya`

**已实现**：
- ✅ `strlen`, `strcmp`, `strncmp`, `strcasecmp`, `strncasecmp`
- ✅ `strcpy`, `strncpy`, `strcat`, `strncat`
- ✅ `strchr`, `strrchr`, `strstr`
- ✅ `strdup`, `strndup`
- ✅ `strcspn`, `strspn`, `strpbrk`, `strtok`

### 3. libc.stdio - 标准 I/O

**文件**：`lib/libc/stdio.uya`

**已实现**：
- ✅ `FILE` 结构体、`stdin`/`stdout`/`stderr`
- ✅ `put_char`, `printf`, `fprintf`, `sprintf`
- ✅ `fopen`, `fclose`, `fread`, `fwrite`
- ✅ `fgets`, `fputs`, `fgetc`, `fputc`
- ✅ `fseek`, `ftell`, `fflush`, `feof`

### 4. libc.stdlib - 标准库

**文件**：`lib/libc/stdlib.uya`

**已实现**：
- ✅ `malloc`, `free`, `calloc`, `realloc`（基于 mmap）
- ✅ `exit`, `abort`
- ✅ `atoi`, `atol`, `atof`, `strtod`, `strtol`, `strtoul`
- ✅ `abs`, `labs`
- ✅ `getenv`, `stat`, `readlink`
- ✅ `opendir`, `readdir`, `closedir`

### 5. libc.mem - 内存操作

**文件**：`lib/libc/mem.uya`

**已实现**：
- ✅ `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`

### 6. libc.unistd - UNIX 标准

**文件**：`lib/libc/unistd.uya`

**已实现**：
- ✅ `read`, `write`, `close`, `lseek`
- ✅ `access`, `unlink`, `mkdir`, `rmdir`, `chdir`, `getcwd`

### 7. libc.ctype - 字符分类

**文件**：`lib/libc/ctype.uya`

**已实现**：
- ✅ `isalpha`, `isdigit`, `isalnum`, `isspace`, `isupper`, `islower`
- ✅ `toupper`, `tolower`

### 8. libc.errno - 错误码

**文件**：`lib/libc/errno.uya`

**已实现**：
- ✅ 标准错误码常量（EPERM, ENOENT, ESRCH, EINTR, EIO, ...）
- ✅ `errno` 全局变量
- ✅ `strerror` - 错误码转字符串

---

## v0.6.0 重构计划

详见 [`docs/std_refactor_design.md`](./std_refactor_design.md)

### Sprint 6: std.core 核心类型

**目标**：实现 Option<T>, Result<T, E>, Error 等核心类型

```uya
// 错误类型定义
union Error {
    None,                        // 无错误
    Message: &[i8],             // 错误消息
    Code: i32,                  // 错误码
    System: i32                 // 系统错误码（errno）
}

// Option<T> - 可选值
union Option<T> {
    Some: T,
    None
}

// Result<T, E> - 结果类型
union Result<T, E: Error> {
    Ok: T,
    Err: E
}

// 核心接口
interface Clone {
    fn clone(self: &Self) Self;
}

interface Eq {
    fn eq(self: &Self, other: &Self) bool;
}

interface Ord {
    fn cmp(self: &Self, other: &Self) i32;
}

interface Hash {
    fn hash(self: &Self) u64;
}

interface Display {
    fn fmt(self: &Self, writer: &Writer) !void;
}
```

### Sprint 7: std.io I/O 抽象层

**目标**：使用 interface 定义 I/O 抽象

```uya
interface Writer {
    fn write(self: &Self, data: &[u8]) !usize;
    fn write_str(self: &Self, s: &const byte) !usize;
    fn flush(self: &Self) !void;
}

interface Reader {
    fn read(self: &Self, buf: &[u8]) !usize;
    fn read_exact(self: &Self, buf: &[u8]) !void;
}

struct File : Writer, Reader {
    fd: i32,
    // ...
}
```

### Sprint 8: std.string 安全字符串操作

**目标**：使用 !T 错误处理重构字符串操作

```uya
// 返回错误版本
export fn parse_int(s: &const byte) !i32;
export fn parse_uint(s: &const byte) !u32;
export fn parse_float(s: &const byte) !f64;

// 安全复制（带边界检查）
export fn copy_safe(dst: &byte, dst_len: usize, src: &const byte) !void;
```

### Sprint 9: std.collections 泛型容器

**目标**：实现泛型容器

```uya
struct Vec<T> {
    data: &T,
    len: usize,
    cap: usize,
    
    fn push(self: &Self, value: T) !void;
    fn pop(self: &Self) Option<T>;
    fn get(self: &Self, i: usize) !&T;
}

struct StringBuf {
    buf: Vec<u8>,
    
    fn push_str(self: &Self, s: &const byte) !void;
    fn as_str(self: &Self) &[i8];
}
```

### Sprint 10: libc 薄封装

**目标**：在 std 基础上实现 C 兼容层

```uya
// libc.string - 调用 std 实现，保持 C 签名
export extern fn strlen(s: *const byte) usize {
    return std.strlen(s as &const byte);
}

export extern fn strcmp(s1: *const byte, s2: *const byte) i32 {
    return std.strcmp(s1 as &const byte, s2 as &const byte);
}
```

---

## --outlibc 功能

**命令**：`uya --outlibc <目录>`

**生成文件**：
- `libuya.h` - 头文件（类型定义 + 函数声明）
- `libuya.c` - 实现文件（所有函数实现）

**使用方法**：
```bash
# 生成库
uya --outlibc /tmp/libuya

# 编译
gcc -c libuya.c -o libuya.o

# freestanding 模式
gcc -nostdlib -ffreestanding your_program.c libuya.o -o your_program -lgcc
```

---

## 核心特性

- ✅ **完全用 Uya 实现**：所有模块都是纯 Uya 代码
- ✅ **零外部依赖**：直接使用系统调用
- ✅ **单文件输出**：`--outlibc` 生成单个 .c 和 .h 文件
- ✅ **可替代 musl/glibc**：兼容 C ABI
- ✅ **零标准库头文件**：生成的代码自己定义所有类型

## v0.6.0 新特性

- 🎯 **类型安全**：std 使用 !T, Option<T>, Result<T, E>
- 🎯 **接口抽象**：Writer, Reader, Clone, Eq, Ord
- 🎯 **泛型容器**：Vec<T>, StringBuf
- 🎯 **libc 薄封装**：调用 std 实现，零重复代码

---

## `std.target`：条件编译宏（需求）

**目标**：在**编译期**按平台裁剪代码，使 Linux 产物不引用 Darwin 符号（反之亦然），从而用纯 Uya 替代编译器里为宿主差异而写的 C 垫片（如 `host_executable_path.c`）。

### 必须区分的维度

| 维度 | 含义 | 典型用途 |
|------|------|----------|
| **宿主（host）** | 正在构建 / 运行当前二进制（如 `bin/uya`）的操作系统与架构 | 编译器自身的 `get_compiler_dir`、`readdir`/`dirent` 布局 |
| **目标（target）** | 用户程序或被编译代码的目标平台（`TARGET_OS` / `UYA_TARGET_OS_*`） | `@asm`、用户态 syscall 映射、`--outlibc` 产物 |

`std.target` 的**首个落地用例**必须能表达 **host**，以便编译器源码在单仓库内维护、交叉构建时行为正确。

### 首个用例（验收标准）

1. **编译器宿主可执行路径**
   - Linux（含 nostdlib）：`/proc/self/exe` + `readlink`（或等价 syscall）。
   - Darwin：`_NSGetExecutablePath` + `realpath`（或等价）。
   - 未选中的宿主分支**不得**进入链接单元（无未解析 Mach 符号出现在 Linux 上等）。

2. **`struct dirent` 布局**
   - Linux glibc x86_64：`d_type` / `d_name` 偏移与当前一致（如 18 / 19）。
   - Darwin：`d_type` / `d_name` 偏移与 `sys/dirent.h` 一致（如 20 / 21）。
   - 同上：仅生成当前 **host** 对应分支，避免运行时探测或 C 里的 `uya_host_dirent_layout()`。

### 与现有能力的关系

- `@asm_target()` 与运行期 `if @asm_target() == …` **不足以**替代上述需求（另一平台代码仍会进入语义/链接路径，除非整段删除）。
- 实现 `std.target` 后，可将 `src/main.uya` 中宿主路径与目录扫描改为条件编译分支，并**删除**仅为此存在的宿主 C 垫片（在构建链全部改接 Uya 之后）。

**跟踪**：路线图见 [`todo_mini_to_full.md`](./todo_mini_to_full.md) 中 `std.target` 条目。
