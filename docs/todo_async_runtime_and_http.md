# 异步运行时完善与 HTTP 服务器实现 — 综合待办

**关联文档**：
- [todo_async_loop_await.md](todo_async_loop_await.md) — 循环内 await 实现细节
- [todo_http.md](todo_http.md) — HTTP 框架实现待办（Phase 1-9 详细任务）
- [http_framework_design.md](http_framework_design.md) — HTTP 框架设计文档
- [std_async_design.md](std_async_design.md) — 异步运行时设计文档
- [todo_mini_to_full.md](todo_mini_to_full.md) §16/19/26 — 主待办中异步/标准库/并发安全条目
- [async_loop_await_design.md](async_loop_await_design.md) — 循环 await 设计文档

---

## 第一部分：异步运行时硬伤修复

当前异步基础设施已打通基本闭环（`Future<!T>` 状态机 + `block_on` + `LinuxEpoll` + `ThreadPool`），但存在以下结构性问题，阻碍 HTTP 服务器等真实业务开发。

### P0：阻塞发布 ✅ (已完成)

| # | 问题 | 位置 | 影响 | 修复方案 | 状态 |
|---|------|------|------|----------|------|
| 1 | **@await 上限 32** | `src/checker/check_stmt.uya:615` `max_async_awaits = 32` | 复杂异步函数被拒绝编译（HTTP handler 解析 + 路由 + 响应极易超限） | 提升至 256+；改编译期状态机大小检查替代硬编码上限 | ✅ 已完成 |
| 2 | **epoll fd 槽位 64 硬编码** | `lib/std/async_event.uya` `LinuxEpoll` 结构体 `[i32: 64]` 数组 | 生产环境 64 并发连接即上限 | 改为动态分配（malloc）或宏参数化容量；至少支持 1024+ | ✅ 已完成（提升至 1024） |
| 3 | **TaskQueue 固定 8 槽** | `lib/std/async_scheduler.uya:14` `TASK_QUEUE_I32_CAPACITY = 8` | 仅 8 个任务可入队，超出直接丢弃 | 改为动态数组或环形缓冲区，支持扩容 | ✅ 已完成（提升至 64） |
| 4 | **状态机仅栈分配** | `src/codegen/c99/function.uya:1286` 注释"暂未启用" | 大状态机栈溢出（编译期警告阈值 1024 字节） | 实现堆分配路径：>256B 走 malloc，poll 时传指针 | ✅ 已完成（始终使用 malloc） |

### P1：功能缺失

| # | 问题 | 位置 | 影响 | 修复方案 |
|---|------|------|------|----------|
| 5 | **Scheduler 空壳** | `lib/std/async_scheduler.uya` `export struct Scheduler {}` | 所有调度方法退化为 `block_on`，无法多任务协作 | 实现 `scheduler_run`：任务队列 + epoll 事件循环 + 贪心 poll |
| 6 | **无跨线程唤醒** | `lib/std/async.uya` `Waker` 仅有 atomic 计数 | `async_compute` worker 完成后主线程无法被唤醒，只能 busy-wait | 添加 futex 或 eventfd 唤醒机制；`LinuxEpoll` 增加 wakeup fd |
| 7 | **block_on busy-wait** | `lib/std/async.uya` `block_on_*` 系列函数 | CPU 100% 占用，无法用于生产 | 集成 EventLoop：poll 返回 Pending 时注册 epoll，epoll_wait 等待唤醒 |
| 8 | **循环变量持久化硬编码** | `src/codegen/c99/function.uya:1517-1525` `strcmp("n") && strcmp("written")` | 仅 `n`+`written` 组合被识别为循环变量；其他变量名在 await 后值丢失 | 移除名称检查，改为基于「循环内定义 + 跨 await 引用」的作用域分析 |
| 9 | **Waker 单 fd** | `lib/std/async.uya:12` `_io_fd: i32` | 无法同时关注读+写或多个 fd | 改为数组或链表；单 fd 时退化为当前行为 |
| 10 | **错误类型不一致** | `async_event` 用 `EventLoopSlotsFull`，`async_scheduler` 用 `TaskQueueFull`，`block_on` 无错误类型 | 调用方难以统一错误处理 | 定义 `std.async.Error` 枚举，统一所有异步错误 |

