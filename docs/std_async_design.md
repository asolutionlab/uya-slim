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

**当前实现**：`lib/std/async.uya` 提供 **`struct Waker`**（最小 `wake/reset/is_woken` 语义，并可暂存一次 `fd + interest` I/O 注册请求）、**`union Poll<T>`**（Ready/Pending）、**`interface Future<T>`**、**`struct Future<T>`**（含 `state: Poll<T>`、`fn poll(...) Poll<T>`）、**`struct Task<T> : Future<T>`**（含 `task_ready`、`poll`）。针对常见标量 **`i32` / `u32` / `usize`** 的 **`Future<!T>`** 路径，已导出 **`poll_ready_ok_*` / `future_ready_ok_*` / `task_ready_ok_*`**，便于自定义 `Future` 与测试构造 `Ready(ok(...))`。`std.async.io` 当前已收敛到 **`Future<!usize>`** 主路径：`MemAsyncWriter` / `MemAsyncReader` 直接返回 `Ready(ok(n))`，`AsyncFd` 在 `poll()` 时确保 `O_NONBLOCK`，并将 `EAGAIN` / `EWOULDBLOCK` 映射为 `Poll.Pending`；此时 future 会把读/写关注记录到 `Waker`，由 `Scheduler` 通过 `EventLoop.register()/poll()/deregister()` 驱动下一轮唤醒。`LinuxEpoll` 当前也已在 `poll()` 命中后按 fd 查找已注册 `Waker` 并调用 `wake()`。这一 readiness 路径现在也被 `lib/std/http/http1_async.uya` 复用，用于 HTTP/1.1 客户端的 nonblocking connect/read/write。`Scheduler` 现在同时提供 `scheduler_run_i32_with_event_loop`、`scheduler_run_pair_i32_with_event_loop` 与固定容量 `TaskQueue_i32` / `scheduler_run_task_queue_i32_with_event_loop`：可让多个 `Future<!i32>` 共享一次 `EventLoop.poll()` 周期完成统一注册/唤醒验证。编译器侧已补齐两处直接支撑队列的 codegen 能力：数组元素上的接口字段方法调用（如 `queue.slots[i].future.poll(...)`）可正确保留接口类型；结构体字段依赖收集也会跳过接口类型，避免误展开 `struct Future<T>` 模板。`test_async_await_parse.uya`、`test_task_std_async.uya`、`test_async_return_value.uya`、`test_async_nested.uya`、`test_std_async_waker.uya`、`test_async_io.uya`、`test_async_fd.uya`、`test_async_copy.uya`、`test_std_async_event.uya`、`test_std_async_scheduler.uya` 已通过 `--c99` 与 `--uya --c99`。**@async_fn 中可直接 `return T`**：无 `@await` 时自动包装为 `Future<T>{ state: Poll<T>.Ready(expr) }`，poll 立即返回 Ready。Checker 对单态/泛型名做基名匹配（如 `Future<T>`、`Future_i32` 可解析为接口/结构体 `Future`），方法解析失败时回退到基名查找。**已知限制**：注解类型 `Future<Future<T>>` 上调用 `.poll` 尚可能报「结构体上不存在该方法」，待修复；当前可改用单层 `Future<T>` 或由调用方先 `try` 再 poll。编译器在结构体含泛型 union 字段时会先输出该 union 的单态定义（如 `Poll_i32`、`uya_tagged_Poll_i32`），且通过 arena 持久化 tagged 名避免重定义。**无 await 且返回 `!Future<T>` 的 @async_fn**：状态机形态为 `Future<!Future<T>>`，其 `struct uya_interface_*` / `struct uya_vtable_*` 在 `src/codegen/c99/function.uya` 中按需生成（不经过 `mono_instances`），并用 `is_struct_defined` 避免重复定义。以下为**目标**目录结构，后续按阶段拆分实现。

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
├── async_channel.uya # Channel<T>, MpscChannel<T>
└── scheduler.uya   # Scheduler 事件循环调度器
```

## 1. std.async.io - 异步 I/O 抽象层

**设计目标**：提供基于 `Future<T>` + `Waker` 的非阻塞 I/O 接口，与 `std.io` 形成同步/异步对称设计。

### 与 std.io（同步）的对比

| 维度 | `std.io` | `std.async.io` |
|------|----------|----------------|
| 返回类型 | `!usize` / `!void` | `Future<!usize>`（当前最小实现） |
| 执行方式 | 同步阻塞 | 状态机 + 非阻塞 |
| 使用场景 | 普通函数 | `@async_fn` 函数 |
| I/O 后端 | 直接系统调用 | poll + waker 事件驱动 |

**注意**：
- `std.io` 的同步接口返回 `!T`，**不能**被 `@await` 调用
- 在 `@async_fn` 中调用同步 `std.io` 方法虽然语法合法，但会**阻塞当前任务**
- 异步场景应使用 `std.async.io` 中的 `AsyncWriter` / `AsyncReader`

**当前现状补充**：
- 语言层已提供 `@error_id(err)`，可读取 `@syscall` 失败路径的 errno 数值
- `AsyncFd` 已将 `EAGAIN` / `EWOULDBLOCK` 映射为 `Poll.Pending`，并通过 `Waker` 记录 `fd + interest`
- `Scheduler` 已可在 `Pending` 时读取该 I/O 请求，调用 `EventLoop.register()/poll()/deregister()` 后再重试 future
- `Scheduler` 已有单任务、双任务与固定容量任务队列入口，可让多个 future 共享一次 `EventLoop.poll()` 与唤醒周期
- `LinuxEpoll.poll()` 已能在事件命中后唤醒对应 `Waker`
- 后续主要剩余通用泛型任务队列、更多任务共享事件循环、跨线程唤醒等扩展

### 核心接口

- [ ] **AsyncWriter 接口**：统一的异步输出抽象
  ```uya
  export interface AsyncWriter {
      fn write(self: &Self, data: &[u8]) Future<!usize>;
      fn write_str(self: &Self, s: &[i8]) Future<!usize>;
      fn flush(self: &Self) Future<!usize>;
  }
  ```

- [ ] **AsyncReader 接口**：统一的异步输入抽象
  ```uya
  export interface AsyncReader {
      fn read(self: &Self, buf: &[u8]) Future<!usize>;
      fn read_exact(self: &Self, buf: &[u8]) Future<!usize>;
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
    fn write(self: &Self, data: &[u8]) Future<!usize> {
        // 内部实现：
        // 1. poll() 时确保 fd 为 O_NONBLOCK
        // 2. 尝试非阻塞写入
        // 3. 如果返回 EAGAIN，向 Waker 记录“等待可写 fd”
        // 4. Scheduler 代为 register/poll/deregister
        // 5. EventLoop 命中后 wake，再次 poll() 重试 syscall
    }
}

