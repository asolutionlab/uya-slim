# macOS 迁移 Phase 5 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 5：`pthread` 与同步原语 Darwin 路线**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做
- “桥接系统 `pthread`”与“继续零依赖实现”两条路线的推荐取舍

适用范围：

- `lib/libc/pthread.uya`
- `tests/test_pthread.uya`
- `tests/test_pthread_cond.uya`

本阶段核心目标：

- 让 macOS 上的线程与同步能力具备可落地路线
- 优先恢复 `pthread_create/join/mutex/cond` 的最小可用能力
- 让 `pthread` 测试成为**独立基线**，而不是继续阻塞 hosted 主测试集
- 明确区分“API 兼容目标”和“Linux 现有零依赖实现细节”

---

## 默认路线决策

### 推荐默认方案

**推荐先走：桥接系统 `pthread` 路线**

理由：

- [ ] macOS 原生线程/同步语义与 Linux `clone + futex + waitpid` 差异极大
- [ ] 现阶段主目标是先把 macOS 平台 bring-up 跑通，而不是重新实现一套 Darwin 线程内核抽象
- [ ] `pthread` 是独立高风险子项目，若继续坚持“零 libpthread 依赖”，会显著拖慢整个 macOS 迁移

### 长期保留方案

**长期可选：继续评估零依赖路线**

- [ ] 若未来坚持“完全不依赖系统 `libpthread`”，应把它视为独立子项目
- [ ] 该路线不应阻塞当前 macOS 主线迁移

---

## 本阶段完成定义

满足以下条件即可视为 Phase 5 完成：

- [ ] `lib/libc/pthread.uya` 拥有清晰的平台实现边界
- [ ] Darwin 路线已明确采用何种策略：
  - [ ] 系统 `pthread` 桥接
  - [ ] 零依赖自实现（若坚持）
- [ ] macOS 上至少恢复以下最小子集：
  - [ ] `pthread_create`
  - [ ] `pthread_join`
  - [ ] `pthread_mutex_*`
  - [ ] `pthread_cond_*`
- [ ] `tests/test_pthread.uya`、`tests/test_pthread_cond.uya` 拥有可执行的 Darwin 基线
- [ ] `pthread` 测试被独立建线，不与 `check-hosted` 强绑定
- [ ] Linux 现有 pthread 路径不回归

---

## 明确不在本阶段做的事

- [ ] 不实现 Darwin `--nostdlib`
- [ ] 不恢复 async / `kqueue`
- [ ] 不要求复刻 Linux 上所有 futex/clone 语义
- [ ] 不要求第一轮就恢复 `pthread_cancel`、`rwlock`、`spinlock`、`yield` 等全部扩展能力

若某个改动需要依赖这些内容，说明已经越过 Phase 5 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 5 应该做到哪里

在 Phase 5 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：明确 Darwin 路线与接口边界
- [ ] Commit 2：拆分 `lib/libc/pthread.uya` 的平台相关实现层
- [ ] Commit 3：把测试拆成“API 测试”和“Linux 实现细节测试”

做到这里，Linux 的主要职责已经完成：路线定稿、接口分层、测试降耦。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时要真正验证 Darwin 的线程和同步语义：

- [ ] `pthread_create` / `pthread_join`
- [ ] `pthread_mutex_*`
- [ ] `pthread_cond_*`
- [ ] 线程启动、退出、等待和互斥条件变量的真实行为

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin `pthread` 桥接层
- [ ] Darwin 下线程生命周期验证
- [ ] Darwin 下条件变量与互斥量语义验证
- [ ] Darwin 下测试通过结论

这些内容只能算“代码已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 做实现收口和验收

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase4.md](todo_macos_phase4.md) 的 hosted 基线
- [ ] Linux 上执行：
  - [ ] `make check`
  - [ ] `make check-hosted`
