# 标准库重构设计文档 v0.7.1

## 概述

本设计文档描述 Uya 标准库的重构计划，核心目标是：

1. **分层架构清晰**：std → libc → osal → syscall
2. **零依赖设计**：每层只依赖下一层，无循环依赖
3. **syscall 裸层**：直接封装 Linux 系统调用
4. **osal 抽象层**：操作系统功能抽象，统一接口
5. **libc C 兼容层**：薄封装，保持 C99 ABI 兼容
6. **std Uya 风格层**：使用 `!T`, `interface`, 泛型, `union`

## 架构设计

```
                    ┌─────────────────┐
                    │      std        │  Uya 原生风格 (!T, interface, 泛型)
                    │   标准库顶层    │
                    └────────┬────────┘
                             │ use
                    ┌────────▼────────┐
                    │     libc        │  C 兼容层（薄封装，保持 C 签名）
                    └────────┬────────┘
                             │ use
                    ┌────────▼────────┐
                    │      osal       │  操作系统抽象层（统一接口）
                    └────────┬────────┘
                             │ use
                    ┌────────▼────────┐
                    │    syscall      │  系统调用层（直接封装 Linux syscall）
                    └─────────────────┘
                             ▲
                             │ use (mem 不在主依赖链，是独立基础层)
                    ┌────────┴────────┐
                    │      mem        │  纯内存操作（无系统调用依赖）
                    └─────────────────┘
```

## 分层职责

### 1. syscall - 系统调用层（最底层）

**职责**：直接封装 Linux 系统调用，提供最原始的系统能力

**特点**：
- 无任何依赖
- 命名与 Linux syscall 一致（如 `sys_read`, `sys_write`）
- 返回原始错误码（需要上层处理）

```uya
// lib/syscall/linux.uya

// 纯系统调用，无依赖
export fn sys_read(fd: i32, buf: &byte, count: usize) i32;
export fn sys_write(fd: i32, buf: &const byte, count: usize) i32;
export fn sys_open(path: &const byte, flags: i32, mode: u32) i32;
export fn sys_close(fd: i32) i32;
export fn sys_mmap(addr: &void, len: usize, prot: i32, flags: i32, fd: i32, offset: i64) &void;
export fn sys_munmap(addr: &void, len: usize) i32;
export fn sys_brk(addr: i32) i32;
export fn sys_clone(flags: usize, stack: &void) i32;
export fn sys_execve(path: &const byte, argv: &(&const byte), envp: &(&const byte)) i32;
export fn sys_exit(code: i32) void;
export fn sys_gettid() i32;
export fn sys_kill(pid: i32, sig: i32) i32;
export fn sys_nanosleep(req: &TimeSpec, rem: &TimeSpec) i32;
export fn sys_gettimeofday(tv: &TimeVal, tz: &void) i32;
export fn sys_ioctl(fd: i32, request: usize, arg: usize) i32;
export fn sys_fcntl(fd: i32, cmd: i32, arg: usize) i32;
export fn sys_stat(path: &const byte, statbuf: &Stat) i32;
export fn sys_lstat(path: &const byte, statbuf: &Stat) i32;
export fn sys_fstat(fd: i32, statbuf: &Stat) i32;
export fn sys_access(path: &const byte, mode: i32) i32;
export fn sys_readlink(path: &const byte, buf: &byte, bufsiz: usize) i32;
export fn sys_unlink(path: &const byte) i32;
export fn sys_rename(oldpath: &const byte, newpath: &const byte) i32;
export fn sys_mkdir(path: &const byte, mode: u32) i32;
export fn sys_rmdir(path: &const byte) i32;
export fn sys_dup(fd: i32) i32;
export fn sys_dup2(oldfd: i32, newfd: i32) i32;
export fn sys_getpid() i32;
export fn sys_getppid() i32;
export fn sys_getuid() u32;
export fn sys_getgid() u32;
export fn sys_setuid(uid: u32) i32;
export fn sys_setgid(gid: u32) i32;
export fn sys_geteuid() u32;
export fn sys_getegid() u32;
```

### 2. mem - 纯内存操作层（独立基础层）

**职责**：提供纯内存操作，无任何系统调用依赖

**特点**：
- 无依赖，独立于主依赖链
- 所有函数都是纯内存操作
- 可被任何层使用

