# 标准库重构设计文档 v0.6.0

## 概述

本设计文档描述 Uya 标准库的重构计划，核心目标是：

1. **std 使用 Uya 现代特性**：`!T`, `interface`, 泛型, `union`, `mc`
2. **libc 是 std 的薄封装**：保持 C99 ABI 兼容，内部调用 std
3. **分层架构**：libc → std → syscall

## 设计原则

### 1. std 层：Uya 原生风格

使用 Uya 的类型安全特性：

```uya
// 错误处理：使用 !T 替代裸指针/null 返回
fn parse_int(s: &const byte) !i32 {
    // 成功返回值，失败返回 error
}

// 类型安全：使用 union Option<T> 和 Result<T, E>
union Option<T> {
    Some: T,
    None
}

union Result<T, E> {
    Ok: T,
    Err: E
}

// 接口抽象：使用 interface 定义行为
interface Writer {
    fn write(self: &Self, data: &[u8]) !usize;
    fn flush(self: &Self) !void;
}

// 泛型容器：类型安全的集合
struct Vec<T> {
    data: &T,
    len: usize,
    cap: usize,
}
```

### 2. libc 层：C99 兼容

薄封装，保持 C 签名：

```uya
// C 签名，内部调用 std 实现
export extern fn strlen(s: *const byte) usize {
    return std.strlen(s as &const byte);
}

export extern fn fopen(path: *const byte, mode: *const byte) *FILE {
    // 转换并调用 std.io.File.open
}
```

## 架构设计

```
lib/
├── std/                          # Uya 风格标准库
│   ├── core/                     # 核心类型（Sprint 6）
│   │   ├── error.uya             # 错误类型
│   │   ├── option.uya            # Option<T>
│   │   ├── result.uya            # Result<T, E>
│   │   └── traits.uya            # Clone, Eq, Ord, Hash, Display
│   │
│   ├── io/                       # I/O 抽象（Sprint 7）
│   │   ├── writer.uya            # interface Writer
│   │   ├── reader.uya            # interface Reader
│   │   └── file.uya              # struct File : Writer, Reader
│   │
│   ├── string/                   # 字符串操作（Sprint 8）
│   │   └── string.uya            # 安全字符串函数
│   │
│   ├── mem/                      # 内存操作
│   │   └── mem.uya               # copy, set, cmp
│   │
│   ├── collections/              # 泛型容器（Sprint 9）
│   │   ├── vec.uya               # Vec<T>
│   │   └── string_buf.uya        # StringBuf
│   │
│   ├── syscall/                  # 系统调用
│   │   └── linux.uya             # Linux syscall 封装
│   │
│   ├── fmt/                      # 格式化
│   │   └── fmt.uya               # format<T: Display>
│   │
│   └── runtime/                  # 运行时
│       └── runtime.uya           # panic, entry
│
└── libc/                         # C 兼容层（Sprint 10）
    ├── syscall.uya               # syscall 封装
    ├── string.uya                # strlen, strcmp, strcpy...
    ├── stdio.uya                 # printf, fopen, fclose...
    ├── stdlib.uya                # malloc, free, atoi...
    ├── mem.uya                   # memcpy, memset...
    └── unistd.uya                # read, write, close...
```

## Sprint 6: std.core 核心类型

### 6.1 std.core.error

```uya
// 错误类型定义
union Error {
    None,                        // 无错误
    Message: &[i8],             // 错误消息
    Code: i32,                  // 错误码
    System: i32                 // 系统错误码（errno）
}

// 错误函数
export fn error_none() Error;
export fn error_message(msg: &const byte) Error;
export fn error_code(code: i32) Error;
export fn error_from_errno(errno: i32) Error;
export fn error_to_string(e: &Error) &[i8];
export fn error_is_none(e: &Error) bool;
```

### 6.2 std.core.option

```uya
// Option<T> - 可选值
union Option<T> {
    Some: T,
    None
}

// 方法
fn option_some<T>(value: T) Option<T>;
fn option_none<T>() Option<T>;
fn option_is_some<T>(self: &Option<T>) bool;
fn option_is_none<T>(self: &Option<T>) bool;
fn option_unwrap<T>(self: &Option<T>) !T;      // None 时返回错误
fn option_unwrap_or<T>(self: &Option<T>, default: T) T;
fn option_map<T, U>(self: &Option<T>, f: fn(T) U) Option<U>;
fn option_and_then<T, U>(self: &Option<T>, f: fn(T) Option<U>) Option<U>;
```