AsyncFd : AsyncReader {
    fn read(self: &Self, buf: &[u8]) Future<!usize> {
        // 类似 write，当前已接到 Waker + EventLoop 的最小闭环
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
  - 已可暂存单次 I/O interest（`fd + readable/writable`），供调度器读取并转交 `EventLoop`
  - `Scheduler` 可利用该状态在 `poll()` 内同步唤醒时直接重试，避免额外一次 `EventLoop.poll()`
  - 已有双任务与固定容量任务队列共享 `EventLoop` 的最小验证入口；通用泛型任务队列、跨线程唤醒与更完整的唤醒安全性仍待后续实现
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
      fn register(self: &Self, fd: i32, interest: EventKind, waker: &Waker) !i32;
      fn deregister(self: &Self, fd: i32) !i32;
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
  - `register()` / `deregister()` 当前成功返回 `0`；`poll()` 会在事件命中后按 fd 查找并 `wake()` 已注册 `Waker`
  - 端到端测试 `test_std_async_event.uya`、`test_epoll_syscall.uya` 已通过 `--c99` 与 `--uya --c99`（codegen 已修复）

- [ ] **macOS 实现**（`std/async/event/macos.uya`）：
  - 基于 `kqueue` / `kevent` 系统调用

- [ ] **Windows 实现**（`std/async/event/windows.uya`）：
  - 基于 IOCP（I/O Completion Ports）

**涉及**：新建 `std/async/event/` 目录

## 4. std.async.channel - 异步通道

- [x] **Channel\<T\>**：
  - 单槽异步通道，用于异步任务间通信
  - 当前提供 `send/recv -> Future<_>` 最小接口
  - 仅保留泛型入口（不再维护 `Channel_i32` / `Channel_usize` 兼容别名）

- [x] **MpscChannel\<T\>**：
  - 多生产者、单消费者、运行时容量版通道
  - 当前以原子锁 + 环形队列实现，容量由调用方传入
  - 已覆盖单槽 Pending 与多槽 FIFO/环回；Send/Sync 约束推导仍待后续实现

**涉及**：`lib/std/async_channel.uya`、`lib/std/collections/ring_queue.uya`

## 5. std.async.scheduler - 调度器

- [~] **Scheduler**：
  - 异步运行时调度器
  - 基于事件循环实现
  - 零堆分配，栈分配状态机
  - 当前已覆盖单任务、双任务与固定容量任务队列共享 `EventLoop` 的最小运行入口
  - 后续管理所有 `Task<T>` 的生命周期
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
| 7 | **多平台事件后端**（macOS kqueue, Windows IOCP） | ⭐⭐ | 阶段 3 + `std.cfg` |

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
