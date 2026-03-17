# std.async 异步标准库设计文档

**相关文档**：
- [std/libc 标准库设计](std_c_design.md) — 同步 I/O（`std.io`）、C 兼容层（`lib/libc`）
- [语言规范 第 18 章](uya.md#18-异步编程) — 异步编程语言核心（`@async_fn`、`@await`、`interface Future<T>`、`union Poll<T>`）

## 概述

`std.async` 是 Uya 异步编程的标准库模块，基于语言核心类型（`interface Future<T>`、`union Poll<T>`、`struct Waker`）实现高级异步抽象。

**设计原则**：
- 基于语言核心的 `@async_fn` / `@await` / `Future<T>` / `Poll<T>`
- 零成本抽象：状态机栈分配，无运行时堆分配
- 显式控制：所有挂起必须 `@await`，无隐式行为
- 与 `std.io` 形成同步/异步对称设计

## 架构概览

**当前实现**：`lib/std/async.uya` 提供 **`struct Waker`**（最小 `wake/reset/is_woken` 状态语义）、**`union Poll<T>`**（Ready/Pending）、**`interface Future<T>`**、**`struct Future<T>`**（含 `state: Poll<T>`、`fn poll(...) Poll<T>`）、**`struct Task<T> : Future<T>`**（含 `task_ready`、`poll`）。`test_async_await_parse.uya`、`test_task_std_async.uya`、`test_async_return_value.uya`、`test_async_nested.uya`、`test_std_async_waker.uya` 已通过 `--c99` 与 `--uya --c99`。**@async_fn 中可直接 `return T`**：无 `@await` 时自动包装为 `Future<T>{ state: Poll<T>.Ready(expr) }`，poll 立即返回 Ready。Checker 对单态/泛型名做基名匹配（如 `Future<T>`、`Future_i32` 可解析为接口/结构体 `Future`），方法解析失败时回退到基名查找。**已知限制**：注解类型 `Future<Future<T>>` 上调用 `.poll` 尚可能报「结构体上不存在该方法」，待修复；当前可改用单层 `Future<T>` 或由调用方先 `try` 再 poll。编译器在结构体含泛型 union 字段时会先输出该 union 的单态定义（如 `Poll_i32`、`uya_tagged_Poll_i32`），且通过 arena 持久化 tagged 名避免重定义。**无 await 且返回 `!Future<T>` 的 @async_fn**：状态机形态为 `Future<!Future<T>>`，其 `struct uya_interface_*` / `struct uya_vtable_*` 在 `src/codegen/c99/function.uya` 中按需生成（不经过 `mono_instances`），并用 `is_struct_defined` 避免重复定义。以下为**目标**目录结构，后续按阶段拆分实现。

```
std/async/
├── io/             # 异步 I/O 抽象
│   ├── writer.uya  # AsyncWriter 接口
│   ├── reader.uya  # AsyncReader 接口
│   └── async_fd.uya # 基于文件描述符的异步 I/O 实现
├── task.uya        # Task<T>, Waker 完整实现
├── event/          # 平台事件循环后端
│   ├── common.uya  # 统一事件接口
│   ├── linux.uya   # epoll / io_uring
│   ├── macos.uya   # kqueue
│   └── windows.uya # IOCP
├── channel.uya     # Channel<T>, MpscChannel<T>
└── scheduler.uya   # Scheduler 事件循环调度器
```

## 1. std.async.io - 异步 I/O 抽象层

**设计目标**：提供基于 `Future<T>` + `Waker` 的非阻塞 I/O 接口，与 `std.io` 形成同步/异步对称设计。

### 与 std.io（同步）的对比

| 维度 | `std.io` | `std.async.io` |
|------|----------|----------------|
| 返回类型 | `!usize` / `!void` | `!Future<usize>` / `!Future<void>` |
| 执行方式 | 同步阻塞 | 状态机 + 非阻塞 |
| 使用场景 | 普通函数 | `@async_fn` 函数 |
| I/O 后端 | 直接系统调用 | poll + waker 事件驱动 |

**注意**：
- `std.io` 的同步接口返回 `!T`，**不能**被 `@await` 调用
- 在 `@async_fn` 中调用同步 `std.io` 方法虽然语法合法，但会**阻塞当前任务**
- 异步场景应使用 `std.async.io` 中的 `AsyncWriter` / `AsyncReader`

### 核心接口

- [ ] **AsyncWriter 接口**：统一的异步输出抽象
  ```uya
  export interface AsyncWriter {
      fn write(self: &Self, data: &[u8]) !Future<usize>;
      fn write_str(self: &Self, s: &[i8]) !Future<usize>;
      fn flush(self: &Self) !Future<void>;
  }
  ```

- [ ] **AsyncReader 接口**：统一的异步输入抽象
  ```uya
  export interface AsyncReader {
      fn read(self: &Self, buf: &[u8]) !Future<usize>;
      fn read_exact(self: &Self, buf: &[u8]) !Future<void>;
  }
  ```

- [ ] **辅助函数**：
  - `async_print_to(writer: &AsyncWriter, s: &[i8]) !Future<void>`
  - `async_println_to(writer: &AsyncWriter, s: &[i8]) !Future<void>`

**涉及**：新建 `std/async/io/writer.uya`、`std/async/io/reader.uya`

### 实现原理

异步 I/O 基于 `poll()` + `Waker` 模式，底层使用平台事件机制：

```uya
// std/async/io/async_fd.uya
struct AsyncFd {
    fd: i32,
    waker: Option<&Waker>
}

AsyncFd : AsyncWriter {
    fn write(self: &Self, data: &[u8]) !Future<usize> {
        // 内部实现：
        // 1. 尝试非阻塞写入
        // 2. 如果返回 EAGAIN，注册到事件循环，返回 union Poll<usize> { Pending: void }
        // 3. 事件就绪时，waker.wake() 唤醒任务
        // 4. 重新 poll 时完成写入，返回 union Poll<usize> { Ready: n }
    }
}

AsyncFd : AsyncReader {
    fn read(self: &Self, buf: &[u8]) !Future<usize> {
        // 类似 write，基于非阻塞读取 + 事件通知
    }
}
```

**涉及**：新建 `std/async/io/async_fd.uya`

### 使用示例

```uya
use std.async.io;

@async_fn
fn fetch_and_write(reader: &AsyncReader, writer: &AsyncWriter) !Future<void> {
    var buf: [u8: 4096] = [];
    const n = try @await reader.read(&buf);
    try @await writer.write(&buf[0:n]);
}
```

## 2. std.async.task - 异步任务

### Task\<T\>

- 异步任务的包装类型
- 实现 `Future<T>` 接口（即实现 `poll(self: &Self, waker: &Waker) union Poll<T>`）
- 提供任务生命周期管理

### Waker

- **定义**：唤醒器，用于在异步操作就绪时通知异步运行时重新调度任务
- **作用**：
  - 当异步操作（如 I/O、定时器等）就绪时，通过 `waker.wake()` 通知运行时
  - 运行时收到通知后，会重新调用 `poll()` 方法检查任务状态
  - 实现高效的异步任务调度，避免忙等待（busy-waiting）
- **当前阶段**：
  - 已落地最小状态语义：`wake()`、`reset()`、`is_woken()`
  - `Scheduler` 可利用该状态在 `poll()` 内同步唤醒时直接重试，避免额外一次 `EventLoop.poll()`
  - 事件循环注册、任务队列、跨线程唤醒仍待后续实现
- **编译期验证**：
  - 编译期验证唤醒安全性（Waker 使用）
  - 确保 Waker 不会被错误使用或泄漏

**涉及**：新建 `std/async/task.uya`

## 3. std.async.event - 平台事件后端

异步 I/O 需要平台特定的事件通知机制：

| 平台 | 事件机制 | 模块 |
|------|---------|------|
| Linux | `epoll` / `io_uring` | `std/async/event/linux.uya` |
| macOS | `kqueue` | `std/async/event/macos.uya` |
| Windows | `IOCP` | `std/async/event/windows.uya` |

- [x] **统一事件接口**（当前实现于 `lib/std/async_event.uya`，模块路径 `use std.async_event`）：
  ```uya
  export interface EventLoop {
      fn register(self: &Self, fd: i32, interest: EventKind, waker: &Waker) !void;
      fn deregister(self: &Self, fd: i32) !void;
      fn poll(self: &Self, timeout_ms: i32) !i32;
  }

  export union EventKind {
      Readable: void,
      Writable: void,
      ReadWrite: void
  }
  ```

- [x] **Linux 实现**（同上文件，`struct LinuxEpoll : EventLoop`）：
  - 基于 `libc.syscall` 的 `sys_epoll_create1` / `sys_epoll_ctl` / `sys_epoll_wait`（底层为 `@syscall`）
  - epoll 常量（含 `EPOLLET`）与 `EpollEvent` 已加入 `lib/libc/syscall.uya` 与 `lib/syscall/linux.uya`
  - 端到端测试 `test_std_async_event.uya`、`test_epoll_syscall.uya` 已通过 `--c99` 与 `--uya --c99`（codegen 已修复）

- [ ] **macOS 实现**（`std/async/event/macos.uya`）：
  - 基于 `kqueue` / `kevent` 系统调用

- [ ] **Windows 实现**（`std/async/event/windows.uya`）：
  - 基于 IOCP（I/O Completion Ports）

**涉及**：新建 `std/async/event/` 目录

## 4. std.async.channel - 异步通道

- [ ] **Channel\<T\>**：
  - 异步通道，用于异步任务间通信
  - 基于 `atomic T` 和 `union` 实现
  - 零运行时锁，编译期验证并发安全

- [ ] **MpscChannel\<T\>**：
  - 多生产者单消费者通道
  - 基于原子操作实现
  - 编译期验证 Send/Sync 约束

**涉及**：新建 `std/async/channel.uya`

## 5. std.async.scheduler - 调度器

- [ ] **Scheduler**：
  - 异步运行时调度器
  - 基于事件循环实现
  - 零堆分配，栈分配状态机
  - 管理所有 `Task<T>` 的生命周期
  - 集成 `EventLoop` 处理 I/O 事件

**涉及**：新建 `std/async/scheduler.uya`

## 6. 实现优先级

| 阶段 | 内容 | 优先级 | 依赖 |
|------|------|--------|------|
| 1 | **语言核心**（`@async_fn`, `@await`, `interface Future<T>`, `union Poll<T>`） | ⭐⭐⭐⭐⭐ | 编译器 |
| 2 | **std.async.task**（`Task<T>`, `Waker`） | ⭐⭐⭐⭐ | 阶段 1 |
| 3 | **std.async.event**（`EventLoop` + Linux epoll） | ⭐⭐⭐⭐ | 阶段 1 + `@syscall` |
| 4 | **std.async.io**（`AsyncWriter`, `AsyncReader`, `AsyncFd`） | ⭐⭐⭐⭐ | 阶段 2 + 3 |
| 5 | **std.async.scheduler**（`Scheduler`） | ⭐⭐⭐ | 阶段 2 + 3 |
| 6 | **std.async.channel**（`Channel<T>`, `MpscChannel<T>`） | ⭐⭐⭐ | 阶段 2 |
| 7 | **多平台事件后端**（macOS kqueue, Windows IOCP） | ⭐⭐ | 阶段 3 + `std.target` |

**第一个里程碑**（最小可用）：
完成阶段 1-4，可以在 Linux 上使用异步 I/O。

**第二个里程碑**（完整运行时）：
完成阶段 1-6，具备完整的异步运行时支持（调度器 + 通道）。

**第三个里程碑**（跨平台）：
完成阶段 1-7，支持 Linux / macOS / Windows 异步编程。

---

## 文档评审要点（供维护参考）

- **与 uya.md 一致**：语言核心类型采用规范中的精确写法——`interface Future<T>`、`union Poll<T>`、`struct Waker`；阶段 1 与 uya.md 第 18.1/18.3 节对齐。
- **取消与显式控制**：uya.md 要求“取消必须显式检查 `is_cancelled()`”；本设计在概述中体现了“显式控制”，若后续增加任务取消 API，需与 18 章保持一致。
- **辅助函数归属**：`async_print_to` / `async_println_to` 未指定所在文件，实现时可放在 `std/async/io/writer.uya` 或单独工具模块。
- **Option 依赖**：`AsyncFd` 示例使用 `Option<&Waker>`，依赖 `std.core.option`（见 [std_c_design](std_c_design.md)）；实现时需确保 use 或本模块提供等价类型。