### 6.3 std.core.result

```uya
// Result<T, E> - 结果类型
union Result<T, E: Error> {
    Ok: T,
    Err: E
}

// 方法
fn result_ok<T, E>(value: T) Result<T, E>;
fn result_err<T, E>(err: E) Result<T, E>;
fn result_is_ok<T, E>(self: &Result<T, E>) bool;
fn result_is_err<T, E>(self: &Result<T, E>) bool;
fn result_unwrap<T, E>(self: &Result<T, E>) !T;
fn result_unwrap_err<T, E>(self: &Result<T, E>) !E;
fn result_map<T, U, E>(self: &Result<T, E>, f: fn(T) U) Result<U, E>;
fn result_map_err<T, E, F>(self: &Result<T, E>, f: fn(E) F) Result<T, F>;
fn result_and_then<T, U, E>(self: &Result<T, E>, f: fn(T) Result<U, E>) Result<U, E>;
```

### 6.4 std.core.traits

```uya
// Clone - 克隆接口
interface Clone {
    fn clone(self: &Self) Self;
}

// Eq - 相等比较
interface Eq {
    fn eq(self: &Self, other: &Self) bool;
    fn ne(self: &Self, other: &Self) bool;  // 默认实现
}

// Ord - 有序比较
interface Ord {
    fn cmp(self: &Self, other: &Self) i32;  // -1, 0, 1
    fn lt(self: &Self, other: &Self) bool;
    fn le(self: &Self, other: &Self) bool;
    fn gt(self: &Self, other: &Self) bool;
    fn ge(self: &Self, other: &Self) bool;
}

// Hash - 哈希
interface Hash {
    fn hash(self: &Self) u64;
}

// Display - 格式化显示
interface Display {
    fn fmt(self: &Self, writer: &Writer) !void;
}
```

## Sprint 7: std.io I/O 抽象

### 7.1 std.io.writer

```uya
// Writer 接口
interface Writer {
    fn write(self: &Self, data: &[u8]) !usize;
    fn write_str(self: &Self, s: &const byte) !usize;
    fn flush(self: &Self) !void;
}

// 辅助函数
export fn write_all(w: &Writer, data: &[u8]) !void;
export fn write_byte(w: &Writer, b: u8) !void;
export fn write_u8(w: &Writer, v: u8) !void;
export fn write_u16_le(w: &Writer, v: u16) !void;
export fn write_u32_le(w: &Writer, v: u32) !void;
export fn write_u64_le(w: &Writer, v: u64) !void;
```

### 7.2 std.io.reader

```uya
// Reader 接口
interface Reader {
    fn read(self: &Self, buf: &[u8]) !usize;
    fn read_exact(self: &Self, buf: &[u8]) !void;
}

// 辅助函数
export fn read_to_end(r: &Reader, buf: &Vec<u8>) !usize;
export fn read_line(r: &Reader, line: &[u8]) !usize;
export fn read_u8(r: &Reader) !u8;
export fn read_u16_le(r: &Reader) !u16;
export fn read_u32_le(r: &Reader) !u32;
```

### 7.3 std.io.file

```uya
// 文件结构体
struct File : Writer, Reader {
    fd: i32,
    owns_fd: bool,              // 是否拥有 fd（close 时需要）
    
    // 构造函数
    fn open(path: &const byte, flags: i32, mode: i32) !File;
    fn create(path: &const byte, mode: i32) !File;
    
    // Writer 接口
    fn write(self: &Self, data: &[u8]) !usize;
    fn write_str(self: &Self, s: &const byte) !usize;
    fn flush(self: &Self) !void;
    
    // Reader 接口
    fn read(self: &Self, buf: &[u8]) !usize;
    fn read_exact(self: &Self, buf: &[u8]) !void;
    
    // 其他操作
    fn seek(self: &Self, offset: i64, whence: i32) !i64;
    fn close(self: &Self) !void;
    fn drop(self: &Self);       // RAII: 自动关闭
}

// 标准流
export const stdin: File = File{ fd: 0, owns_fd: false };
export const stdout: File = File{ fd: 1, owns_fd: false };
export const stderr: File = File{ fd: 2, owns_fd: false };
```

