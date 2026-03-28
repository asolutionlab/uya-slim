# macOS 迁移 Phase 3 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 3：`@syscall`、`syscall`、`osal` 与 runtime**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做

适用范围：

- `src/codegen/c99/main.uya`
- `lib/libc/syscall.uya`
- `lib/syscall/`
- `lib/osal/osal.uya`
- `lib/std/runtime/entry/entry.uya`
- `lib/std/runtime/runtime.uya`

本阶段核心目标：

- 将 `@syscall` 从“仅 Linux x86-64”提升为“具备 Darwin 分支的代码生成框架”
- 为 `lib/libc/syscall.uya` 与 `lib/syscall/` 建立 Darwin 落点
- 让 `osal` 不再默认等价于 Linux syscall 语义
- 去掉 `std.runtime.entry` 与 `std.runtime.runtime` 中硬编码的 Linux syscall 号
- 为 Phase 4 的 hosted 自举和主测试基线提供可在 macOS 真机验证的基础系统能力

---

## 本阶段完成定义

满足以下条件即可视为 Phase 3 完成：

- [ ] `@syscall` 的代码生成不再在非 Linux x86-64 上直接报错
- [ ] `lib/libc/syscall.uya` 拥有明确的 Darwin 路线
- [ ] `lib/syscall/` 拥有明确的 Darwin 路线
- [ ] `osal` 的基础常量、结构体和封装不再默认等价于 Linux
- [ ] `std.runtime.entry` 不再硬编码 Linux `SYS_setrlimit`
- [ ] `std.runtime.runtime` 不再硬编码 Linux `SYS_exit=60`
- [ ] macOS 上普通 hosted 程序可用 `std.runtime` 启动并退出
- [ ] Linux 行为不回归

---

## 明确不在本阶段做的事

- [ ] 不迁移 `pthread`
- [ ] 不实现 Darwin `--nostdlib`
- [ ] 不实现 `kqueue`
- [ ] 不恢复 async 测试
- [ ] 不把 `osal` 扩展成完整 Darwin 生产级实现
- [ ] 不处理 `epoll` / `pipe2` / futex 的兼容替代

若某个改动需要触碰这些内容，说明已经越过 Phase 3 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 3 应该做到哪里

在 Phase 3 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：重构 `@syscall` 代码生成框架
- [ ] Commit 2：为 `lib/libc/syscall.uya` 与 `lib/syscall/` 预留 Darwin 后端结构
- [ ] Commit 3：收敛 `osal` / `std.runtime` 的 Linux-only 硬编码

做到这里，Linux 的主要职责已经完成：接口、模块、helper、文件布局和运行时抽象已经成型。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时要真正验证 Darwin 的 ABI 和 syscall 语义：

- [ ] Darwin `x86_64` 的 `@syscall` 调用约定
- [ ] Darwin `arm64` 的 `@syscall` 调用约定
- [ ] Darwin 的 syscall 号与错误返回语义
- [ ] Darwin 上 `setrlimit` / `exit` / `readlink` / `getcwd` / `fcntl` 等基础能力

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin `@syscall` helper
- [ ] Darwin syscall 号表
- [ ] Darwin `lib/syscall` / `libc.syscall` 分支
- [ ] Darwin `osal` 常量与结构体
- [ ] Darwin `std.runtime.entry` / `std.runtime.runtime` 行为

这些内容只能算“代码已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 做实现收口和验收

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase1.md](todo_macos_phase1.md) 与 [todo_macos_phase2.md](todo_macos_phase2.md) 的核心目标
- [ ] Linux 上执行：
  - [ ] `make check`
  - [ ] `make uya-hosted`
