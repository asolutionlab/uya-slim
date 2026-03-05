# 标准库重构待办

基于 [std_refactor_design.md](std_refactor_design.md)，执行前请阅读设计文档。开发流程遵循 [.codebuddy/rules/uya-dev-flow.mdc](../.codebuddy/rules/uya-dev-flow.mdc)（TDD、`make check`）。

**实现约定**：每项任务均需「先写测试（或注明沿用现有测试）→ 实现 → `make check`」；大函数/深嵌套按 uya-dev-flow 规则拆分（函数 ≤50 行、嵌套 ≤3 层）。

---

## 总览表

| Phase | 阶段       | 状态     | 说明 |
|-------|------------|----------|------|
| 1     | syscall 层 | 未开始   | 系统调用层，无依赖 |
| 2     | mem 层     | 未开始   | 纯内存操作层，独立基础层 |
| 3     | osal 层    | 未开始   | 操作系统抽象层，依赖 syscall |
| 4     | libc 层    | 未开始   | C 兼容层，依赖 osal + mem |
| 5     | std 层     | 未开始   | Uya 原生风格层，依赖 libc（及可选 osal） |

**依赖与顺序**：syscall 无依赖；mem 无依赖；osal 仅依赖 syscall；libc 依赖 osal + mem；std 依赖 libc（及可选 osal）。执行顺序必须 Phase 1 → 2 → 3 → 4 → 5，避免跨层依赖。

---

## Phase 1：syscall 层

- [x] 建立 `lib/syscall/`，新增 `linux.uya`（与现有 `lib/libc/syscall.uya` 对齐，无 extern "libc"）。
- [x] 编译器支持 `use syscall` → 收集 `lib/syscall/*.uya`（main.uya）；codegen 为 `lib/syscall/` 增加 `syscall_` 前缀（function.uya、expr.uya 回退）。
- [x] 为 lib/libc/ 和 lib/syscall/ 下的 export 变量添加模块前缀（排除 stderr/stdin/stdout 以保持与系统 libc 兼容）。
- [ ] 实现基础文件操作：`sys_read`、`sys_write`、`sys_open`、`sys_close`；测试先行，`make check` 通过。
- [ ] 实现内存管理：`sys_mmap`、`sys_munmap`、`sys_brk`；测试先行，`make check` 通过。
- [ ] 实现进程/线程相关：`sys_clone`、`sys_execve`、`sys_exit`、`sys_gettid`、`sys_kill`、`sys_getpid`、`sys_getppid` 等；测试先行，`make check` 通过。
- [ ] 实现时间：`sys_nanosleep`、`sys_gettimeofday`；测试先行，`make check` 通过。
- [ ] 实现设备/控制：`sys_ioctl`、`sys_fcntl`；测试先行，`make check` 通过。
- [ ] 实现文件/目录：`sys_stat`、`sys_lstat`、`sys_fstat`、`sys_access`、`sys_readlink`、`sys_unlink`、`sys_rename`、`sys_mkdir`、`sys_rmdir`、`sys_dup`、`sys_dup2`；测试先行，`make check` 通过。
- [ ] 实现用户/组：`sys_getuid`、`sys_getgid`、`sys_setuid`、`sys_setgid`、`sys_geteuid`、`sys_getegid`（按需）；测试先行，`make check` 通过。

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