- [ ] 记录当前 `pthread` 的强 Linux 绑定点：
  - [ ] `lib/libc/pthread.uya` 顶部注释已明确写明“基于 Linux x86-64 的 `SYS_clone + waitpid + futex`”
  - [ ] `pthread_create` 直接调用 `@syscall(SYS_clone, ...)`
  - [ ] `pthread_join` 直接依赖 `waitpid`
  - [ ] `pthread_mutex_*` / `pthread_cond_*` 直接依赖 `sys_futex`
  - [ ] `tests/test_pthread.uya` 直接构造 `pthread_t` / `pthread_mutex_t` 等内部结构
  - [ ] `tests/test_pthread_cond.uya` 也是实现细节耦合型测试，而非纯 API 测试

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 确定 Darwin 路线与 API 边界 | `lib/libc/pthread.uya`、文档 | Linux 文档与接口不回归 |
| 2 | 拆分平台实现层 | `lib/libc/pthread.uya` | Linux pthread 编译不回归 |
| 3 | 测试降耦与分层 | `tests/test_pthread.uya`、`tests/test_pthread_cond.uya` | Linux 测试不回归 |
| 4 | Darwin 最小桥接落位 | `lib/libc/pthread.uya` | macOS 最小 pthread smoke |
| 5 | Darwin pthread 基线收口 | `lib/libc/pthread.uya`、测试 | macOS pthread 测试通过 |

---

## Commit 1：确定 Darwin 路线与 API 边界

**建议提交名**：`pthread: define darwin strategy and api boundary`

### 目标

- 明确 Darwin 先采用“系统 `pthread` 桥接”路线
- 把当前 Linux 实现从“默认的 POSIX 真相”降级成“Linux 特化实现”

### 修改文件

- [ ] [../lib/libc/pthread.uya](../lib/libc/pthread.uya)
- [ ] 文档入口

### 任务清单

- [ ] 在 `lib/libc/pthread.uya` 注释中明确：
  - [ ] 当前 Linux 实现基于 `clone/futex/waitpid`
  - [ ] Darwin 默认不复用该语义
- [ ] 明确平台接口层与实现层的分工
- [ ] 确认第一阶段 Darwin 最小恢复范围：
  - [ ] 线程创建/等待
  - [ ] 基础 mutex
  - [ ] 基础 cond
- [ ] 明确暂缓项：
  - [ ] `pthread_cancel`
  - [ ] `pthread_rwlock`
  - [ ] `pthread_spinlock`
  - [ ] 高级 attr / timed / affinity / yield 细节

### 验证

- [ ] Linux：编译不回归
- [ ] Linux：`test_pthread.uya` / `test_pthread_cond.uya` 不回归

### 完成标准

- [ ] Darwin 路线明确
- [ ] `pthread` 子系统不再含糊地默认等于 Linux 实现

---

## Commit 2：拆分平台实现层

**建议提交名**：`pthread: split linux-specific implementation details`

### 目标

- 把 Linux 特定实现与公共接口层拆开
- 为 Darwin 桥接层预留清晰落点

### 修改文件

- [ ] [../lib/libc/pthread.uya](../lib/libc/pthread.uya)
- [ ] 必要时新增平台相关文件

### 任务清单

- [ ] 把以下 Linux 特化实现从公共接口层中隔离出来：
  - [ ] `SYS_clone`
  - [ ] `sys_futex`
  - [ ] `waitpid`
  - [ ] Linux 风格线程栈管理
- [ ] 为 Darwin 路线预留 extern/wrapper 或平台分支接口
- [ ] 保持对外 API 名称尽量稳定

### 验证

- [ ] Linux：pthread 相关代码仍可编译
- [ ] Linux：现有 pthread 测试不回归

### 完成标准

- [ ] `lib/libc/pthread.uya` 不再把 Linux 线程实现和公共接口揉在一起
- [ ] Darwin 路线有明确落点

---

## Commit 3：测试降耦与分层

**建议提交名**：`test: split pthread api tests from linux-specific assumptions`

### 目标

- 把 `pthread` 测试从“实现细节绑定”改成“API 能力验证优先”
- 避免 Darwin 桥接路线一上来就被 Linux 实现细节测试卡死

