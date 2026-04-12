# Uya libc pthread NPTL-lite 改造 TODO

日期：2026-04-12
最新更新：2026-04-12（稳定基线恢复）

## 状态摘要（2026-04-12）

- **Phase 0 稳定**：`tests/test_pthread.uya` 22/22 通过，`tests/test_pthread_cond.uya` 3/3 通过。
- **已落地**：
  - `syscall.uya` 补齐了 `CLONE_*` 和 `FUTEX_*_PRIVATE` 常量。
  - `pthread_desc` + `_pthread_registry` 已启用，`pthread_self` 通过稳定的 `pub_handle` 返回当前线程句柄。
  - `pthread_create` 已改成“先建 descriptor、再 clone、child 入口直接调用 start routine 并 `sys_exit(0)`”。
  - `pthread_exit` 已能把 `result` / `exited` 写回 descriptor；`pthread_join` 仍通过 `waitpid` 做回收，并从 descriptor 读取返回值。
  - mutex owner 已全量改用 `sys_gettid()`，mutex 也已引入 `0/1/2` futex 慢路径（fast path CAS `0->1`，slow path futex wait，unlock futex wake）。
  - `pthread_once` 已从忙等改为 futex wait/wake 状态机（`0=never, 1=running, 2=done`）。
  - `pthread_cond_*`、`pthread_key_*`、`pthread_cancel` 这些 API 已有基础实现，但语义仍偏 NPTL-lite。
- **仍待补齐**：真正的 `CLONE_THREAD` / `CLONE_SETTLS` / `joinstate` futex 迁移、TSD destructor、多线程 cancel state/type、以及 detached 线程的最终资源回收模型。
- **当前模型**：`pthread_create` 仍使用 `CLONE_VM | SIGCHLD`（即 `0x00000100 | 17`），但已经有 descriptor registry 和稳定 `pthread_self`；`pthread_join` 仍依赖 `sys_waitpid`，`CLONE_THREAD` 切换待 `joinstate` / TLS / TCB 方案就绪后再执行。

## 背景

Uya 当前 `lib/libc/pthread.uya` 已经覆盖了不少 pthread API，但实现模型仍然偏向“最小可跑”：

- `pthread_create` 当前仍使用 `CLONE_VM | SIGCHLD`，并通过 `waitpid` 完成 `pthread_join`；但 child 路径已经直接调用 start routine，然后 `sys_exit(0)`，避免回到 C 级返回链。
- 这不是 glibc NPTL 的线程组模型。NPTL 使用 Linux `clone` 创建 1:1 内核线程，并依赖 `CLONE_THREAD`、`CLONE_SETTLS`、`CLONE_PARENT_SETTID`、`CLONE_CHILD_CLEARTID`、futex、TLS/TCB 和信号机制。
- 当前 `pthread_create` 仍依赖全局 `_pthread_start_fn` / `_pthread_start_arg` 传参。这个方式能靠 `_pthread_create_mutex` 规避并发创建竞态，但长期应改为“每线程 descriptor 自带启动参数”。
- 当前递归 mutex owner 已修复为 `sys_gettid()` / descriptor tid，不再依赖 `getpid()`。
- 当前 TSD 已有基础实现，但仍是 `tid % 64` 的全局数组模拟，不满足真实 per-thread storage 和 destructor 语义。

本计划目标不是复制 glibc 代码，而是参考 glibc NPTL 的结构与语义，做一版适合 Uya 当前 runtime 的 **NPTL-lite**。

## 参考资料

- glibc 2.34 将原 `libpthread`、`libdl`、`libutil`、`libanl` 功能并入 `libc`，保留空静态归档以兼容旧链接参数：<https://sourceware.org/pipermail/libc-announce/2021/000032.html>
- glibc `pthread_create` / `createthread` 路线中使用 `clone` flags、TLS、parent/child tid：<https://sourceware.org/pipermail/glibc-cvs/2021q2/073250.html>
- glibc `clone` / `clone3` 内部包装和 stack size 传递：<https://sourceware.org/pipermail/glibc-cvs/2021q3/073721.html>
- glibc join/detach/exit 改用 `joinstate` futex 状态机的说明：<https://sourceware.org/pipermail/glibc-cvs/2021q2/073359.html>
- glibc NPTL futex 内部封装方向：<https://sourceware.org/pipermail/glibc-cvs/2020q4/071070.html>
- glibc condvar 的 64-bit waiter sequence 和 G1/G2 双组设计说明：<https://sourceware.org/pipermail/glibc-cvs/2016q4/061458.html>

