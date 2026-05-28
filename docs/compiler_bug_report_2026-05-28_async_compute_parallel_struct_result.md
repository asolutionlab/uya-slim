# `std.thread.async_compute<usize>` 返回堆分配结构体结果时的运行期崩溃报告（2026-05-28）

本文档记录一个已在本仓库本地复现、并已修复的问题：worker 通过 `async_compute<usize>` 返回 `WorkerResult*` 的 `usize` 编码值后，主线程 `block_on<usize>` 解码并读取结果时曾发生 SIGSEGV。

当前状态：已修复（2026-05-28）

## 最小复现

- 复现文件：`tests/repros/async_compute_parallel_struct_result_bug.uya`

复现命令：

```bash
./bin/uya build tests/repros/async_compute_parallel_struct_result_bug.uya -o /tmp/async_compute_parallel_struct_result_bug
/tmp/async_compute_parallel_struct_result_bug
echo EXIT:$?
```

当前结果：

```text
Segmentation fault
EXIT:139
```

期望结果：

```text
EXIT:0
```

## 修复结果

根因最终分成两层：

1. `lib/std/thread.uya` 的常驻 worker 原先是 `fork` 出来的 worker 进程。这样 child 里 `malloc` 出来的结果对象并不和调用方共享地址空间，把 `WorkerResult*` 重新编码成 `usize` 回传后，主线程拿到的只是“数值相同但不指向同一对象”的地址。
2. 在把常驻 worker 切到 `pthread` 线程后，又暴露出 `lib/libc/pthread.uya` 的 x86_64 启动 trampoline 栈对齐 bug：`_pthread_call_start()` 额外做了一次 `subq $8`，导致线程入口后续调用链的栈错 8 字节，对 `movaps` 一类要求 16 字节对齐的指令会直接触发 SIGSEGV。

本次修复内容：

- `lib/std/thread.uya`：常驻 ThreadPool worker 从 `fork` 子进程切为 `pthread` 线程，保留现有 shared-slot / pipe 驱动模型。
- `lib/libc/pthread.uya`：修正 x86_64 `_pthread_call_start()` 的栈对齐，去掉多余的 `subq/addq $8`。
- `tests/test_std_thread.uya`：新增 `async_compute_usize_can_roundtrip_heap_pointer_with_thread_pool` 回归，覆盖“worker 返回堆对象指针，经 `usize` 往返后主线程解引用”的场景。

当前验证结果：

```bash
./bin/uya test tests/test_pthread_api_create_join.uya
./bin/uya test tests/test_std_thread.uya
./bin/uya build tests/repros/async_compute_parallel_struct_result_bug.uya -o /tmp/async_compute_parallel_struct_result_bug
/tmp/async_compute_parallel_struct_result_bug
echo EXIT:$?
```

结果：

```text
test_pthread_api_create_join: 通过
test_std_thread: 20/20 通过
EXIT:0
```

## 复现程序包含的关键变量

这个最小复现不依赖业务仓库，但它同时覆盖了几类容易互相干扰的条件：

1. 主线程准备一段较大的堆上 payload，并拆成多个 `WorkItem`。
2. 每个 worker 通过 `async_compute<usize>` 接收一个 `WorkerTask` 指针。
3. worker 在堆上分配 `WorkerResult`，其中保存一个 `&PairHash` 数组。
4. `PairHash` 内嵌两个 `Hash32`，每个 `Hash32` 都是 `[byte:32]`。
5. worker 内部每轮计算都会经过 `Arena + blake3_digest` 的哈希路径。
6. worker 把 `WorkerResult*` 重新编码成 `usize` 返回给主线程。
7. 主线程 `block_on<usize>` 取回该值，再用 `@ptr_from_usize` 转回指针并读取结果。

因此，这个 repro 目前只能证明“复杂结果通过 `usize` 往返后出错”，还不能单凭它断言是 `std.thread`、future 完成态、结构体 copy/lowering，还是 worker 内部计算先破坏了内存。

## 本次复现拿到的直接证据

已确认：

- 前端解析、类型检查、C99 生成和宿主 C 编译都通过。
- 崩溃发生在运行期，而且发生在主线程读取 worker 返回结果时。
- 仓库里已有 `tests/test_std_thread.uya` 与 `tests/test_async_compute_types.uya` 覆盖普通 `async_compute<usize>` 标量路径；这个 repro 新增的是“堆分配结构体结果指针经 `usize` 往返”的场景。

使用 `gdb` 观察本次现场，崩溃栈为：

```text
Program received signal SIGSEGV, Segmentation fault.
0x... in pair_hash_equal (left=0x0, right=0x...) at uya_common.c:292
#0  pair_hash_equal(...)
#1  main_main () at uya_common.c:3272
```

同一现场里，主线程局部变量显示：

```text
result_bits = 140737340781120
result      = 0x7ffff7343240
result->pairs = 0x0
result->len   = 140737353877280
local = 0
global_index = 0
```

这说明崩溃不是因为 `pair_hash_equal` 自身逻辑出错，而是因为主线程拿到的 `WorkerResult*` 内容已经明显异常：

- `result->pairs` 在首次读取时就是 `null`
- `result->len` 也不是预期的 `5`
- 本次 `gdb` 现场里，`result_bits` 落在主线程栈上、紧邻 `futures` 局部变量区域，不像是 worker 里 `malloc` 出来的结果指针

上面这些现象更像“返回值在 worker -> future -> 主线程 这条路径上被污染或被错误解释”，但还不能完全排除 worker 线程更早阶段已经写坏了内存。

## 当前能说到哪一步

已经可以说：

- 问题不是语法、类型系统或宿主 C 编译失败，而是纯运行期崩溃。
- 崩溃点在主线程读取 worker 结果时，而不是 worker 创建、future 构造或 `block_on` 启动时。
- “普通标量 `usize`” 和“把堆对象指针塞进 `usize` 再取回”不是同一风险级别；当前失败的是后者。

还不能直接说：

- 一定是 `lib/std/thread.uya` shared-slot / pipe 回传逻辑本身有 bug。
- 一定是 `AsyncComputeFuture<usize>` boxing/unboxing 把值改坏了。
- 一定是嵌套结构体 copy/lowering 的问题。
- 一定与 `Arena + blake3_digest` 无关。

## 建议排查顺序

1. 先把 worker 内部哈希逻辑替换成常量填充，保留“堆分配 `WorkerResult` -> `usize` 返回 -> 主线程解码”这条路径。如果仍崩溃，优先看结果传递和解码链路。
2. 再做反向缩减：保留 `Arena + blake3_digest`，但让 worker 只返回标量校验值而不是结果指针。如果这样不崩溃，重点就收敛到“指针/结构体结果往返”路径。
3. 优先检查 `lib/std/thread.uya` 中 `result_bits` 的生产与消费路径，尤其是 worker 写回 shared slot、`finish_from_raw_value`、`finish_from_raw_poll` 这几段。
4. 如果线程结果链路看起来正确，再检查 `run_worker` 里 `PairHash` 赋值，以及 C99 backend 对 `@usize_from_ptr` / `@ptr_from_usize`、结构体赋值和嵌套固定数组的生成。

## 影响

- 会阻塞“worker 并行计算复杂结果，主线程汇总”的使用形态进入稳定可用状态。
- 这也是上层仓库想用于 large-file chunk/hash 并行化的基本模式；但外部仓库里见到的崩溃是否与本 repro 完全同因，仍需要单独验证，不能直接在本报告里写死。

## 关联文件

- `tests/repros/async_compute_parallel_struct_result_bug.uya`
- `lib/std/thread.uya`
- `buglist.md`
