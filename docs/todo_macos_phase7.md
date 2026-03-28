# macOS 迁移 Phase 7 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 7：`std.async` 与 `kqueue`**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做
- `std.async` / `async_event` 在迁移时应如何先去 Linux 绑定、再接入 Darwin `kqueue`

适用范围：

- `lib/std/async_event.uya`
- `lib/std/async.uya`
- `lib/std/async_scheduler.uya`
- `lib/libc/syscall.uya`
- `lib/syscall/`
- `tests/test_async_fd.uya`
- `tests/test_std_async_event.uya`
- `tests/test_std_async_scheduler.uya`
- `tests/test_epoll_syscall.uya`
- `docs/std_async_design.md`

本阶段核心目标：

- 把 `EventLoop` 公共接口从 Linux `epoll` 实现中拆开
- 保留 Linux `epoll` 路径，同时为 macOS 接入 `kqueue` / `kevent`
- 让 `AsyncFd` 不再写死 Linux errno、flag 和 `pipe2` 假设
- 恢复 macOS hosted 路径下的 async 基础测试

---

## 默认路线决策

### 推荐默认方案

**推荐先把 Phase 7 定义为“恢复最小 async I/O 闭环”**：

- [ ] 对外尽量保持 `use std.async_event`、`EventLoop`、`EventKind` 这层公共接口不变
- [ ] 内部先拆分“公共接口层”和“Linux / Darwin 后端层”
- [ ] Darwin 第一阶段只追求 `kqueue` / `kevent` 最小可用，不同时追求更大范围的 async 运行时重构
- [ ] 测试先恢复 `EventLoop`、`AsyncFd`、`Scheduler + EventLoop` 的最小闭环
- [ ] 不把 Linux `epoll` 的专有能力直接当成跨平台语义

### 推荐的测试策略

**推荐把测试拆成三层**：

- [ ] 接口级测试：只验证 `EventLoop` / `AsyncFd` / `Scheduler` 语义，不绑定 `epoll`
- [ ] Linux 专属测试：保留 `epoll` syscall 和 `LinuxEpoll` 细节验证
- [ ] Darwin 专属测试：新增 `kqueue` 最小 smoke 和 async 闭环测试

理由：

- [ ] 当前 `std.async_scheduler` 已主要依赖 `EventLoop` 接口，而不是 `LinuxEpoll`
- [ ] 当前真正强 Linux 绑定主要集中在 `async_event` 实现、`AsyncFd` 常量与测试
- [ ] 先分层后 bring-up，最能避免“Darwin 代码只是在 Linux 上看起来合理”

### 长期可选方案

**长期可选：把事件后端进一步整理成独立模块布局**

- [ ] 后续可再把 `std.async.event` 收敛成 `common/linux/macos/windows` 结构
- [ ] 该目标不应阻塞当前 macOS `kqueue` 恢复

---

## 本阶段完成定义

满足以下条件即可视为 Phase 7 完成：

- [ ] `EventLoop` 公共接口与 Linux `epoll` 后端已分层
- [ ] Linux `epoll` 路径不回归
- [ ] macOS 上存在可用的 `kqueue` / `kevent` 事件循环后端
- [ ] `AsyncFd` 不再写死 Linux `EAGAIN` / `EWOULDBLOCK` / `O_NONBLOCK`
- [ ] `test_std_async_scheduler.uya` 这类接口级测试保持跨平台可运行
- [ ] macOS 上 `test_std_async_event.uya` / `test_async_fd.uya` 形成最小可用基线
- [ ] Linux 专属 `epoll` 测试与跨平台 async 测试已经分层

---

## 明确不在本阶段做的事

- [ ] 不扩展 `io_uring`
- [ ] 不新增 Windows `IOCP`
- [ ] 不处理 async 跨线程唤醒
- [ ] 不把 `std.async` 一次性重构成全新目录体系
- [ ] 不要求本阶段立即把 macOS async 纳入默认 `make check`