## 范围

### Phase 0 目标

- 保持现有 Linux pthread 测试不回归。
- 明确当前实现不是完整 NPTL，只是 API 覆盖较多的 clone/futex 最小实现。
- 新增 TODO 文档和测试分层，避免继续把“API 覆盖”误写成“线程语义完整”。

### NPTL-lite 第一版目标

- Linux 优先：x86_64 先落地，再补 arm64/riscv64。
- 覆盖核心 API：
  - `pthread_create`
  - `pthread_join`
  - `pthread_exit`
  - `pthread_detach`
  - `pthread_self`
  - `pthread_equal`
  - `pthread_mutex_*`
  - `pthread_cond_*`
  - `pthread_once`
  - `pthread_key_*`
  - `pthread_getspecific`
  - `pthread_setspecific`
- 使用 Linux 1:1 线程模型：
  - `CLONE_VM`
  - `CLONE_FS`
  - `CLONE_FILES`
  - `CLONE_SYSVSEM`
  - `CLONE_SIGHAND`
  - `CLONE_THREAD`
  - `CLONE_PARENT_SETTID`
  - `CLONE_CHILD_CLEARTID`
  - `CLONE_SETTLS` 在 TLS/TCB 就绪后启用
- join/detach/exit 用 descriptor + futex 状态机，不再依赖 `waitpid`。

### 暂缓目标

- robust mutex
- priority inheritance mutex
- process-shared pthread 对象
- 完整异步 cancel
- 完整信号取消点集成
- glibc 级别 condvar G1/G2 全量实现
- stack cache 优化
- macOS/Darwin 系统 pthread 桥接

Darwin 路线继续按 `docs/todo_macos_phase5.md` 独立推进，不混入本 Linux NPTL-lite 计划。

## 当前差距清单

- [ ] `pthread_create` 使用 `CLONE_VM | SIGCHLD`，不是 `CLONE_THREAD` 线程组模型。
- [ ] `pthread_join` 依赖 `waitpid`，切到 `CLONE_THREAD` 后不可用。
- [x] `pthread_exit` 已保存 retval 到 descriptor，但 TSD destructor 处理仍缺失。
- [ ] `pthread_detach` 只有 detached 标记，没有 join/detach/exit 完整状态机。
- [x] `pthread_self` 已返回稳定 `pthread_t` handle，不再临时构造对象。
- [ ] `pthread_create` 使用全局 `_pthread_start_fn` / `_pthread_start_arg`，不应作为长期架构。
- [x] mutex owner 使用 `getpid()`，在真实线程组内会误判 owner。 → **已修复为 `sys_gettid()`**
- [x] mutex 状态只有简化 `0/1`，缺少 “locked maybe waiter” futex 慢路径优化。 → **已实现 `0/1/2` futex 慢路径**
- [ ] `pthread_mutex_timedlock` 当前是简化实现，语义与返回码需要重做。
- [x] condvar 的 `waiters + seq` futex 基础版本已落地，但 `condattr` / clock 语义仍未补齐。
- [ ] TSD 用全局哈希数组模拟，缺少 per-thread value array 和 destructor 多轮调用。
- [ ] cancel 只记录 tid 槽位，`pthread_setcancelstate` / `pthread_setcanceltype` 仍是占位语义。
- [x] `pthread_once` 忙等，应该改成 futex wait/wake。 → **已实现 futex 状态机**
- [ ] rwlock 主要用 yield 忙等，应该增加 futex 慢路径。
- [ ] 测试直接构造 `pthread_t`、`pthread_mutex_t` 等内部结构，耦合实现细节。

## 详细 TODO

### 1. 文档与测试边界

- [x] 更新 `docs/libc_todo.md` 中 pthread 状态，改为“NPTL-lite + 语义仍在收口”。
- [x] 更新 `docs/libc_progress.md` 中 pthread 部分，列出 `waitpid join`、全局启动参数、简化 TSD 等限制。
- [ ] 新增 `tests/test_pthread_api.uya`，只验证 public API，不直接构造内部字段。
- [ ] 保留现有 `tests/test_pthread.uya` 为 Linux 实现细节测试，逐步迁移。
- [ ] 扩展 `tests/stress_pthread.sh`，加入多轮 create/join、mutex 竞争、condvar、TSD 压测。

### 2. syscall 基础

