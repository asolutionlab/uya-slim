# macOS 迁移 Phase 4 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 4：hosted 自举与主测试基线**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做

适用范围：

- `Makefile`
- `tests/run_programs_parallel.sh`
- `tests/verify_proof_optimization.sh`
- hosted 自举与主测试相关的执行入口

本阶段核心目标：

- 为 macOS 建立不依赖 `--nostdlib` 的正式自举入口
- 为 macOS 建立第一版 hosted 主测试基线
- 把 `run_programs_parallel.sh` 从“全量 Linux 假设”变成“可分层、可跳过、可收敛”的测试入口
- 为后续 `pthread`、`--nostdlib`、`async` 让路，而不是被它们阻塞

---

## 本阶段完成定义

满足以下条件即可视为 Phase 4 完成：

- [ ] `Makefile` 拥有 hosted 版正式入口，至少包括：
  - [ ] `uya-hosted`
  - [ ] `b-hosted`
  - [ ] `tests-hosted`
  - [ ] `check-hosted`
- [ ] `tests/run_programs_parallel.sh` 支持平台分层与跳过机制
- [ ] 第一版 macOS hosted 主测试集被定义清楚
- [ ] macOS 上可稳定完成：
  - [ ] `make from-c`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
  - [ ] `make tests-hosted`
- [ ] `check-hosted` 的范围明确，不再被 `pthread` / `async` / `--nostdlib` 阻塞
- [ ] Linux 现有验证路径不回归

---

## 明确不在本阶段做的事

- [ ] 不迁移 `pthread`
- [ ] 不实现 Darwin `--nostdlib`
- [ ] 不恢复 async / `kqueue`
- [ ] 不要求 macOS 在此阶段跑通所有测试
- [ ] 不要求此阶段解决 Linux-only 的 `epoll`、`pipe2`、futex 语义

若某个改动需要依赖这些内容，说明已经越过 Phase 4 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 4 应该做到哪里

在 Phase 4 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：新增 hosted 验证入口
- [ ] Commit 2：测试分层与跳过列表机制
- [ ] Commit 3：定义第一版 hosted 测试范围与多文件测试策略

做到这里，Linux 的主要职责已经完成：命令入口、脚本结构、测试分层和第一版 baseline 都已成型。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时需要真实确认 Darwin hosted 路径是否可用：

- [ ] Darwin 下 `make from-c`
- [ ] Darwin 下 `make uya-hosted`
- [ ] Darwin 下 `make b-hosted`
- [ ] Darwin 下 `make tests-hosted`
- [ ] Darwin 下第一版主测试集的实际通过/跳过/失败清单

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin 的 skip 列表
- [ ] Darwin 的主测试集准入范围
- [ ] Darwin 的 hosted 自举通过结论
- [ ] Darwin 的 `check-hosted` 闭环

这些内容只能算“脚本与结构已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 做实现收口和验收

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase1.md](todo_macos_phase1.md)、[todo_macos_phase2.md](todo_macos_phase2.md)、[todo_macos_phase3.md](todo_macos_phase3.md) 的核心目标
- [ ] Linux 上执行：
  - [ ] `make check`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
- [ ] 记录当前 Phase 4 的显式阻塞点：
  - [ ] `Makefile` 中 `b` / `check` 仍绑定 `--nostdlib`
  - [ ] `tests/run_programs_parallel.sh` 仍有 `gcc` / 链接假设
  - [ ] `tests/run_programs_parallel.sh` 的 `SKIP_TESTS` 为空
  - [ ] `tests/run_programs_parallel.sh` 仍调用不存在的 `run_programs.sh`

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 新增 hosted 验证目标 | `Makefile` | Linux hosted 入口可执行 |
| 2 | 测试脚本支持分层与跳过 | `tests/run_programs_parallel.sh` | Linux 脚本不回归 |
| 3 | 定义第一版 hosted baseline | `Makefile`、`tests/run_programs_parallel.sh` | Linux dry-run 成立 |
| 4 | macOS hosted smoke 与自举基线 | `Makefile`、测试脚本 | macOS `from-c/uya-hosted/b-hosted` |
| 5 | macOS 主测试基线收口 | `Makefile`、测试脚本、验证脚本 | macOS `tests-hosted/check-hosted` |

---

## Commit 1：新增 hosted 验证目标

**建议提交名**：`build: add hosted validation targets`

### 目标

- 正式把 hosted 路径从现有 `uya / b / check` 里拆出来
- 让 Phase 4 可以不依赖 `--nostdlib` 自举路径推进

### 修改文件

- [ ] [../Makefile](../Makefile)

### 任务清单

- [ ] 新增 `tests-hosted`
- [ ] 新增 `check-hosted`
- [ ] 若 Phase 1 尚未落地，则补齐：
  - [ ] `uya-hosted`
  - [ ] `b-hosted`
- [ ] 明确 hosted 目标链路：
  - [ ] `uya-hosted`：普通链接构建编译器
  - [ ] `b-hosted`：普通链接自举对比
  - [ ] `tests-hosted`：运行第一版 hosted 主测试集
  - [ ] `check-hosted`：聚合 hosted 自举和 hosted 测试
- [ ] 保持现有 `uya / b / check` 不变，避免立即破坏 Linux 原流程

### 验证

- [ ] Linux：`make uya-hosted`
- [ ] Linux：`make b-hosted`
- [ ] Linux：`make tests-hosted`

### 完成标准

- [ ] hosted 验证路径成为正式入口
- [ ] 后续 macOS baseline 可以不经过 `--nostdlib`

