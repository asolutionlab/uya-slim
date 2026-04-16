# Uya v0.9.3 发布说明

> **类型**：**v0.9.x 发行线上的功能版本**
> **发布日期**：2026-04-16

## 概要

v0.9.3 以 async 运行时和语法能力为主线，补齐了从 `@await` lowering、跨线程唤醒、通用任务队列、取消语义，到 async I/O 原语、async 方法、`@frame(foo)` 生命周期 API 的整条链路。
这一版同时把相关设计文档、状态矩阵和语言手册同步到了当前实现，便于后续继续推进 release 版验证。

---

## 核心变更

### 1. async/await lowering 修复与收口

- 修复了复合表达式里的 `try @await` lowering 边角，避免复杂表达式在 codegen 阶段走错路径。
- 清理了 async lowering 相关的历史待办与状态描述，`docs/async_status_matrix.md`、`docs/async_production_todo.md`、`docs/todo_async_runtime_and_http.md` 已同步当前实现。
- `tests/test_async_compound_try_await.uya` 已加入回归，覆盖 `try @await` 在复合表达式中的行为。

### 2. async 运行时能力补齐

- 跨线程唤醒链路接通到 `eventfd`，async scheduler 可以跨线程唤醒等待的 event loop。
- 引入通用 `TaskQueue<T>`，替代只服务少数类型的特化队列，便于复用到更多 async 场景。
- 完整取消语义已接入：`Waker.cancel()` / `is_cancelled()`、`TaskQueue.cancel()`、`async_compute` 的排队中与运行中任务回收策略都已统一。
- 新增并扩展了 async scheduler / thread / multi-fd concurrent 等回归，确保共享 I/O 与取消路径稳定。

### 3. 更完整的 async I/O 原语与 helper

- `std.async` 新增并补齐了更高层的 I/O helper：
  - `AsyncWriter.write_all(...)`
  - `AsyncReader.read_exact(...)`
  - `AsyncFd.read_exact(...)`
  - `AsyncFd.write_all(...)`
  - `async_write_bytes(...)`
  - `async_write_cstr(...)`
  - `async_print_to(...)`
  - `async_print_bytes_to(...)`
  - `async_println_to(...)`
  - `async_println_bytes_to(...)`
- 对应的 `MemAsyncWriter` / `MemAsyncReader` / `AsyncFd` 回归已补齐。
- 新增 pipe + `LinuxEpoll` 共享调度回归，覆盖真实 I/O 场景而不仅是 mock scheduler。

### 4. async 方法与接口签名支持

- `@async_fn` 现在可用于：
  - 顶层函数
  - 结构体/联合体的方法实现
  - 接口方法签名
- 这一版把 async 能力从“函数级”扩展到“方法级”，让接口抽象和 async 实现可以直接对接。
- `tests/test_async_method_interface.uya` 已加入回归，覆盖 async 方法实现与接口签名组合。

### 5. `@frame(foo)` 生命周期 API 收口

- `@frame(foo)` 现在对外的高层生命周期 API 收口为：
  - `frame.start(...)`
  - `frame.poll(&waker)`
  - `frame.stop()`
- 底层 C helper 继续保留为 `*_frame_start` / `*_poll` / `*_frame_stop`，同时维持旧的兼容别名。
- `@frame(foo)` 的 pinned 语义与 checker / codegen 已和文档同步，避免“release/drop/reset”这类旧命名继续扩散。

### 6. 文档与状态同步

- `docs/uya.md`、`docs/uya_ai_prompt.md`、`docs/compiler_status.md`、`docs/grammar_quick.md`、`docs/builtin_functions.md`、`docs/async_status_matrix.md`、`docs/std_async_design.md`、`docs/todo_async_runtime_and_http.md`、`docs/todo_mini_to_full.md`、`docs/async_production_todo.md` 均已同步当前 async 能力。
- `docs/async_frame_allocation_design.md`、`docs/async_frame_lifecycle_naming_design.md`、`docs/todo_async_frame_allocation.md` 已更新 `@frame` 生命周期命名和兼容别名说明。

---

## 测试

- `make check`：**785** 项测试通过
- `make b`：自举验证通过，主编译器与自举编译器生成的可执行文件字节相同

新增测试：

- `tests/test_async_compound_try_await.uya`
- `tests/test_async_io.uya`
- `tests/test_async_fd.uya`
- `tests/test_async_method_interface.uya`
- `tests/test_std_async_scheduler.uya`
- `tests/test_std_thread.uya`
- `tests/test_async_multi_fd_concurrent.uya`

---

## 相关文件变更

- `src/parser/main.uya`
- `src/parser/declarations.uya`
- `src/checker/check_stmt.uya`
- `src/checker/check_call.uya`
- `src/checker/type_from_ast.uya`
- `src/checker/lookup.uya`
- `src/checker/main.uya`
- `src/checker/types.uya`
- `src/checker/symbols.uya`
- `src/codegen/c99/function.uya`
- `src/codegen/c99/expr.uya`
- `src/codegen/c99/types.uya`
- `lib/std/async.uya`
- `lib/std/async_scheduler.uya`
- `lib/std/thread.uya`
- `lib/libc/syscall.uya`
- `docs/async_frame_allocation_design.md`
- `docs/async_frame_lifecycle_naming_design.md`
- `docs/todo_async_frame_allocation.md`
- `docs/async_status_matrix.md`
- `docs/std_async_design.md`
- `docs/todo_async_runtime_and_http.md`
- `docs/todo_mini_to_full.md`
- `docs/async_production_todo.md`
- `docs/uya.md`
- `docs/uya_ai_prompt.md`
- `docs/compiler_status.md`
- `docs/builtin_functions.md`
- `docs/grammar_quick.md`