若某个改动依赖这些内容，说明已经越过 Phase 7 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 7 应该做到哪里

在 Phase 7 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：定义 async / `kqueue` 的目标边界和测试分层
- [ ] Commit 2：拆分 `EventLoop` 公共接口与 Linux `epoll` 后端
- [ ] Commit 3：收敛 `AsyncFd` 与测试中的 Linux-only errno / flag / `pipe2` 假设

做到这里，Linux 的主要职责已经完成：接口边界、后端结构和测试基线已经具备。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时要真正验证 Darwin 的 `kqueue`、`kevent` 与非阻塞 I/O 语义：

- [ ] Darwin `kqueue` / `kevent` 后端
- [ ] Darwin 的 `fcntl` / `O_NONBLOCK` / would-block errno 行为
- [ ] Darwin 下的管道创建与事件通知路径
- [ ] `AsyncFd` 在 macOS 上的 Pending -> wake -> Ready 闭环

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin `kqueue` / `kevent` 实现
- [ ] Darwin 非阻塞读写与 errno 映射
- [ ] Darwin async smoke 通过结论
- [ ] macOS 上 `Scheduler + EventLoop` 闭环通过结论

这些内容只能算“代码已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 做实现收口和验收

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase3.md](todo_macos_phase3.md) 的 `syscall/osal/runtime` 基线
- [ ] 先完成 [todo_macos_phase4.md](todo_macos_phase4.md) 的 hosted 自举与主测试基线
- [ ] Linux 上执行：
  - [ ] `make check`
- [ ] 记录当前 async 的强 Linux 绑定点：
  - [ ] `lib/std/async_event.uya` 仍把 `EventLoop` 与 `LinuxEpoll` 放在同一个实现文件
  - [ ] `lib/std/async.uya` 写死 `ASYNC_ERR_EAGAIN = 11`
  - [ ] `lib/std/async.uya` 写死 `ASYNC_ERR_EWOULDBLOCK = 11`
  - [ ] `lib/std/async.uya` 直接依赖 Linux 的 `O_NONBLOCK`
  - [ ] `tests/test_async_fd.uya` 写死 `SYS_write = 1`、`SYS_close = 3`、`SYS_pipe2 = 293`
  - [ ] `tests/test_async_fd.uya` 写死 `TEST_O_NONBLOCK = 0x800`
  - [ ] `tests/test_std_async_event.uya` 直接实例化 `LinuxEpoll`
  - [ ] `tests/test_epoll_syscall.uya` 只验证 Linux `epoll`，不属于跨平台 async 基线
  - [ ] `tests/test_std_async_scheduler.uya` 已主要依赖 `EventLoop` 接口，是跨平台回归重点

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 定义 async / `kqueue` 目标边界与测试分层 | 文档、测试分组说明 | 范围清晰，不误把 `epoll` 语义当跨平台语义 |
| 2 | 拆分 `EventLoop` 公共接口与 Linux `epoll` 后端 | `lib/std/async_event.uya`、测试 | Linux `epoll` 不回归 |
| 3 | 收敛 `AsyncFd` 与测试中的 Linux-only 假设 | `lib/std/async.uya`、async 测试 | Linux async 闭环不回归 |
| 4 | Darwin `kqueue` 最小 bring-up | `async_event`、`libc/syscall`、测试 | macOS `EventLoop` 最小 smoke |
| 5 | 恢复 macOS async 基线 | `async.uya`、scheduler、测试 | macOS `AsyncFd` 与 scheduler 闭环 |

---

## Commit 1：定义 async / `kqueue` 目标边界与测试分层

**建议提交名**：`async: define darwin kqueue baseline`

### 目标

- 明确 Phase 7 的验收边界
- 明确哪些测试是跨平台接口测试，哪些测试保留为 Linux 专属

### 修改文件

- [ ] [../docs/std_async_design.md](../docs/std_async_design.md)
- [ ] 相关 TODO 文档

### 任务清单

