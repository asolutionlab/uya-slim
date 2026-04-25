# Uya Async 现状总表

**最后更新**：2026-04-25  
**范围**：Linux + C99 后端；聚焦 `@async_fn` / `@await` / `Future` / `Poll` / `Waker` / `AsyncFd` / `Scheduler` / `async_compute`

## 总览

| 能力 | 状态 | Runtime | Codegen | Tests | Docs |
|------|------|---------|---------|-------|------|
| async lowering / 状态机控制流 | ✅ 完成 | `if/else if`、`while`、范围 `for`、定长数组 `for`、嵌套块、循环间同步语句已稳定 | Bug A/B/C/D 与复合表达式中的 `try @await`（赋值 RHS / return 表达式）已修复；`const r: !T = @await fut` 这类 direct err-union await 绑定也已接通；`return error.X`、局部变量提升、await 间同步语句恢复 | `test_async_bug_b_sync_between.uya` `test_async_for_await.uya` `test_async_bug_d_nested_block.uya` `test_async_compound_try_await.uya` `test_async_await_direct_err_union.uya` | `async_coroutine_transform_design.md` `plan_async_coroutine_transform.md` `async_loop_await_design.md` |
| async 方法 / 接口方法签名 | ✅ 完成 | 结构体内部方法、外部方法块、接口方法签名均支持 `@async_fn`；接口 ABI 仍以 `Future<!T>` / `!Future<T>` 表达 | 方法 async wrapper/poll、`Self` 解析、`Type::method` async 调用图键与 vtable 分派已接通 | `test_async_method_interface.uya` `test_interface_error_union_method.uya` `test_struct_inner_method_void.uya` | `uya.md` `builtin_functions.md` `grammar_formal.md` `std_async_design.md` |
| async frame 分配 / 生命周期 | ✅ 完成 | 默认路径已切 `AsyncFramePool` + caller-owned inline + pinned 语义；`@frame(foo)` 暴露 `start/poll/stop`；Ready/Error/Cancel 统一释放 | `@frame(foo)` 类型构造器与 frame 生命周期命名已收口 | `test_async_frame_methods.uya` `test_async_frame_stack_ok.uya` `test_async_frame_release_path.uya` | `async_frame_allocation_design.md` `todo_async_frame_allocation.md` |
| `Waker` / `EventLoop` / `AsyncFd` | ✅ Linux 主路径完成 | `Waker` 支持单 interest、`eventfd` 绑定/关闭、`cancel/is_cancelled`；`LinuxEpoll` + `AsyncFd` 已接通 readiness；`AsyncWriter/AsyncReader` 已具备 `write_all` / `read_exact`，helper 层已有 `async_write_bytes/cstr`、`async_print_to/println_to` | 无额外关键缺口 | `test_std_async_event.uya` `test_async_fd.uya` `test_async_io.uya` | `std_async_design.md` `async_production_todo.md` |
| `Scheduler` / 泛型 `TaskQueue<T>` | ✅ 完成 | `scheduler_run_*_with_event_loop`、`scheduler_run_pair_i32_with_event_loop`、`TaskQueue<T>` / typed wrappers、共享 `EventLoop` 单轮推进已完成；`Future<!usize>` 的真实 shared-epoll I/O 队列也已验证 | 队列依赖的“数组元素上的接口字段方法调用”与“结构体依赖收集误展开接口模板”已修复 | `test_std_async_scheduler.uya` `test_async_multi_fd_concurrent.uya` `test_async_fd.uya` | `std_async_design.md` `todo_async_runtime_and_http.md` `todo_mini_to_full.md` |
| 跨线程 wake / `eventfd` | ✅ 完成 | `Scheduler` 在 `Pending` 时同步注册 `eventfd + io fd`；worker/外部线程 `wake()` 可直接唤醒主 `EventLoop` | 无新增 codegen 依赖 | `test_std_async_scheduler.uya` 外部 wake 场景 | `async_production_todo.md` `todo_async_runtime_and_http.md` |
| 协作式取消语义 | ✅ 完成 | `Waker.cancel()`、`TaskQueue.cancel()`、统一 deregister / eventfd close / slot cleanup；结果用 `error.Cancelled` 写回 | 无新增关键缺口 | `test_std_async_scheduler.uya` 取消 slot；`test_std_thread.uya` queued/running cancel | `std_async_design.md` `async_production_todo.md` |
| `std.thread.async_compute<T>` 集成 | ✅ Linux 主路径完成 | 未启动/排队/one-shot 任务可立即取消；运行中的共享槽任务在结果回收时稳定返回 `error.Cancelled` | `Future<!T>` 单态、typedef 装箱、成员调用、`f32/f64` helper 已收口 | `test_std_thread.uya` `test_async_compute_types.uya` | `todo_async_runtime_and_http.md` `todo_mini_to_full.md` |
| HTTP/DNS/TLS async 客户端主链路 | ✅ 当前量产主链路完成 | HTTP/1.1 nonblocking connect/read/write、DNS async 查询、timeout/deadline 已接通 | async lowering / 变量提升相关缺口已修复到主链路可用 | `test_http1_async_client.uya` `test_std_dns_async_transport.uya` `test_https_loopback.uya` | `async_production_todo.md` `todo_async_runtime_and_http.md` |
| UyaGin async 服务端协议热路径 | ✅ P5 完成 | request parser 已支持 chunked request 原地解码；response 已支持 `writev` 聚合写、显式 chunked response、Linux x86_64 `sendfile` 优先发送 | 为支撑文件响应路径，direct err-union await bind lowering 缺口已补齐；当前剩余噪音是 parser 对 `catch { ... }` 某些写法的假告警，不影响 codegen/run | `test_http_parse.uya` `test_http_server.uya` `test_http_uyagin.uya` `test_https_loopback.uya` | `uyagin_todo.md` `uyagin_design.md` `tls_https_todo.md` |