### 修改文件

- [ ] [../tests/test_pthread.uya](../tests/test_pthread.uya)
- [ ] [../tests/test_pthread_cond.uya](../tests/test_pthread_cond.uya)

### 任务清单

- [ ] 区分两类测试：
  - [ ] API 级测试：适合 Darwin 第一阶段恢复
  - [ ] Linux 实现细节测试：后续单独保留/分组
- [ ] 减少测试对内部字段初始化形状的依赖：
  - [ ] `pthread_t`
  - [ ] `pthread_mutex_t`
  - [ ] `pthread_cond_t`
- [ ] 第一阶段优先保留：
  - [ ] `pthread_create/join`
  - [ ] `pthread_mutex_init/lock/unlock`
  - [ ] `pthread_cond_init/signal/broadcast`

### 验证

- [ ] Linux：第一阶段 pthread API 测试仍通过
- [ ] Linux：被降级的实现细节测试有明确分组或标记

### 完成标准

- [ ] Darwin 可以只恢复“API 级最小子集”而不被现有测试形状阻塞

---

## Commit 4：Darwin 最小桥接落位

**建议提交名**：`darwin: bridge minimal pthread api`

### 目标

- 在 macOS 上恢复最小 `pthread` API
- 先跑通线程创建、等待、互斥量、条件变量主路径

### 修改文件

- [ ] [../lib/libc/pthread.uya](../lib/libc/pthread.uya)
- [ ] 必要的 Darwin 声明或封装文件

### 任务清单

- [ ] 落地 Darwin 桥接层：
  - [ ] `pthread_create`
  - [ ] `pthread_join`
  - [ ] `pthread_mutex_init/destroy/lock/unlock`
  - [ ] `pthread_cond_init/destroy/wait/signal/broadcast`
- [ ] 确认返回值、错误码和最小语义与测试对齐
- [ ] 若需要，允许 Darwin 最初只支持最小属性集

### 验证

- [ ] macOS：最小线程创建/等待 smoke
- [ ] macOS：最小 mutex smoke
- [ ] macOS：最小 cond smoke

### 完成标准

- [ ] Darwin 最小 `pthread` API 可用

---

## Commit 5：Darwin pthread 基线收口

**建议提交名**：`darwin: close first pthread baseline`

### 目标

- 在 macOS 上收敛第一版 `pthread` 测试基线
- 为后续是否继续扩展高级子集留下清晰边界

### 修改文件

- [ ] [../lib/libc/pthread.uya](../lib/libc/pthread.uya)
- [ ] [../tests/test_pthread.uya](../tests/test_pthread.uya)
- [ ] [../tests/test_pthread_cond.uya](../tests/test_pthread_cond.uya)

### 任务清单

- [ ] 生成 Darwin 第一版通过/失败/跳过清单
- [ ] 明确 Darwin 第一版已支持的 API 子集
- [ ] 明确仍延后的项目：
  - [ ] `cancel`
  - [ ] `rwlock`
  - [ ] `spinlock`
  - [ ] `yield`
  - [ ] 高级 timed / attr 行为
- [ ] 确认 `pthread` 测试入口独立于 `check-hosted`

### 验证

- [ ] macOS：`test_pthread.uya` 第一版子集通过
- [ ] macOS：`test_pthread_cond.uya` 第一版子集通过

### 完成标准

- [ ] Darwin pthread 基线稳定
- [ ] 后续扩展不再阻塞主迁移路线

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make check`
- [ ] `make check-hosted`
- [ ] pthread 相关测试不回归

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] 最小线程创建/等待
- [ ] 最小 mutex
- [ ] 最小 cond

---

## 阶段结束后应立即进入的下一步

Phase 5 完成后，后续阶段按风险顺序继续推进：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 6：`--nostdlib`
2. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 7：`std.async` / `kqueue`

不建议在 Phase 5 还未收口前直接实现 `async`，否则线程/同步与事件循环问题会交叉污染排查。

