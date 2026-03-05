# 标准库重构待办

基于 [std_refactor_design.md](std_refactor_design.md)，执行前请阅读设计文档。开发流程遵循 [.codebuddy/rules/uya-dev-flow.mdc](../.codebuddy/rules/uya-dev-flow.mdc)（TDD、`make check`）。

**实现约定**：每项任务均需「先写测试（或注明沿用现有测试）→ 实现 → `make check`」；大函数/深嵌套按 uya-dev-flow 规则拆分（函数 ≤50 行、嵌套 ≤3 层）。

---

## 总览表

| Phase | 阶段       | 状态     | 说明 |
|-------|------------|----------|------|
| 1     | syscall 层 | 即将完成 | 系统调用层，待清理工作 |
| 2     | mem 层     | 未开始   | 纯内存操作层，独立基础层 |
| 3     | osal 层    | 未开始   | 操作系统抽象层，依赖 syscall |
| 4     | libc 层    | 未开始   | C 兼容层，依赖 osal + mem |
| 5     | std 层     | 未开始   | Uya 原生风格层，依赖 libc（及可选 osal） |

**依赖与顺序**：syscall 无依赖；mem 无依赖；osal 仅依赖 syscall；libc 依赖 osal + mem；std 依赖 libc（及可选 osal）。执行顺序必须 Phase 1 → 2 → 3 → 4 → 5，避免跨层依赖。

---

## extern "libc" 与函数命名规则

> **重要**：AI 必须准确理解裸名与非裸名的规则，避免生成错误的函数声明。

### 规则速查表

| 语法 | C 输出 | 用途 |
|------|--------|------|
| `fn foo(...)` | `static void uya_foo(...)` | 内部函数，带 `uya_` 前缀 |
| `export fn foo(...)` | `void module_prefix_foo(...)` | 导出函数，**带模块前缀** |
| `extern fn foo(...)` | `extern void foo(...)` | 声明外部 C 函数，**裸名** |
| `extern "libc" fn foo(...)` | `extern void foo(...)` | 声明 C 标准库函数，**裸名**，`byte`→`char` |
| `export extern fn foo(...)` | `void foo(...)` | 用 Uya 实现 C 兼容函数，**裸名** |
| `export extern "libc" fn foo(...)` | `void foo(...)` | 用 Uya 实现 C 标准库函数，**裸名**，`byte`→`char` |

### 关键区分

**1. `export fn` vs `export extern fn`**

```uya
// ❌ 错误：libc 层使用 export fn 会导致 C 名带模块前缀
// lib/libc/string.uya（模块 libc.string → 前缀 libc_string）
export fn strlen(s: *const byte) usize { ... }
// 生成：usize libc_string_strlen(*const byte s)  ← 不是标准 C 库的 strlen！

// ✅ 正确：libc 层必须使用 export extern "libc" fn
export extern "libc" fn strlen(s: *const byte) usize { ... }
// 生成：size_t strlen(const char *s)  ← 标准 C 库签名！
```

**2. `lib/syscall/` 的特殊规则**

```uya
// lib/syscall/linux.uya（模块 syscall → 前缀 syscall_）
// 注意：此层不需要 extern "libc"，因为不链接 C 标准库

// ✅ 正确：syscall 层使用普通 export fn，会自动添加 syscall_ 前缀
export fn sys_read(fd: i32, buf: &byte, count: usize) !isize { ... }
// 生成：isize syscall_sys_read(i32 fd, byte* buf, usize count)

// ✅ 正确：syscall 层也可以使用裸名（如果需要与其他代码链接）
export extern fn sys_read(fd: i32, buf: &byte, count: usize) !isize { ... }
// 生成：isize sys_read(i32 fd, byte* buf, usize count)  ← 裸名
```

**3. `byte` 类型映射**

```uya
// 在 extern "libc" 声明中，byte 自动映射为 char
extern "libc" fn strlen(s: *const byte) usize;
// C 声明：size_t strlen(const char *s);  ← byte 变成 char

// 在普通函数中，byte 是 unsigned char
export fn my_func(s: &byte) void;
// C 声明：void module_prefix_my_func(unsigned char *s);
```

### 各层推荐用法