## Sprint 8: std.string 安全字符串操作

```uya
// 基本字符串函数（无错误返回）
export fn strlen(s: &const byte) usize;
export fn strcmp(s1: &const byte, s2: &const byte) i32;
export fn strncmp(s1: &const byte, s2: &const byte, n: usize) i32;

// 安全复制（带边界检查）
export fn copy_safe(dst: &byte, dst_len: usize, src: &const byte) !void;
export fn cat_safe(dst: &byte, dst_len: usize, src: &const byte) !void;

// 解析函数（返回 !T）
export fn parse_i8(s: &const byte) !i8;
export fn parse_i16(s: &const byte) !i16;
export fn parse_i32(s: &const byte) !i32;
export fn parse_i64(s: &const byte) !i64;
export fn parse_u8(s: &const byte) !u8;
export fn parse_u16(s: &const byte) !u16;
export fn parse_u32(s: &const byte) !u32;
export fn parse_u64(s: &const byte) !u64;
export fn parse_f32(s: &const byte) !f32;
export fn parse_f64(s: &const byte) !f64;

// 字符串操作（返回 Option）
export fn find(s: &const byte, c: byte) Option<usize>;
export fn rfind(s: &const byte, c: byte) Option<usize>;
export fn split_first(s: &const byte, delim: byte) Option<(&const byte, &const byte)>;

// 大小写转换
export fn to_lower_inplace(s: &byte) void;
export fn to_upper_inplace(s: &byte) void;

// 检查函数
export fn starts_with(s: &const byte, prefix: &const byte) bool;
export fn ends_with(s: &const byte, suffix: &const byte) bool;
export fn is_whitespace(s: &const byte) bool;
export fn is_digit(s: &const byte) bool;
```

## Sprint 9: std.collections 泛型容器

### 9.1 std.collections.vec

```uya
// 动态数组
struct Vec<T> {
    data: &T,
    len: usize,
    cap: usize,
    
    // 构造函数
    fn new() Vec<T>;
    fn with_capacity(cap: usize) !Vec<T>;
    fn from_slice(slice: &[T]) !Vec<T> where T: Clone;
    
    // 访问
    fn len(self: &Self) usize;
    fn is_empty(self: &Self) bool;
    fn capacity(self: &Self) usize;
    fn get(self: &Self, i: usize) !&T;           // 边界检查
    fn get_unchecked(self: &Self, i: usize) &T;  // 无检查
    fn first(self: &Self) Option<&T>;
    fn last(self: &Self) Option<&T>;
    fn as_slice(self: &Self) &[T];
    
    // 修改
    fn push(self: &Self, value: T) !void;
    fn pop(self: &Self) Option<T>;
    fn insert(self: &Self, i: usize, value: T) !void;
    fn remove(self: &Self, i: usize) !T;
    fn clear(self: &Self) void;
    fn truncate(self: &Self, new_len: usize) void;
    fn reserve(self: &Self, additional: usize) !void;
    
    // 迭代
    fn iter(self: &Self) Iterator<T>;
    
    // RAII
    fn drop(self: &Self) void;
}
```

### 9.2 std.collections.string_buf

```uya
// 字符串缓冲区
struct StringBuf {
    buf: Vec<u8>,
    
    // 构造函数
    fn new() StringBuf;
    fn with_capacity(cap: usize) !StringBuf;
    fn from(s: &const byte) !StringBuf;
    
    // 访问
    fn len(self: &Self) usize;
    fn is_empty(self: &Self) bool;
    fn as_str(self: &Self) &[i8];
    fn as_bytes(self: &Self) &[u8];
    
    // 修改
    fn push(self: &Self, c: byte) !void;
    fn push_str(self: &Self, s: &const byte) !void;
    fn push_slice(self: &Self, s: &[u8]) !void;
    fn clear(self: &Self) void;
    fn truncate(self: &Self, new_len: usize) void;
    
    // 格式化
    fn format<T: Display>(self: &Self, value: T) !void;
    
    // RAII
    fn drop(self: &Self) void;
}
```

## Sprint 10: libc 薄封装

### 10.1 设计原则

libc 是 std 的薄封装层：