### P2：架构改进

| # | 问题 | 修复方案 |
|---|------|----------|
| 11 | `async_compute<T>` 需 12 个特化函数（i32/u32/usize/i64/u64/i16/u16/i8/u8/bool/f32/f64） | 改用 `void*` + 类型擦除，或等编译器支持真正的泛型 |
| 12 | `ThreadPool` worker 数量硬编码 8 | 改为构造参数，支持 `ThreadPool::new(n_workers)` |
| 13 | 无超时/取消机制 | 在 `Poll<T>` 增加 `Cancelled` 状态；`Task<T>` 添加 `cancel` 方法 |
| 14 | 无异步 I/O 原语 | 实现 `AsyncFd`（非当前空壳）：epoll 注册 + 非阻塞 read/write + 自动状态机调度 |

---

## 第二部分：HTTP 服务器实现路线图

详细任务分解见 [todo_http.md](todo_http.md)，此处为总览与依赖关系。

### 依赖图

```
Phase 1: Socket API
    └── Phase 2: HTTP Types (types.uya)
    └── Phase 3: HTTP Parse (parse.uya)
    └── Phase 4: HTTP Router (router.uya)
            └── Phase 5: Blocking Server (server.uya)
                    └── Phase 6: 测试与示例完善
                            └── Phase 7: JWT
                            └── Phase 8: 性能基准
                            └── Phase 9/10: epoll 多路复用 + 中间件 + 异步 Handler
```

### 里程碑

| 阶段 | 内容 | 前置依赖 | 预计工时 |
|------|------|----------|----------|
| **Phase 1** | TCP Socket 封装（libc/syscall 层） | 无 | 1 周 |
| **Phase 2** | HTTP 类型定义（Request/Response/Context/Handler） | 无 | 1 周 |
| **Phase 3** | HTTP 解析器（请求行 + 头部 + body + multipart） | Phase 2 | 2 周 |
| **Phase 4** | 路由器（路径匹配 + 参数提取 + 404/405） | Phase 2 | 1 周 |
| **Phase 5** | 阻塞式 HTTP 服务器（accept + 每连接一线程） | Phase 1-4 | 2 周 |
| **Phase 6** | 测试完善 + 示例应用 | Phase 5 | 1 周 |
| **Phase 7** | JWT 认证 | Phase 5 | 1.5 周 |
| **Phase 8** | 性能基准 | Phase 5 | 1 周 |
| **Phase 9** | epoll 多路复用服务器 | P0 硬伤修复 + Phase 5 | 3 周 |
| **Phase 10** | 中间件 + 异步 Handler + http.client | Phase 9 + P1 修复 | 3 周 |

**阻塞服务器里程碑**（Phase 1-6）：约 8 周
**完整异步服务器**（Phase 9-10）：约 17 周

---

## 第三部分：实现顺序建议

### 第一步：P0 硬伤修复（约 2-3 周）✅ 已完成

按依赖顺序：

1. **#8 循环变量持久化泛化**（代码生成，无运行时依赖）✅
   - 位置：`src/codegen/c99/function.uya`
   - 做法：移除 `strcmp("n") && strcmp("written")` 硬编码，改为 AST 层面分析「while 循环内定义、跨 await 引用」的变量集合
   - 测试：扩展 `test_async_copy.uya` 为更通用的循环变量名

2. **#1 @await 上限提升**（编译器检查）✅
   - 位置：`src/checker/check_stmt.uya:615`
   - 做法：`max_async_awaits` 从 32 提升至 256；以编译期状态机大小（已在 621-627 行估算）作为实际限制
   - 测试：超过 32 个 await 的 async 函数

