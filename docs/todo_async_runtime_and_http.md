# 异步运行时完善与 HTTP 服务器实现 — 综合待办

**最后更新**：2026-03-25 — HTTP Phase 5：`IncompleteRequest` + `find_crlf_or_incomplete` / 体未收齐时流式续读；`http_conn_read_parse`、`http_connbuf_shift`、`HTTP_CONN_READ_CAP` 与多 `recv` 的 `http_recv_parse_request`；测试 `http_keepalive_pipeline_two_requests`、`parse_post_body_incomplete`。此前同日 — ThreadPool `THREAD_POOL_MAX_WORKERS` / `THREAD_POOL_MAX_PENDING` 提升至 32；此前 2026-03-24 — Phase 4 `lib/std/http/router.uya` 已落地：`router_find_route` 返回命中下标 / `-1`（404）/ `-2`（405）、`path_matches_pattern` / `router_apply_path_params`、`MAX_ROUTES` 与 `RouterFull`；测试 `tests/test_http_router.uya`。此前：2026-03-22 — `f32`/`f64` 已并入 `AsyncComputeFuture<T>`；C99 泛型方法内 `thread_type_is_*(T)` 折叠；前导 `uya_thread_call_f32`/`f64` 以 **u32/u64 位模式** 与槽位对接，内部用 **union** 转 `float`/`double`，并以 **`float(*)(float)` / `double(*)(double)`** 间接调用（**不可**伪装成 `uint32_t(*)(uint32_t)` 等整型 ABI，否则 `async_compute` 浮点用例会错）。

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

| # | 问题 | 修复方案 | 状态 |
|---|------|----------|------|
| 11 | `async_compute<T>` 曾需 12 套重复 `Future` 实现 | 改用 `void*` + 类型擦除，或编译器泛型 + 单一 `AsyncComputeFuture<T>` | **已完成 API 收敛**：`AsyncComputeFuture<T>` 覆盖 **含 f32/f64** 的全部载荷；**仅**导出 **`async_compute<T>`**（已删 12 个 **`async_compute_*`**）；typedef 别名仍可用。 |
| 12 | `ThreadPool` worker / pending 曾硬编码 8 | `thread_pool_new(n)` 已存在；**已**将 `THREAD_POOL_MAX_WORKERS` / `THREAD_POOL_MAX_PENDING` 与数组维度提升至 **32**，边界比较改用常量 | **部分完成**（仍固定上限数组，非动态扩容） |
| 13 | 无超时/取消机制 | 在 `Poll<T>` 增加 `Cancelled` 状态；`Task<T>` 添加 `cancel` 方法 | 待办 |
| 14 | 无异步 I/O 原语 | 实现 `AsyncFd`（非当前空壳）：epoll 注册 + 非阻塞 read/write + 自动状态机调度 | 待办（`std.async.io` 已有最小路径，见 `todo_mini_to_full`） |

### P1.5：编译器 / C99（与 `Future<!T>`、`std.thread` typedef 相关）✅ 近期已闭环

以下项已在 `src/codegen/c99/`（`structs.uya`、`stmt.uya`、`expr.uya`、`main.uya` 等）与 `lib/std/thread.uya` 落地，`test_std_thread.uya`、`test_async_compute_types.uya` 与全量 `--uya --c99` 通过：

- 泛型 `AsyncComputeFuture<T>` **不**再按「非泛型 struct」生成占位 interface vtable；`Future<!T>` 单态与 `Poll<!T>` 的 `err_*` 命名一致。
- **接口实参装箱**：实参变量 C 类型为 **typedef**（如 `AsyncComputeI32Future`）时，经 `find_type_alias_from_program` → `get_mono_struct_name` 再生成 `struct uya_interface_Future_err_*` 装箱。
- **成员方法调用**：`f.poll(&w)` 在接收者类型无 `struct ` 前缀时，从类型串解析标识符并走别名解析，生成 `uya_AsyncComputeFuture_*_poll`（修复误生成 `unknown(...)`）。
- **`ok<bool>` / `ok<f32>` / `ok<f64>` 单态**：`finish_from_raw_poll` 按 `T` 分发时由 `thread_ok_bool` / `thread_ok_f32` / `thread_ok_f64` 内显式 `ok<...>` 锚定；codegen 保留 `mark_ok_mono_reachable_for_async_compute_futures`。
- **泛型方法 + `thread_type_is_*(T)`**：`gen_call_expr` 在 `struct_type_args` 上下文中将调用折叠为字面量 `0`/`1`（勿从方法体抽泛型顶层 helper，否则 C 可达性不生成）。
- **宿主线程浮点调用**：`src/codegen/c99/main.uya` 注入的 `uya_thread_call_f32`/`f64` 必须与真实 **`float`/`double` 调用约定**一致；槽位仍为整型位模式仅作存储与传递。