1. **保持 C 签名**：函数名、参数类型、返回值完全兼容 C99
2. **调用 std 实现**：不重复实现逻辑
3. **错误转换**：std 的 `!T` 转换为 C 的返回码/null
4. **安全增强**：添加边界检查、空指针防护

### 10.2 libc.string

```uya
use std.string;
use std.mem;

// strlen - 调用 std 实现
export extern fn strlen(s: *const byte) usize {
    return std.strlen(s as &const byte);
}

// strcmp - 调用 std 实现
export extern fn strcmp(s1: *const byte, s2: *const byte) i32 {
    return std.strcmp(s1 as &const byte, s2 as &const byte);
}

// strcpy - 安全增强
export extern fn strcpy(dst: *byte, src: *const byte) *byte {
    if dst == null || src == null { return dst; }
    const len: usize = std.strlen(src as &const byte);
    std.mem.copy(dst as &byte, src as &const byte, len + 1);
    return dst;
}

// strcat - 安全增强
export extern fn strcat(dst: *byte, src: *const byte) *byte {
    if dst == null || src == null { return dst; }
    const dst_len: usize = std.strlen(dst as &const byte);
    const src_len: usize = std.strlen(src as &const byte);
    std.mem.copy((dst as usize + dst_len) as &byte, src as &const byte, src_len + 1);
    return dst;
}
```

### 10.3 libc.stdio

```uya
use std.io;
use std.mem;

// FILE 类型定义（与 C 兼容）
struct FILE {
    fd: i32,
    flags: i32,
    buffer: &[u8],
    buf_len: usize,
}

// fopen - 调用 std.io.File.open
export extern fn fopen(path: *const byte, mode: *const byte) *FILE {
    if path == null || mode == null { return null; }
    
    const flags: i32 = parse_mode(mode as &const byte);
    const result: !std.io.File = std.io.File.open(path as &const byte, flags, 0o644);
    
    if result is error { return null; }
    
    // 分配 FILE 结构
    const f: *FILE = std.mem.alloc(@size_of(FILE)) as *FILE;
    if f == null { return null; }
    
    f.fd = result.fd;
    f.flags = flags;
    f.buffer = null;
    f.buf_len = 0;
    
    return f;
}

// fclose - 调用 std.io.File.close
export extern fn fclose(fp: *FILE) i32 {
    if fp == null { return -1; }
    
    var f: std.io.File = std.io.File{ fd: fp.fd, owns_fd: true };
    const result: !void = f.close();
    
    std.mem.free(fp as &void);
    
    if result is error { return -1; }
    return 0;
}

// fwrite - 调用 std.io.Writer.write
export extern fn fwrite(ptr: *const void, size: usize, nmemb: usize, fp: *FILE) usize {
    if ptr == null || fp == null { return 0; }
    const total: usize = size * nmemb;
    var f: std.io.File = std.io.File{ fd: fp.fd, owns_fd: false };
    const result: !usize = f.write(ptr as &[u8], total);
    if result is error { return 0; }
    return result / size;
}
```

## 迁移计划

### 阶段 1：核心类型（Sprint 6）

1. 实现 `std.core.error`
2. 实现 `std.core.option`
3. 实现 `std.core.result`
4. 实现 `std.core.traits`

### 阶段 2：I/O 抽象（Sprint 7）

1. 定义 `interface Writer`
2. 定义 `interface Reader`
3. 重构 `std.io.File` 实现 Writer/Reader

### 阶段 3：字符串操作（Sprint 8）

1. 重构 `std.string` 使用 `!T`
2. 添加安全版本函数
3. 添加解析函数

### 阶段 4：泛型容器（Sprint 9）

1. 实现 `Vec<T>`
2. 实现 `StringBuf`
3. 添加迭代器支持

### 阶段 5：libc 封装（Sprint 10）

1. 重构 `libc.string` 调用 std
2. 重构 `libc.stdio` 调用 std
3. 重构 `libc.stdlib` 调用 std

## 验证标准

每个 Sprint 完成后需验证：

1. **编译通过**：`make check` 通过
2. **测试覆盖**：新增测试用例全部通过
3. **自举验证**：编译器能使用新 std 编译自身
4. **libc 兼容**：`--outlibc` 生成的库能与 C 代码链接