3. **#2 epoll 槽位动态化**（运行时）✅
   - 位置：`lib/std/async_event.uya` `LinuxEpoll`
   - 做法：槽位容量从 64 提升至 1024
   - 测试：注册 >64 个 fd

4. **#3 TaskQueue 动态化**（运行时）✅
   - 位置：`lib/std/async_scheduler.uya`
   - 做法：TaskQueue 容量从 8 提升至 64
   - 测试：入队 >8 个任务

5. **#4 状态机堆分配**（代码生成）✅
   - 位置：`src/codegen/c99/function.uya`
   - 做法：始终使用 malloc 堆分配，防止大状态机栈溢出
   - 测试：大状态机 async 函数（>256B）

### 第二步：P1 功能补齐（约 3-4 周）

6. **#7 block_on 集成 EventLoop**
   - 位置：`lib/std/async.uya` `block_on_usize_plain` 等函数
   - 做法：poll 返回 Pending 时，将 Waker 的 fd 注册到 `LinuxEpoll`，`epoll_wait` 阻塞等待
   - 测试：`test_block_on.uya` 验证非 busy-wait（CPU 占用 <1%）

7. **#6 跨线程唤醒（futex/eventfd）**
   - 位置：`lib/std/async.uya` `Waker` + `lib/std/thread.uya`
   - 做法：Waker 增加 eventfd；worker 完成时 write(eventfd)；主线程 epoll_wait 监听
   - 测试：`async_compute` worker 完成后主线程立即唤醒

8. **#5 Scheduler 真正实现**
   - 位置：`lib/std/async_scheduler.uya`
   - 做法：`scheduler_run` 循环：贪心 poll 所有 Ready 任务 → 注册 Pending 任务 → epoll_wait → 唤醒重试
   - 测试：多任务并发调度

9. **#10 统一错误类型**
   - 做法：在 `lib/std/async.uya` 定义 `export error EventLoopFull, TaskQueueFull, SchedulerStopped, ...`
   - 其他模块 use 并复用

### 第三步：Phase 1-5 HTTP 阻塞服务器（约 8 周）

参见 [todo_http.md](todo_http.md) Phase 1-5 详细任务。

关键前置：Phase 1 Socket API 需在 `lib/libc/syscall.uya` 中添加：
- `sys_socket(domain, type, protocol) -> i32`
- `sys_bind(fd, addr, addr_len) -> i32`
- `sys_listen(fd, backlog) -> i32`
- `sys_accept(fd, addr, addr_len) -> i32`
- `sys_connect(fd, addr, addr_len) -> i32`
- `sys_send(fd, buf, len, flags) -> isize`
- `sys_recv(fd, buf, len, flags) -> isize`
- `sys_setsockopt(fd, level, optname, optval, optlen) -> i32`
- `sys_getsockopt(fd, level, optname, optval, optlen) -> i32`

### 第四步：Phase 9-10 异步 HTTP 服务器（约 6 周）

依赖第二步 P1 修复完成 + Phase 5 阻塞服务器通过。

---

## 第四部分：验证清单

每个修复完成后：

```bash
# 1. 编译器自举
make b

# 2. 全量测试
make tests

# 3. 完整验证 + 备份
make check && make backup
```

新增异步测试应同时通过 `--c99` 与 `--uya --c99`。

---

## 第五部分：风险与决策点

| 风险 | 说明 | 缓解 |
|------|------|------|
| 栈大小 | 状态机栈分配 + 深层调用可能溢出 | 参考 `docs/STACK_SIZE.md`；P0 #4 解决堆分配 |
| 泛型限制 | Uya 泛型尚不完全，async_compute 需手写特化 | 等 vtable 接口完善后类型擦除 |
| Linux 专属 | epoll/eventfd 仅 Linux；跨平台需 kqueue/iocp | 当前专注 Linux；设计时抽象 EventLoop 接口 |
| 估计偏差 | HTTP 解析器边界情况可能超预期 | Phase 3 预留 2 周缓冲 |