- [x] 在 `lib/libc/syscall.uya` 补齐 Linux clone flags：
  - [x] `CLONE_VM`
  - [x] `CLONE_FS`
  - [x] `CLONE_FILES`
  - [x] `CLONE_SYSVSEM`
  - [x] `CLONE_SIGHAND`
  - [x] `CLONE_THREAD`
  - [ ] `CLONE_SETTLS`
  - [x] `CLONE_PARENT_SETTID`
  - [x] `CLONE_CHILD_CLEARTID`
- [x] 在 `lib/libc/syscall.uya` 补齐 futex op：
  - [x] `FUTEX_WAIT_PRIVATE`
  - [x] `FUTEX_WAKE_PRIVATE`
  - [ ] `FUTEX_WAIT_BITSET`
  - [ ] `FUTEX_WAKE_BITSET`
  - [ ] `FUTEX_CLOCK_REALTIME`
- [x] 新增 `sys_set_tid_address(clear_child_tid: &i32) !i64`。
- [x] 新增 `sys_tgkill(tgid: i32, tid: i32, sig: i32) !i32`，为 cancel/signal 预留。
- [ ] 扩展 `sys_futex` 返回值，尽量保留 `-errno`，不要只返回 `-1`。
- [ ] 新增 `sys_futex_wait`、`sys_futex_wake`、`sys_futex_wait_bitset` helper，减少 pthread 里直接拼 syscall 参数。

### 3. Thread descriptor 与主线程初始化

- [x] 已落地内部 `pthread_desc` 结构与 registry；当前字段包含 `tid` / `stack` / `stack_size` / `detached` / `exited` / `result` / `pub_handle`。
- [ ] 若后续切到真正 NPTL，可再补更完整的 `joinstate` / `cancel` / `TSD` 字段：
  - [ ] `tid: atomic i32`
  - [ ] `joinstate: atomic i32`
  - [ ] `detached: atomic i32`
  - [ ] `start_routine: &void`
  - [ ] `arg: &void`
  - [ ] `result: &void`
  - [ ] `stack_base: &void`
  - [ ] `stack_size: usize`
  - [ ] `guard_size: usize`
  - [ ] `cancel_state: atomic i32`
  - [ ] `cancel_type: atomic i32`
  - [ ] `cancel_pending: atomic i32`
  - [ ] `tsd_values: &&void`
  - [ ] `next: &pthread_desc`
- [ ] 定义 `joinstate` 状态：
  - [ ] `PTHREAD_JOINABLE`
  - [ ] `PTHREAD_EXITING`
  - [ ] `PTHREAD_EXITED`
  - [ ] `PTHREAD_JOINED`
  - [ ] `PTHREAD_DETACHED`
- [ ] 先将 `pthread_t` 收敛为更纯粹的 handle，短期保留兼容字段或提供转换层。
- [x] 主线程 descriptor 已懒初始化（第一次 `pthread_self` 时自动建立）。
- [x] `pthread_self` 已返回稳定 handle，不再构造临时对象。

### 4. clone trampoline

- [x] child 分支现在直接调用 `start_routine(arg)`，然后 `sys_exit(0)`，不再回到 C 级返回链。
- [ ] 未来若切到 `CLONE_THREAD`，再把这段收敛成架构相关 trampoline/helper，统一 x86_64 / arm64 / riscv64 的入口。
- [ ] 仍要避免 child 换栈后继续依赖父栈局部变量。
- [ ] 仍需确认 C99 codegen 是否要注入 helper，例如 `uya_clone_thread`。

### 5. pthread_create

- [x] descriptor 已在 clone 前分配，clone 成功后再写入 registry。
- [ ] 栈仍用 malloc 分配，后续再换 mmap 分配线程栈。
- [ ] 栈顶按 ABI 做 16-byte 对齐。
- [ ] 支持 guard page：
  - [ ] `mmap` 多分配 guard。
  - [ ] `mprotect(PROT_NONE)` 设置 guard。
  - [ ] `pthread_attr_setguardsize` 可后续补。
- [ ] 按 attr 处理 stack size，校验 `PTHREAD_STACK_MIN`。
- [x] child 路径已从 `pthread_create` 里拆出，直接调用 start routine 后退出。
- [ ] 仍使用 `CLONE_VM | SIGCHLD`；`CLONE_THREAD` / `CLONE_PARENT_SETTID` / `CLONE_CHILD_CLEARTID` / `CLONE_SETTLS` 还要后续迁移。
- [ ] 父线程通过 `ptid` 获取 child tid。
- [ ] child exit 通过 `ctid` 或 descriptor `tid` + futex 唤醒 joiner。
- [ ] 失败路径释放 descriptor 和 stack。
- [ ] detached 线程从 create attr 进入 `DETACHED` 状态。