```uya
// lib/mem/mem.uya

// 内存操作
export fn copy(dst: &byte, src: &const byte, n: usize) void;
export fn copy_backward(dst: &byte, src: &const byte, n: usize) void;
export fn set(s: &byte, c: u8, n: usize) void;
export fn zero(s: &byte, n: usize) void;
export fn compare(s1: &const byte, s2: &const byte, n: usize) i32;

// 字符串操作（纯内存）
export fn strlen(s: &const byte) usize;
export fn strnlen(s: &const byte, maxlen: usize) usize;
export fn strcmp(s1: &const byte, s2: &const byte) i32;
export fn strncmp(s1: &const byte, s2: &const byte, n: usize) i32;
export fn strcpy(dst: &byte, src: &const byte) &byte;
export fn strncpy(dst: &byte, src: &const byte, n: usize) &byte;
export fn strcat(dst: &byte, src: &const byte) &byte;
export fn strncat(dst: &byte, src: &const byte, n: usize) &byte;
export fn memchr(s: &const byte, c: u8, n: &byte) &byte;
export fn strchr(s: &const byte, c: u8) &byte;
export fn strrchr(s: &const byte, c: u8) &byte;

// 字节操作
export fn memcmp(s1: &const byte, s2: &const byte, n: usize) i32;
export fn memset(s: &byte, c: u8, n: usize) &byte;
```

### 3. osal - 操作系统抽象层

**职责**：在 syscall 之上提供统一的操作系统抽象，屏蔽系统调用细节差异

**特点**：
- 依赖 syscall
- 提供统一的错误处理（使用 !T）
- 跨平台抽象接口
- 不处理纯内存操作（由 mem 层负责）

```uya
// lib/osal/osal.uya
use syscall;

// 错误类型定义
union OSError {
    None,
    NotFound,
    PermissionDenied,
    AlreadyExists,
    InvalidInput,
    IoError,
    OutOfMemory,
    NotSupported,
    TimedOut,
    Interrupted,
    Code: i32              // 原始系统错误码
}

// 文件相关
struct File {
    fd: i32,
    owns_fd: bool
}

export fn os_open(path: &const byte, flags: OSFlags, mode: u32) !File;
export fn os_close(f: &File) !void;
export fn os_read(f: &File, buf: &byte, count: usize) !usize;
export fn os_write(f: &File, buf: &const byte, count: usize) !usize;
export fn os_seek(f: &File, offset: i64, whence: i32) !i64;
export fn os_stat(path: &const byte) !OSStat;
export fn os_fstat(f: &File) !OSStat;

// 内存管理（底层使用 mmap）
export fn os_mmap(addr: &void, size: usize, prot: OSProt, flags: OSMapFlags, fd: i32, offset: i64) !&void;
export fn os_munmap(addr: &void, size: usize) !void;

// 进程/线程
export fn os_spawn(path: &const byte, args: &[&const byte], env: &[&const byte]) !i32;
export fn os_exec(path: &const byte, args: &[&const byte], env: &[&const byte]) !void;
export fn os_exit(code: i32) void;
export fn os_getpid() i32;
export fn os_gettid() i32;
export fn os_kill(pid: i32, sig: i32) !void;
export fn os_waitpid(pid: i32) !i32;

// 时间
export fn os_sleep(duration: Duration) !void;
export fn os_gettimeofday() Duration;
export fn os_clock_gettime(clock: ClockId) !Duration;

// 目录操作
export fn os_mkdir(path: &const byte, mode: u32) !void;
export fn os_rmdir(path: &const byte) !void;
export fn os_readdir(path: &const byte) !Vec<DirEntry>;

// 错误转换
fn errno_to_oserror(errno: i32) OSError;
```

### 4. libc - C 兼容层

**职责**：在 osal + mem 之上提供 C 兼容接口，保持 C99 ABI 兼容

**特点**：
- 依赖 osal 和 mem
- 保持 C 函数签名
- 错误转换为 C 风格（返回 -1/null）
- 字符串/内存操作调用 mem，文件/进程操作调用 osal

```uya
// lib/libc/string.uya
use osal;
use mem;

// C 签名，内部调用 mem 实现
export extern fn strlen(s: *const byte) usize {
    return mem.strlen(s as &const byte);
}

export extern fn strcmp(s1: *const byte, s2: *const byte) i32 {
    return mem.strcmp(s1 as &const byte, s2 as &const byte);
}

export extern fn strncmp(s1: *const byte, s2: *const byte, n: usize) i32 {
    return mem.strncmp(s1 as &const byte, s2 as &const byte, n);
}

export extern fn strcpy(dst: *byte, src: *const byte) *byte {
    if dst == null || src == null { return dst; }
    return mem.strcpy(dst as &byte, src as &const byte) as *byte;
}

export extern fn memcpy(dst: *void, src: *const void, n: usize) *void {
    if dst == null || src == null { return dst; }
    mem.copy(dst as &byte, src as &const byte, n);
    return dst;
}

export extern fn memset(s: *void, c: i32, n: usize) *void {
    if s == null { return s; }
    mem.set(s as &byte, c as u8, n);
    return s;
}
```

### 5. std - Uya 原生风格标准库（最顶层）