---

## Commit 2：测试脚本支持分层与跳过

**建议提交名**：`test: add hosted tiers and skip lists`

### 目标

- 让 `run_programs_parallel.sh` 支持“第一版 Darwin 可运行子集”
- 避免 Linux-only 测试阻塞 macOS baseline

### 修改文件

- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)

### 任务清单

- [ ] 增加平台识别逻辑
- [ ] 增加分层概念：
  - [ ] 通用测试
  - [ ] Linux-only
  - [ ] Darwin-ready
  - [ ] 后续恢复的高风险测试
- [ ] 建立 skip 列表结构：
  - [ ] `SKIP_TESTS_LINUX`
  - [ ] `SKIP_TESTS_DARWIN`
  - [ ] 或等价机制
- [ ] 至少先把以下从 Darwin 第一版主线中排除：
  - [ ] `test_pthread.uya`
  - [ ] `test_pthread_cond.uya`
  - [ ] `test_async_fd.uya`
  - [ ] `test_std_async_event.uya`
  - [ ] `test_epoll_syscall.uya`
  - [ ] 其他直接写死 Linux syscall 号的测试

### 验证

- [ ] Linux：无 skip 时不回归
- [ ] Linux：带 skip 结构后结果统计仍正确

### 完成标准

- [ ] 测试脚本具备 Darwin baseline 的技术能力
- [ ] 高风险测试可以被显式延后，而不是随机失败

---

## Commit 3：定义第一版 hosted baseline

**建议提交名**：`test: define first hosted baseline scope`

### 目标

- 给 `tests-hosted` 和 `check-hosted` 定义一个现实可执行的第一版范围
- 处理多文件测试入口缺失的问题，避免 baseline 假通过

### 修改文件

- [ ] [../Makefile](../Makefile)
- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] [../tests/verify_proof_optimization.sh](../tests/verify_proof_optimization.sh)

### 任务清单

- [ ] 明确 `tests-hosted` 第一版范围：
  - [ ] 语言核心
  - [ ] 基础标准库
  - [ ] 非 `pthread`
  - [ ] 非 async
  - [ ] 非 `--nostdlib`
- [ ] 明确 `check-hosted` 第一版范围：
  - [ ] `b-hosted`
  - [ ] `tests-hosted`
  - [ ] 是否纳入 `verify_proof_optimization.sh`
- [ ] 处理多文件测试问题：
  - [ ] 要么补回 `run_programs.sh` 的等价入口
  - [ ] 要么在第一版 hosted baseline 中显式排除 `multifile` / `cross_deps`
- [ ] 让 baseline 的“未纳入项”被文档化，而不是隐式漏掉

### 验证

- [ ] Linux：`make tests-hosted`
- [ ] Linux：`make check-hosted`

### 完成标准

- [ ] 第一版 hosted baseline 有清晰边界
- [ ] 多文件测试不再处于“脚本会调用不存在文件”的悬空状态

---

## Commit 4：macOS hosted smoke 与自举基线

**建议提交名**：`darwin: establish hosted smoke and bootstrap baseline`

### 目标

- 在 macOS 真机上第一次跑通 hosted 主线
- 形成 Darwin 上的最小“可生成编译器、可自举”的结论

### 修改文件

- [ ] [../Makefile](../Makefile)
- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] 视 smoke 暴露问题调整前置阶段文件

### 任务清单

- [ ] macOS 上执行：
  - [ ] `make from-c`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
- [ ] 记录第一次真实失败点：
  - [ ] 构建失败
  - [ ] 自举失败
  - [ ] 链接失败
  - [ ] 运行失败
- [ ] 修正 Phase 1-3 遗留的 hosted 路径问题

### 验证

- [ ] macOS：`make from-c`
- [ ] macOS：`make uya-hosted`
- [ ] macOS：`make b-hosted`

### 完成标准

- [ ] macOS hosted smoke 成立
- [ ] macOS hosted 自举对比成立

---

## Commit 5：macOS 主测试基线收口

**建议提交名**：`darwin: close first hosted test baseline`

### 目标

- 在 macOS 上收敛第一版主测试集
- 让 `tests-hosted` / `check-hosted` 成为可重复运行的实际入口

### 修改文件

- [ ] [../Makefile](../Makefile)
- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] [../tests/verify_proof_optimization.sh](../tests/verify_proof_optimization.sh)

### 任务清单

- [ ] 生成 Darwin 第一版通过/失败/跳过清单
- [ ] 收敛 Darwin skip 列表
- [ ] 确认 `tests-hosted` 输出稳定
- [ ] 确认 `check-hosted` 的组成：
  - [ ] 是否包含 proof optimization
  - [ ] 是否暂不包含多文件测试
- [ ] 在文档中记下第一版 baseline 的显式范围

### 验证

- [ ] macOS：`make tests-hosted`
- [ ] macOS：`make check-hosted`

### 完成标准

- [ ] Darwin hosted 主测试基线稳定
- [ ] 后续 `pthread` / `--nostdlib` / `async` 可以在不破坏 baseline 的前提下独立推进

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] `make b-hosted`
- [ ] 选择 1 个最小测试 smoke

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] `make b-hosted`
- [ ] `make tests-hosted`

---

## 阶段结束后应立即进入的下一步

Phase 4 完成后，后续阶段应按风险顺序推进：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 5：`pthread`
2. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 6：`--nostdlib`
3. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 7：`std.async` / `kqueue`

此时不建议再回头重做 hosted baseline；后续阶段应以不破坏 `check-hosted` 为前提推进。