### 6. pthread_join / pthread_exit / pthread_detach

- [x] `pthread_exit(retval)` 已保存 `retval` 到 descriptor，并置 `exited`。
- [ ] 仍缺 TSD destructor。
- [x] `pthread_join` 当前通过 `waitpid` 等待线程结束，然后从 descriptor 读取 `retval` 并回收栈/descriptor。
- [ ] `pthread_join` 尚未迁移到 futex joinstate，也还没有重复 join / detached 的完整状态机。
- [x] `pthread_detach` 已有 detached 标记。
- [ ] `pthread_detach` 仍需要 CAS 状态机来处理与 join/exit 的竞态。
- [ ] detached 线程退出后的资源回收先做安全保守版：
  - [ ] 不在线程仍在用栈时 munmap 当前栈。
  - [ ] 可先保留资源到进程结束。
  - [ ] 后续再实现 reaper 或 stack cache。

### 7. TLS / TCB

- [ ] 确认 Uya 当前 C99 运行时是否已有 thread-local 能力。
- [ ] 如果没有，先做最小 thread pointer 方案：
  - [ ] x86_64 可评估 `arch_prctl(ARCH_SET_FS)` 与宿主 C runtime 冲突风险。
  - [ ] 如果风险过高，第一版先用 gettid 到 descriptor registry 查询。
- [ ] 给 descriptor registry 加锁或 lock-free 查找策略。
- [ ] `pthread_self` 从 TLS/registry 返回当前 descriptor。
- [ ] `CLONE_SETTLS` 只在 TCB 方案安全后开启。

### 8. mutex

- [x] 所有 owner 逻辑改用 `gettid()` 或 descriptor tid，不再用 `getpid()`。
- [x] 普通 mutex 改成 `0/1/2` 状态：
  - [x] `0 = unlocked`
  - [x] `1 = locked no known waiter`
  - [x] `2 = locked maybe waiter`
- [x] lock fast path CAS `0 -> 1`。
- [x] lock slow path将状态转为 `2` 并 futex wait。
- [x] unlock 在必要时 futex wake 1。
- [x] recursive mutex 增加 owner tid 与 recursion count。
- [x] errorcheck mutex：
  - [x] owner 重复 lock 返回 `EDEADLK`。
  - [x] 非 owner unlock 返回 `EPERM`。
- [x] `pthread_mutex_timedlock` 重写（基础版已落地，循环内重算剩余时间）：
  - [ ] 使用 `FUTEX_CLOCK_REALTIME` 将绝对时间直接传入 futex（后续优化）。
  - [ ] 支持 clock attr 或先限定 realtime。
  - [x] 校验 `tv_nsec`。
  - [x] timeout 返回 `ETIMEDOUT`。
- [ ] 增加竞争测试：
  - [ ] 2 线程计数。
  - [ ] 8/32 线程计数。
  - [ ] recursive/errorcheck owner 行为。

### 9. condition variable

- [x] 第一版 `waiters + seq + futex` 模型已落地，`pthread_cond_wait` / `pthread_cond_timedwait` / `pthread_cond_signal` / `pthread_cond_broadcast` 都已可用。
- [ ] `pthread_condattr_*` 仍未补齐：
  - [ ] `pthread_condattr_init`
  - [ ] `pthread_condattr_destroy`
  - [ ] `pthread_condattr_getclock`
  - [ ] `pthread_condattr_setclock`
- [ ] `pthread_cond_timedwait` 目前按 `gettimeofday` + 相对超时处理，后续再补 `CLOCK_REALTIME` / `CLOCK_MONOTONIC`。
- [ ] 后续评估 glibc 类 64-bit waiter sequence + G1/G2 双组方案。
- [ ] 增加真实多线程测试：
  - [ ] 1 waiter + 1 signaler。
  - [ ] N waiters + broadcast。
  - [ ] timeout 与 signal 竞态。
  - [ ] signal 早于 wait 不应错误唤醒。

### 10. pthread_once

- [x] 将 busy wait 改为 futex wait/wake。
- [x] 状态定义 `0 = never` / `1 = running` / `2 = done` 已在实现中落地。
- [x] 初始化成功后 wake 所有等待线程。
- [ ] 处理初始化函数异常退出或线程取消的后续策略。
- [ ] 增加多线程并发 once 测试。