| 层 | 推荐语法 | 原因 |
|----|----------|------|
| **syscall** | `export fn sys_xxx(...)` | 自动添加 `syscall_` 前缀，避免符号冲突 |
| **mem** | `export fn xxx(...)` | 模块前缀隔离，如 `mem_copy` |
| **osal** | `export fn os_xxx(...)` | 模块前缀隔离，如 `osal_os_open` |
| **libc** | `export extern "libc" fn xxx(...)` | **必须裸名**，保持 C ABI 兼容 |
| **std** | `export fn xxx(...)` | 模块前缀隔离，Uya 原生风格 |

### 引用说明

详见 [`docs/uya.md`](uya.md) 第 114-133 行、第 2160-2199 行。

---

## Phase 1：syscall 层

### 1.1 基础设施（已完成）

- [x] 建立 `lib/syscall/`，新增 `linux.uya`（使用 `export fn`，不使用 `extern "libc"`，因为 syscall 层不链接 C 标准库）。
- [x] 编译器支持 `use syscall` → 收集 `lib/syscall/*.uya`（main.uya）；codegen 为 `lib/syscall/` 增加 `syscall_` 前缀（function.uya、expr.uya 回退）。
- [x] 为 lib/libc/ 和 lib/syscall/ 下的 export 变量添加模块前缀（排除 stderr/stdin/stdout 以保持与系统 libc 兼容）。

### 1.2 基础文件操作

- [x] `sys_read`、`sys_write`、`sys_open`、`sys_close`（已实现，已测试）。
- [x] `sys_lseek`（已实现，已测试）。
- [x] 补充 `test "sys_read_write_file" {}` 等功能测试（`tests/test_syscall_file.uya`）。

### 1.3 内存管理

- [x] `sys_mmap`、`sys_munmap`（已实现，已测试）。
- [x] `sys_brk`（已实现，已测试）。
- [x] 补充内存管理测试（已实现 test_syscall_mem.uya）。

### 1.4 进程/线程相关

- [x] `sys_exit`、`sys_getpid`、`sys_kill`、`sys_waitpid`（已实现，已测试）。
- [x] `sys_getppid`（已实现函数体，已测试）。
- [x] `sys_clone`（已实现，已测试）。
- [x] `sys_execve`（已实现，已测试）。
- [x] `sys_gettid`（已实现，已测试）。

### 1.5 时间相关

- [x] `sys_nanosleep`（已实现，已测试）。
- [x] `sys_gettimeofday`（已实现，已测试）。
- [x] 补充时间测试。

### 1.6 设备/控制

- [x] `sys_ioctl`（已实现，已测试）。
- [x] `sys_fcntl`（已实现，已测试）。
- [x] 补充设备/控制测试。

### 1.7 文件/目录

- [x] `sys_stat`、`sys_access`、`sys_readlink`、`sys_unlink`、`sys_mkdir`、`sys_rmdir`、`sys_chdir`、`sys_getcwd`（已实现，已测试）。
- [x] `sys_lstat`、`sys_fstat`、`sys_rename`、`sys_dup`、`sys_dup2`（已实现，已测试）。
- [x] 补充文件/目录测试（已实现 test_syscall_dir.uya）。

### 1.8 用户/组

- [x] `sys_getuid`、`sys_getgid`、`sys_setuid`、`sys_setgid`、`sys_geteuid`、`sys_getegid`（已实现，已测试）。
- [x] 补充用户/组测试。

### 1.9 清理工作

- [ ] 明确 `lib/libc/syscall.uya` 的迁移/废弃计划（与 `lib/syscall/linux.uya` 存在重复）。

---

## Phase 2：mem 层

- [ ] 建立 `lib/mem/`，新增 `mem.uya`（及可选 `string.uya`）。
- [ ] 实现内存操作：`copy`、`copy_backward`、`set`、`zero`、`compare`、`memcmp`、`memset`、`memchr`；保证无系统调用依赖；测试先行，`make check` 通过。
- [ ] 实现字符串操作（纯内存）：`strlen`、`strnlen`、`strcmp`、`strncmp`、`strcpy`、`strncpy`、`strcat`、`strncat`、`strchr`、`strrchr`；无外部依赖；测试先行，`make check` 通过。
- [ ] 验证：编译通过、无循环依赖、被依赖方（如后续 libc）可引用。