- [ ] 记录当前强 Linux 绑定点：
  - [ ] `src/codegen/c99/main.uya` 中 `#error "@syscall currently only supports Linux x86-64"`
  - [ ] `lib/libc/syscall.uya` 中 Linux x86-64 syscall 号
  - [ ] `lib/syscall/linux.uya` 是 `lib/syscall/` 目录中唯一实现
  - [ ] `lib/osal/osal.uya` 使用 Linux 常量和值
  - [ ] `lib/std/runtime/entry/entry.uya` 直接使用 `SYS_setrlimit=160`
  - [ ] `lib/std/runtime/runtime.uya` 直接使用 `@syscall(60, code)`

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 重构 `@syscall` 代码生成结构 | `src/codegen/c99/main.uya` | Linux codegen 不回归 |
| 2 | 建立 Darwin syscall 层落点 | `lib/libc/syscall.uya`、`lib/syscall/` | Linux 编译不回归 |
| 3 | 收敛 `osal` / `std.runtime` 的 Linux-only 假设 | `lib/osal/osal.uya`、`lib/std/runtime/*` | Linux 普通程序不回归 |
| 4 | Darwin `x86_64` 路线落位 | `src/codegen/c99/main.uya`、`lib/*syscall*`、`runtime` | macOS x86_64 smoke |
| 5 | Darwin `arm64` 与 osal/runtime 收口 | 同上 | macOS arm64 smoke |

---

## Commit 1：重构 `@syscall` 代码生成结构

**建议提交名**：`codegen: refactor syscall helper generation for multi-platform`

### 目标

- 先把 `@syscall` 代码生成从“硬编码 Linux x86-64 内联汇编块”改成可扩展结构
- 在不改变 Linux 现有行为的前提下，为 Darwin 分支预留插入点

### 修改文件

- [ ] [../src/codegen/c99/main.uya](../src/codegen/c99/main.uya)

### 任务清单

- [ ] 拆出“生成 syscall helper”的逻辑块
- [ ] 明确平台与架构分支层次：
  - [ ] Linux x86-64
  - [ ] Darwin x86-64
  - [ ] Darwin arm64
- [ ] 保持现有 Linux x86-64 helper 名称与调用方式不变
- [ ] 将当前 `#error` 改为更适合后续扩展的结构

### 验证

- [ ] Linux：编译器仍可生成 C 代码
- [ ] Linux：现有 `@syscall` 相关测试不回归

### 完成标准

- [ ] `@syscall` 生成逻辑具备多平台结构
- [ ] Linux 路径未被破坏

---

## Commit 2：建立 Darwin syscall 层落点

**建议提交名**：`syscall: add darwin backend scaffolding`

### 目标

- 为 `lib/libc/syscall.uya` 和 `lib/syscall/` 都建立 Darwin 扩展落点
- 不要求此提交就把 Darwin 语义完全跑通

### 修改文件

- [ ] [../lib/libc/syscall.uya](../lib/libc/syscall.uya)
- [ ] [../lib/syscall/linux.uya](../lib/syscall/linux.uya)
- [ ] 新增 Darwin 对应文件

### 任务清单

- [ ] 明确双层职责：
  - [ ] `lib/libc/syscall.uya`：面向 libc/测试兼容层
  - [ ] `lib/syscall/`：面向 osal 层
- [ ] 新增 Darwin 对应实现文件或入口文件
- [ ] 建立平台选择机制，避免 `osal` 未来仍强绑 `linux.uya`
- [ ] 保留 Linux 文件与现有接口稳定

### 验证

- [ ] Linux：编译通过
- [ ] Linux：`use syscall` 现有调用不回归

### 完成标准

- [ ] Darwin 后端有明确文件落点
- [ ] 双层 syscall 结构不再只有 Linux 唯一路径

---

## Commit 3：收敛 `osal` 与 `std.runtime` 的 Linux-only 假设

**建议提交名**：`runtime: remove linux-only assumptions from osal and std.runtime`

### 目标

- 把 `osal` 与 runtime 中写死的 Linux 假设先收敛成可替换的抽象
- 在不要求 Darwin 语义已经正确的前提下，把硬编码从主逻辑里拿出来

### 修改文件

- [ ] [../lib/osal/osal.uya](../lib/osal/osal.uya)
- [ ] [../lib/std/runtime/entry/entry.uya](../lib/std/runtime/entry/entry.uya)
- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)

### 任务清单

- [ ] 收敛 `osal` 中的 Linux 常量与结构体假设
- [ ] 标记需要 Darwin 校准的项目：
  - [ ] `O_CREAT`
  - [ ] `O_TRUNC`
  - [ ] `O_APPEND`
  - [ ] `RLIMIT_STACK`
  - [ ] `os_readlink`
  - [ ] `os_getdents64` 或替代路径