### 11. TSD / pthread_key

- [x] `pthread_key_create` / `pthread_key_delete` / `pthread_getspecific` / `pthread_setspecific` 已有基础实现。
- [ ] key registry 只管理 key 元数据，当前还夹带了简化的 value storage。
- [ ] 每个 descriptor 仍未真正拥有自己的 TSD value array。
- [ ] `pthread_setspecific` 目前还不是严格的 descriptor-backed 存储。
- [ ] `pthread_getspecific` 还需要从当前线程 descriptor 读取。
- [ ] `pthread_key_delete` 仍需要更严格的 generation 语义，避免旧 key 误用。
- [ ] 在线程退出时执行 destructor。
- [ ] destructor 按 POSIX 做多轮扫描，第一版可设置轮数常量。
- [ ] 增加测试：
  - [ ] 主线程和子线程同 key 不同 value。
  - [ ] destructor 被调用。
  - [ ] key delete 后访问返回 null 或 EINVAL 路径一致。

### 12. cancel

- [x] `pthread_cancel` / `pthread_testcancel` / `pthread_setcancelstate` / `pthread_setcanceltype` 已有基础实现。
- [ ] descriptor 中仍未保存 cancel state/type/pending。
- [ ] `pthread_cancel` 目前只是写入 tid 槽位。
- [ ] deferred cancel 还要接到 `pthread_testcancel` 和取消点检查。
- [ ] `pthread_setcancelstate` / `pthread_setcanceltype` 仍只是参数校验。
- [ ] 第一版 async cancel 可返回 `ENOTSUP` 或只在安全点生效，需文档明确。
- [ ] 后续用 `tgkill`/内部信号唤醒阻塞 syscall。
- [ ] `pthread_join` 对 canceled 线程返回 `PTHREAD_CANCELED`。

### 13. rwlock / spinlock / barrier

- [ ] rwlock 从 yield 忙等改为 futex 慢路径。
- [ ] rwlock 增加 writer preference 或 reader preference 策略说明。
- [ ] spinlock 增加 pause/yield 退避，不进入 futex。
- [ ] barrier 依赖修正后的 mutex/cond 实现。
- [ ] 增加多线程 barrier 测试，覆盖重复使用 generation。

### 14. affinity / sched 扩展

- [ ] 保留 `pthread_setaffinity_np` / `pthread_getaffinity_np`，继续以 tid 调用 `sched_*affinity`。
- [ ] 在 `CLONE_THREAD` 后确认 tid 仍与 `gettid()` 一致。
- [ ] 后续支持 create attr 的 sched policy/priority/affinity 时，需要 child startup latch，确保用户入口执行前完成设置。

### 15. 验证命令

- [ ] `./bin/uya test tests/test_syscall_thread.uya`
- [ ] `./bin/uya test tests/test_pthread.uya`
- [ ] `./bin/uya test tests/test_pthread_cond.uya`
- [ ] `tests/stress_pthread.sh`
- [ ] `make check`
- [ ] 自举验证，确保 compiler 使用新 libc pthread 后不回归。

## 建议提交顺序

1. `pthread: document nptl-lite scope` ✅
2. `test: split pthread api and linux implementation tests`
3. `syscall: add clone and futex pthread primitives` ✅
4. `pthread: fix mutex owner and futex slow path` ✅
5. `pthread: futex-based pthread_once` ✅
6. `pthread: introduce thread descriptor`
7. `pthread: add clone trampoline for nptl-lite threads`
8. `pthread: move join and exit to futex joinstate`
9. `pthread: repair condvar wait signal timedwait`
10. `pthread: implement per-thread keys and once futex`
11. `pthread: add cancellation state and testcancel semantics`
12. `test: add pthread stress and semantic coverage`

## 风险

- `CLONE_SETTLS` 可能与宿主 C runtime TLS 冲突，需要谨慎设计 TCB。
- detached 线程的栈回收不能在线程还在当前栈上执行时直接 `munmap`。
- `CLONE_THREAD` 后不能再用 `waitpid` 回收线程，join 必须先完成状态机迁移。
- 修改 `pthread_t` 结构会影响现有测试里直接构造内部字段的代码，需要测试先降耦。
- C99 codegen 可能需要注入架构相关 clone trampoline helper，不能只在 Uya 层拼普通函数调用。