**职责**：在 libc + osal 之上提供 Uya 现代特性（!T, interface, 泛型）

**特点**：
- 依赖 libc 和 osal
- 使用 Uya 高级特性
- 类型安全、错误处理现代化

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

## 目录结构

```
lib/
├── syscall/                     # 系统调用层（无依赖）
│   └── linux.uya               # Linux syscall 封装
│
├── mem/                         # 纯内存操作层（独立基础层）
│   ├── mem.uya                 # copy, set, cmp
│   └── string.uya              # strlen, strcmp, strcpy...
│
├── osal/                        # 操作系统抽象层（依赖 syscall）
│   ├── osal.uya                # 核心抽象
│   ├── file.uya                # 文件抽象
│   ├── process.uya             # 进程/线程抽象
│   ├── time.uya                # 时间抽象
│   ├── dir.uya                 # 目录操作抽象
│   └── error.uya               # 错误类型
│
├── libc/                        # C 兼容层（依赖 osal + mem）
│   ├── string.uya              # strlen, strcmp, strcpy...
│   ├── stdio.uya               # printf, fopen, fclose...
│   ├── stdlib.uya              # malloc, free, atoi...
│   ├── unistd.uya              # read, write, close...
│   ├── mem.uya                # memcpy, memset...
│   ├── pthread.uya             # pthread_* 系列
│   ├── time.uya                # time, clock...
│   └── sys.uya                 # sys/* 头文件
│
└── std/                         # Uya 原生风格层（依赖 libc + osal）
    ├── core/                    # 核心类型
    │   ├── error.uya           # 错误类型
    │   ├── option.uya          # Option<T>
    │   ├── result.uya          # Result<T, E>
    │   └── traits.uya          # Clone, Eq, Ord, Hash, Display
    │
    ├── io/                      # I/O 抽象
    │   ├── writer.uya          # interface Writer
    │   ├── reader.uya          # interface Reader
    │   └── file.uya            # struct File : Writer, Reader
    │
    ├── string/                  # 字符串操作
    │   └── string.uya          # 安全字符串函数
    │
    ├── mem/                     # 内存操作
    │   ├── allocator.uya       # IAllocator 接口
    │   ├── heap.uya            # HeapAllocator（调用 osal.mmap）
    │   ├── arena.uya           # ArenaAllocator
    │   └── fixed_buf.uya       # FixedBufferAllocator
    │
    ├── collections/             # 泛型容器
    │   ├── vec.uya             # Vec<T>
    │   └── string_buf.uya      # StringBuf
    │
    ├── fmt/                     # 格式化
    │   └── fmt.uya             # format<T: Display>
    │
    └── runtime/                 # 运行时
        └── runtime.uya          # panic, entry
```

## 依赖关系详解

### syscall → osal

osal 使用 syscall 实现底层功能：

```uya
// lib/osal/file.uya
use syscall;

export fn os_open(path: &const byte, flags: OSFlags, mode: u32) !File {
    const fd: i32 = syscall.sys_open(path, flags, mode);
    if fd < 0 {
        return OSError.Code(errno);
    }
    return File{ fd: fd, owns_fd: true };
}

export fn os_read(f: &File, buf: &byte, count: usize) !usize {
    const n: i32 = syscall.sys_read(f.fd, buf, count);
    if n < 0 {
        return OSError.Code(errno);
    }
    return n as usize;
}
```

### osal → std.mem.HeapAllocator

std 层的 HeapAllocator 调用 osal 的 mmap：

```uya
// lib/std/mem/heap.uya
use osal;

/// 全局堆分配器 - 基于 mmap/munmap 系统调用
struct HeapAllocator : IAllocator {
    fn alloc(self: &Self, size: usize) !&void {
        const ptr: !&void = osal.os_mmap(
            null,                           // addr: 让内核选择
            size + @size_of(usize),         // 额外存储大小
            OSProt.READ | OSProt.WRITE,
            OSMapFlags.PRIVATE | OSMapFlags.ANONYMOUS,
            -1,                             // fd
            0                               // offset
        );
        if ptr is error { return AllocError.OutOfMemory; }
        
        const header: &usize = ptr as &usize;
        *header = size + @size_of(usize);
        return (ptr as &usize + 1) as &void;
    }
    
    fn free(self: &Self, ptr: &void) void {
        const header: &usize = (ptr as &usize - 1) as &usize;
        const actual_size: usize = *header;
        osal.os_munmap(header as &void, actual_size);
    }
}

const heap_allocator: HeapAllocator = HeapAllocator{};

export fn alloc(size: usize) !&void { return heap_allocator.alloc(size); }
export fn free(ptr: &void) void { heap_allocator.free(ptr); }
```

### mem → libc