- [ ] 收敛 `std.runtime.entry` 中 `SYS_setrlimit=160` 假设
- [ ] 收敛 `std.runtime.runtime` 中 `@syscall(60, code)` 假设

### 验证

- [ ] Linux：普通 hosted 程序仍可启动
- [ ] Linux：普通 hosted 程序仍可退出
- [ ] Linux：`osal` 基础能力不回归

### 完成标准

- [ ] `osal` / runtime 中的 Linux-only 假设被集中管理
- [ ] Darwin 分支具备真实插入点

---

## Commit 4：Darwin `x86_64` 路线落位

**建议提交名**：`darwin: enable x86_64 syscall and runtime path`

### 目标

- 在 macOS x86_64 上跑通最小系统能力
- 让 hosted 程序至少能够启动、执行基础系统调用并退出

### 修改文件

- [ ] [../src/codegen/c99/main.uya](../src/codegen/c99/main.uya)
- [ ] Darwin syscall 文件
- [ ] [../lib/osal/osal.uya](../lib/osal/osal.uya)
- [ ] [../lib/std/runtime/entry/entry.uya](../lib/std/runtime/entry/entry.uya)
- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)

### 任务清单

- [ ] 落地 Darwin x86_64 `@syscall` helper
- [ ] 落地最小 Darwin x86_64 syscall 号集合
- [ ] 验证 runtime 启动、参数保存、退出路径
- [ ] 验证最小 `osal` 能力：
  - [ ] 文件/目录基础能力
  - [ ] 资源限制基础能力
  - [ ] 时间基础能力

### 验证

- [ ] macOS x86_64：最小 hosted 程序编译成功
- [ ] macOS x86_64：最小 hosted 程序运行成功
- [ ] macOS x86_64：最小 `std.runtime.entry` 路径可用

### 完成标准

- [ ] Darwin x86_64 hosted 程序具备最小系统能力

---

## Commit 5：Darwin `arm64` 与 osal/runtime 收口

**建议提交名**：`darwin: enable arm64 syscall and finish runtime smoke`

### 目标

- 在 macOS arm64 上完成最小系统能力验证
- 让 Phase 3 达到“可交给 Phase 4 hosted 自举”的状态

### 修改文件

- [ ] [../src/codegen/c99/main.uya](../src/codegen/c99/main.uya)
- [ ] Darwin syscall 文件
- [ ] [../lib/osal/osal.uya](../lib/osal/osal.uya)
- [ ] [../lib/std/runtime/entry/entry.uya](../lib/std/runtime/entry/entry.uya)
- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)

### 任务清单

- [ ] 落地 Darwin arm64 `@syscall` helper
- [ ] 落地 Darwin arm64 最小 syscall 号集合
- [ ] 验证 arm64 上 runtime 启动与退出
- [ ] 验证 arm64 上 `osal` 最小 smoke

### 验证

- [ ] macOS arm64：最小 hosted 程序编译成功
- [ ] macOS arm64：最小 hosted 程序运行成功
- [ ] macOS arm64：最小 `osal` smoke 成功

### 完成标准

- [ ] Darwin arm64 hosted 程序具备最小系统能力
- [ ] Phase 3 可交付给 Phase 4

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] 选择 1 个最小程序验证启动与退出

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] macOS x86_64：最小 hosted 程序启动与退出
- [ ] macOS arm64：最小 hosted 程序启动与退出
- [ ] `std.runtime.entry` 可保存参数
- [ ] `std.runtime.runtime` 的退出路径可工作

---

## 阶段结束后应立即进入的下一步

Phase 3 完成后，必须立刻进入以下主线：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 4：hosted 自举与主测试基线
2. 若 hosted 基线稳定，再进入：
   - [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 5：`pthread`
   - [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 6：`--nostdlib`
   - [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 7：`std.async` / `kqueue`

不建议在 Phase 3 尚未完成前提前实现 `pthread`、`--nostdlib` 或 `async`，否则很容易把 syscall/runtime 的底层问题和高层功能问题混在一起。