---

## Phase 3：osal 层

- [ ] 建立 `lib/osal/`，新增 `osal.uya`（及按设计拆分的 `file.uya`、`process.uya`、`time.uya`、`dir.uya`、`error.uya` 等）。
- [ ] `use syscall`；定义统一错误类型（如 `OSError` union）；对外 API 使用 `!T` 风格。
- [ ] 实现文件抽象：`os_open`、`os_close`、`os_read`、`os_write`、`os_seek`、`os_stat`、`os_fstat`；测试先行，`make check` 通过。
- [ ] 实现内存管理抽象：`os_mmap`、`os_munmap`（底层调用 syscall）；测试先行，`make check` 通过。
- [ ] 实现进程/线程抽象：`os_spawn`、`os_exec`、`os_exit`、`os_getpid`、`os_gettid`、`os_kill`、`os_waitpid`；测试先行，`make check` 通过。
- [ ] 实现时间抽象：`os_sleep`、`os_gettimeofday`、`os_clock_gettime`；测试先行，`make check` 通过。
- [ ] 实现目录操作：`os_mkdir`、`os_rmdir`、`os_readdir`；测试先行，`make check` 通过。
- [ ] 验证：仅依赖 syscall，不依赖 libc/std；`make check` 通过。

### osal 跨平台实现策略

- **接口统一**：所有平台暴露同一套 osal API（`os_open`、`os_read`、`os_write`、`OSError` 等），libc/std 只依赖该统一接口。
- **实现方式**：短期仅支持 Linux，osal 仅 `use syscall`（即 `lib/syscall/linux.uya`）。跨平台扩展采用「每平台一个 syscall 实现、接口一致」；osal 保持一份实现，通过构建/编译时选择当前平台的 syscall 模块；若工具链暂不支持按平台选 syscall 模块，则采用「每平台一份 osal 实现」（如 `osal/linux.uya`、`osal/windows.uya`），对外 API 严格一致，由应用或 libc 在编译时只 `use` 其中一份。
- **原则**：平台差异收敛在 syscall 层（或 per-platform 的 osal 实现）；osal 业务逻辑中不写 `#if`/平台分支。
- **验证**：新增平台时仅需新增对应 syscall 模块（及可选的 osal 实现），不修改已有 osal 调用方；`make check` 及该平台测试通过即可。

---

## Phase 4：libc 层

- [ ] 重构 `lib/libc/` 中字符串/内存类：改为调用 `lib/mem`（如 `strlen`、`strcmp`、`strcpy`、`memcpy`、`memset` 等）；保持 C 签名与 ABI；测试先行，`make check` 通过。
- [ ] 重构 `lib/libc/` 中文件/进程类：改为调用 `lib/osal`（如 `fopen`、`fread`、`fwrite` 等封装 osal 文件抽象）；保持 C 签名；测试先行，`make check` 通过。
- [ ] pthread/time 等按设计文档规划：依赖 osal 或 syscall 的薄封装；测试先行，`make check` 通过。
- [ ] 验证：`make check` 通过；`--outlibc` 生成的库能与 C 代码链接。

---

## Phase 5：std 层

- [ ] 在现有 `lib/std/` 基础上对齐设计文档：核心类型（Option、Result、Error）、traits（Clone、Eq、Ord、Hash、Display）等；测试先行，`make check` 通过。
- [ ] I/O 抽象：`interface Writer`、`interface Reader`，`struct File : Writer, Reader`；依赖 libc 或 osal；测试先行，`make check` 通过。
- [ ] HeapAllocator：调用 `osal.os_mmap`/`osal.os_munmap` 实现；实现 `IAllocator` 或等价接口；测试先行，`make check` 通过。
- [ ] 泛型容器：Vec、StringBuf 等（按设计文档）；测试先行，`make check` 通过。
- [ ] 验证：自举与测试通过；依赖 libc（及可选 osal），不反向依赖。

---

## 与 uya-dev-flow 的对接

- 每个任务均需「先写测试（或注明沿用现有测试）→ 实现 → `make check`」。
- 函数行数 ≤50 行、嵌套深度 ≤3 层；超出则拆分或提前返回/提取函数。
- 新增或修改的测试需同时通过 `--c99` 与 `--uya --c99` 方式。