libc 是 mem 的薄封装（C 兼容）：

```uya
// lib/libc/string.uya
use mem;

export extern fn strlen(s: *const byte) usize {
    if s == null { return 0; }
    return mem.strlen(s);
}

export extern fn strcmp(s1: *const byte, s2: *const byte) i32 {
    if s1 == null || s2 == null { return 0; }
    return mem.strcmp(s1, s2);
}
```

### osal + mem → libc

libc 根据功能调用不同底层实现：

```uya
// lib/libc/stdio.uya
use osal;
use mem;

export extern fn fopen(path: *const byte, mode: *const byte) *FILE {
    if path == null || mode == null { return null; }
    
    const flags: i32 = parse_mode(mode as &const byte);
    const result: !osal.File = osal.os_open(path as &const byte, flags, 0o644);
    
    if result is error { return null; }
    
    // 使用 osal 分配 FILE 结构
    const f: *FILE = osal.os_mmap(null, @size_of(FILE), ...) as *FILE;
    if f == null { return null; }
    
    f.fd = result.fd;
    f.flags = flags;
    f.buffer = null;
    f.buf_len = 0;
    
    return f;
}

export extern fn memcpy(dst: *void, src: *const void, n: usize) *void {
    if dst == null || src == null { return dst; }
    mem.copy(dst as &byte, src as &const byte, n);
    return dst;
}
```

### libc + osal → std

std 使用 libc 和 osal 作为基础：

```uya
// lib/std/io/file.uya
use libc;
use osal;

struct File : Writer, Reader {
    fd: i32,
    owns_fd: bool,
    
    fn open(path: &const byte, flags: i32, mode: i32) !File {
        const fp: *libc.FILE = libc.fopen(path, mode_to_cstring(flags));
        if fp == null {
            return Error.FromErrno;
        }
        return File{ fd: fp.fd, owns_fd: true };
    }
    
    fn read(self: &Self, buf: &[u8]) !usize {
        const n: usize = libc.fread(buf, 1, buf.len, self.fp);
        if n == 0 && buf.len > 0 {
            return Error.FromErrno;
        }
        return n;
    }
}
```

## 设计原则

### 1. 单一职责

每层只负责一件事：
- **syscall**：系统调用映射
- **mem**：纯内存操作（独立基础层）
- **osal**：操作系统抽象
- **libc**：C 兼容
- **std**：Uya 现代化

### 2. 依赖单向

依赖方向永远是向下的：
```
std → libc → osal → syscall
         ↘
          mem  (独立基础层，不在主依赖链)
```

禁止反向依赖或跨层依赖。

### 3. 错误处理分层

- **syscall**：返回原始错误码
- **osal**：转换为 OSError（!T）
- **libc**：转换为 C 风格（返回 -1/null）
- **std**：保持 !T 或转换为 Result

### 4. 零重复实现

不重复实现功能，上层调用下层：

```uya
// ❌ 错误：libc 直接实现字符串操作
fn strlen(s: &const byte) usize {
    var i: usize = 0;
    while s[i] != 0 { i += 1; }
    return i;
}

// ✅ 正确：libc 调用 mem
fn strlen(s: &const byte) usize {
    return mem.strlen(s);
}
```

### 5. mem 层独立

mem 层是独立的基础层，任何层都可以使用它：
- libc 使用 mem 处理字符串/内存
- std 可以直接使用 mem
- osal 不使用 mem（因为需要系统调用）

## 实现优先级

### Phase 1: syscall 层
1. 实现基本文件操作：read, write, open, close
2. 实现内存管理：mmap, munmap, brk
3. 实现进程管理：fork, exec, exit, wait

### Phase 2: mem 层
1. 实现 copy, set, compare 等内存操作
2. 实现 strlen, strcmp, strcpy 等字符串操作
3. 确保无任何外部依赖

### Phase 3: osal 层
1. 封装 syscall 为统一接口
2. 实现错误转换
3. 添加跨平台抽象（未来支持其他 OS）

### Phase 4: libc 层
1. 重构现有 libc 调用 mem（字符串/内存）和 osal（文件/进程）
2. 添加 pthread 支持
3. 添加 time/clock 支持

### Phase 5: std 层
1. 实现核心类型（Option, Result, Error）
2. 实现 I/O 抽象（Writer, Reader）
3. 实现 HeapAllocator 调用 osal.mmap
4. 实现泛型容器（Vec, StringBuf）

## 验证标准

每个阶段完成后需验证：

1. **编译通过**：`make check` 通过
2. **测试覆盖**：新增测试用例全部通过
3. **自举验证**：编译器能使用新标准库编译自身
4. **依赖检查**：无循环依赖，每层只依赖下一层
5. **libc 兼容**：`--outlibc` 生成的库能与 C 代码链接