## 当前口径

- `Pending` 仍表示“调度层未就绪”，业务错误走 `!T`
- 取消模型是**协作式取消**，future 需要在 `poll()` 中显式检查 `waker.is_cancelled()`
- `Waker` 当前仍是**单 interest / 单 fd** 模型；多 interest 不是当前实现范围
- 跨线程唤醒当前依赖 **Linux `eventfd`**，因此这部分能力口径是 **Linux-only**

## 已完成但仍需记住的约束

- `test_async_multi_fd_concurrent.uya` 现在按“event loop 推进一步后 Ready”的契约断言，不再依赖旧的 `waker.is_woken()` 时序假设
- `async_compute` 的“运行中取消”不会抢占停止宿主计算，而是保证调用侧最终看到 `error.Cancelled`
- `TaskQueue<T>` 现已泛型化，但容量仍是固定 `64`，当前重点是统一调度与取消语义，不是动态扩容
- 复合表达式中的 `try @await` 现已支持赋值 RHS 与 return 表达式，固定回归见 `tests/test_async_compound_try_await.uya`
- direct `const r: !T = @await fut` 绑定现已纳入固定回归；但 parser 对 `catch { 0 - 1 }` 一类写法仍会打印假性的“意外的 token `}`”诊断
- 接口方法签名可写 `@async_fn`，但对接口来说这仍是“返回 future 的异步契约”，不是单独的新 ABI
- `@frame(foo)` 当前公开高层方法只有 `start` / `poll` / `stop`

## 剩余 P2

- 跨平台 `EventLoop` 后端：macOS `kqueue` / Windows `IOCP`
- 更丰富 async formatting/helper（typed writer、`write_byte`、更高层格式化输出等）
- 多 interest `Waker`
- HTTP 连接池与 keep-alive 复用
- TLS 会话复用
- DNS `A/AAAA` 并发聚合