**后续清理（非阻塞）**：✅ 已抽取 typedef 解析助手；✅ 已移除 `ok_bool_force` 等冗余；✅ 已移除 12 个 **`async_compute_*`** 导出；**`async_compute<T>`** C99 单态走 **`std_thread_async_compute_future_new_<T>`** + 装箱（**勿**仅靠宏展开体：`thread_type_is_*` 在 C 端不折叠会落回错误分支）。

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

6. **#7 block_on 集成 EventLoop** ✅
   - 位置：`lib/std/async_scheduler.uya` `block_on_with_event_loop` 系列函数
   - 做法：poll 返回 Pending 时，将 Waker 的 fd 注册到 `LinuxEpoll`，`epoll_wait` 阻塞等待
   - 测试：`test_std_async_scheduler.uya` 验证 EventLoop 集成

7. **#6 跨线程唤醒（futex/eventfd）** ✅
   - 位置：`lib/std/async.uya` `Waker`
   - 做法：Waker 增加 `_event_fd` 字段和 `event_fd()` getter（eventfd fd 由 EventLoop 设置）
   - 完整 eventfd 集成需线程池改造（TODO）
   - 测试：现有测试通过

8. **#5 Scheduler 真正实现** ✅
   - 位置：`lib/std/async_scheduler.uya`
   - 做法：`scheduler_run_task_queue_i32_with_event_loop` 实现贪心 poll：Ready 任务直接完成 → Pending 任务注册 epoll → epoll_wait → 唤醒重试
   - 测试：`test_std_async_scheduler.uya` 多任务并发调度测试通过

9. **#10 统一错误类型** ✅
   - 位置：`lib/std/async.uya`
   - 做法：定义 `export error EventLoopSlotsFull; export error TaskQueueFull; export error SchedulerStopped; export error FutureNotReady;`
   - 其他模块可 use 并复用
   - 测试：现有测试通过

### 第三步：Phase 1-5 HTTP 阻塞服务器（约 8 周）

参见 [todo_http.md](todo_http.md) Phase 1-5 详细任务。

**Phase 1：TCP 基础设施** ✅
- Socket API 系统调用（socket/bind/listen/accept/connect/send/recv/shutdown/setsockopt/getsockopt）
- Socket 常量（AF_INET/SOCK_STREAM/IPPROTO_TCP 等）
- 测试：`test_tcp_basic.uya` 通过

**Phase 2：http.types** ✅
- 创建 `lib/std/http/` 目录和 `types.uya`
- 错误类型、HTTP 方法枚举、状态码枚举、服务器模式枚举
- 请求/响应/连接/Context 结构体
- Handler/Middleware 接口
- 测试：`test_http_types.uya` 通过

**Phase 3：http.parse** ✅
- `parse.uya`：请求行、头部、body、Keep-alive `ParseResult`、multipart 等
- 测试：`test_http_parse.uya` 等

**Phase 4：http.router** ✅
- `router.uya`：`Router` / `RouteEntry`、`router_add`、`router_find_route`（命中下标；`-1` 未匹配；`-2` 路径有模式但方法不允许）、`path_matches_pattern`、`router_apply_path_params`；`types.uya` 中 `MAX_ROUTES` 与 `RouterFull` 错误
- 首版路由表不存 `Handler`（避免接口装箱）；命中下标后由业务自行映射处理函数
- 测试：`test_http_router.uya`

**Phase 5：http.server（进行中）**
- `server.uya`：`http_conn_read_parse`（`IncompleteRequest` 时续读）、`http_connbuf_shift`（已消耗字节前移）、`HTTP_CONN_READ_CAP` 与 `http_recv_parse_request` 内部多 `recv`
- `parse.uya`：首行/头部行末无完整 CRLF 或 body 未收齐时返回 `error.IncompleteRequest`（`find_crlf_or_incomplete`）
- 测试：`test_http_server.uya`（含流水线双 GET、`POST+GET`→`201`/`204`、`http_parse_error_returns_400`）、`parse_post_body_incomplete`；`http_send_response` 支持 `Created`/`NoContent` 状态行
- 示例：`examples/http_server.uya`（`try` + `match`：`pr`/成功分支放在各 `error.*` 之后，避免 C 代码 `else` 悬空）

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
| 泛型限制 | 曾阻碍 `Future<!T>` + typedef 与 `ok<bool>` 单态 | **已缓解**：`AsyncComputeFuture<T>` 泛型体 + C99 装箱/成员调用修复；对外仅 **`async_compute<T>`**（含 f32/f64）；typedef 别名保留 |
| Linux 专属 | epoll/eventfd 仅 Linux；跨平台需 kqueue/iocp | 当前专注 Linux；设计时抽象 EventLoop 接口 |
| 估计偏差 | HTTP 解析器边界情况可能超预期 | Phase 3 预留 2 周缓冲 |