- [ ] 明确 Phase 7 第一阶段只追求：
  - [ ] `EventLoop.register/poll/deregister`
  - [ ] `AsyncFd` 的读写 Pending / Ready 闭环
  - [ ] `Scheduler + EventLoop` 的最小联动
- [ ] 明确以下测试层次：
  - [ ] 接口级 async 测试
  - [ ] Linux `epoll` 专属测试
  - [ ] Darwin `kqueue` 专属测试
- [ ] 明确公共使用面优先保持：
  - [ ] `use std.async_event`
  - [ ] `EventLoop`
  - [ ] `EventKind`

### 验证

- [ ] 文档表述与主迁移策略一致

### 完成标准

- [ ] async / `kqueue` 的目标与测试边界清晰，不再混杂

---

## Commit 2：拆分 `EventLoop` 公共接口与 Linux `epoll` 后端

**建议提交名**：`async_event: split common api and linux backend`

### 目标

- 把 `EventLoop` / `EventKind` 的公共层与 `LinuxEpoll` 的 Linux 细节拆开
- 为 Darwin 后端预留独立入口

### 修改文件

- [ ] [../lib/std/async_event.uya](../lib/std/async_event.uya)
- [ ] [../tests/test_std_async_event.uya](../tests/test_std_async_event.uya)
- [ ] [../tests/test_epoll_syscall.uya](../tests/test_epoll_syscall.uya)

### 任务清单

- [ ] 保留 `EventLoop`、`EventKind` 的稳定公共表面
- [ ] 把 `event_kind_to_epoll()`、`LinuxEpoll` slot 管理等逻辑明确标成 Linux 后端实现
- [ ] 为 Darwin 后端预留独立创建路径或平台选择入口
- [ ] 把 `test_std_async_event.uya` 中“接口语义验证”和“Linux 具体后端验证”拆开
- [ ] 保留 `test_epoll_syscall.uya` 作为 Linux 专属 smoke

### 验证

- [ ] Linux：`LinuxEpoll` 路径不回归
- [ ] Linux：通用 `EventLoop` 接口测试仍可通过

### 完成标准

- [ ] `async_event` 不再默认把 Linux `epoll` 细节等同于公共接口

---

## Commit 3：收敛 `AsyncFd` 与测试中的 Linux-only 假设

**建议提交名**：`async: remove linux-only fd assumptions`

### 目标

- 把 `AsyncFd` 和 async 相关测试中的 Linux errno / flag / `pipe2` 绑定点清出来
- 为 Darwin 非阻塞 I/O 路径准备统一语义

### 修改文件

- [ ] [../lib/std/async.uya](../lib/std/async.uya)
- [ ] [../lib/std/async_scheduler.uya](../lib/std/async_scheduler.uya)
- [ ] [../tests/test_async_fd.uya](../tests/test_async_fd.uya)
- [ ] [../tests/test_std_async_scheduler.uya](../tests/test_std_async_scheduler.uya)
- [ ] 必要时修改 [../lib/libc/syscall.uya](../lib/libc/syscall.uya)

### 任务清单

- [ ] 去掉 `AsyncFd` 内部写死的 `EAGAIN` / `EWOULDBLOCK` 数值
- [ ] 去掉 `AsyncFd` 内部写死的 Linux `O_NONBLOCK` 假设
- [ ] 明确 `would_block` 与 `set_nonblock` 的统一封装位置
- [ ] 为测试引入“非阻塞 pipe 创建 helper”：
  - [ ] Linux 可继续走 `pipe2`
  - [ ] Darwin 可退化为 `pipe + fcntl`
- [ ] 把 `test_async_fd.uya` 中直接写死的 syscall 编号改成可平台化调用
- [ ] 保证 `test_std_async_scheduler.uya` 继续保持接口级、跨平台定位

### 验证

- [ ] Linux：`test_async_fd` 不回归
- [ ] Linux：`test_std_async_scheduler` 不回归

### 完成标准

- [ ] `AsyncFd` 与 async 基础测试不再写死 Linux-only 常量和系统调用编号

---

## Commit 4：Darwin `kqueue` 最小 bring-up

**建议提交名**：`darwin: bring up minimal kqueue event loop`

### 目标

- 在 macOS 上落地最小 `kqueue` / `kevent` 事件循环
- 先恢复 `EventLoop` 级别的 smoke

### 修改文件

- [ ] [../lib/std/async_event.uya](../lib/std/async_event.uya)
- [ ] [../lib/libc/syscall.uya](../lib/libc/syscall.uya)
- [ ] [../lib/syscall/](../lib/syscall/)
- [ ] [../tests/test_std_async_event.uya](../tests/test_std_async_event.uya)

### 任务清单

- [ ] 若 Phase 3 未提供，补齐 Darwin `kqueue` / `kevent` 所需 syscall / wrapper
- [ ] 落地 Darwin `EventLoop` 后端：
  - [ ] 创建 `kqueue`
  - [ ] 注册可读 / 可写 interest
  - [ ] `poll()` 命中后唤醒 `Waker`
  - [ ] 取消注册或清理资源
- [ ] 让 `test_std_async_event.uya` 在 macOS 上转为验证 Darwin 后端最小闭环

### 验证

- [ ] macOS：`EventLoop` 最小 smoke 通过
- [ ] macOS：`Waker` 可被 `kqueue` 命中后唤醒

### 完成标准

- [ ] Darwin `kqueue` 事件循环最小可用

---

## Commit 5：恢复 macOS async 基线

**建议提交名**：`darwin: restore async fd baseline`

### 目标

- 在 macOS 上恢复 `AsyncFd` 和 `Scheduler + EventLoop` 的最小闭环
- 把 Linux 专属测试与跨平台 async 基线真正分开

### 修改文件

- [ ] [../lib/std/async.uya](../lib/std/async.uya)
- [ ] [../lib/std/async_scheduler.uya](../lib/std/async_scheduler.uya)
- [ ] [../tests/test_async_fd.uya](../tests/test_async_fd.uya)
- [ ] [../tests/test_std_async_scheduler.uya](../tests/test_std_async_scheduler.uya)
- [ ] 必要时更新 [../docs/std_async_design.md](../docs/std_async_design.md)

### 任务清单

- [ ] 在 macOS 上跑通 `AsyncFd.read()` 的 Pending -> Ready 路径
- [ ] 在 macOS 上跑通 `Scheduler + EventLoop` 驱动重试路径
- [ ] 校准 Darwin 下：
  - [ ] 非阻塞读写返回值
  - [ ] would-block errno
  - [ ] 管道创建与关闭路径
- [ ] 明确哪些 async 测试进入 macOS 第一版基线
- [ ] 保留 Linux `epoll` syscall smoke 为 Linux-only，不混入 Darwin async 验收

### 验证

- [ ] macOS：`test_async_fd` 最小路径通过
- [ ] macOS：`test_std_async_scheduler` 保持通过
- [ ] Linux：现有 async 路径不回归

### 完成标准

- [ ] macOS hosted 路径下的 async 基础能力恢复
- [ ] Phase 7 进入“可继续扩 async 特性而不再卡死在 Linux `epoll` 假设”状态

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make check`
- [ ] async 相关测试不回归
- [ ] Linux `epoll` 专属测试不回归

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] macOS：`EventLoop` 最小 smoke 通过
- [ ] macOS：`AsyncFd` 读路径 Pending -> Ready 通过
- [ ] macOS：`Scheduler + EventLoop` 最小联动通过

---

## 阶段结束后应立即进入的下一步

Phase 7 完成后，后续主线应继续：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 8：跨平台验证与文档收口

若 macOS async 只先恢复到 `EventLoop + AsyncFd + Scheduler` 最小闭环，也属于可接受结果；不应因为尚未扩展更多事件类型或更复杂 async 运行时能力而阻塞主线收口。

