# macOS 迁移 Phase 8 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 8：跨平台验证与文档收口**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做
- 最终迁移验收应如何从“分阶段实现”收口到“可重复执行的命令矩阵与文档矩阵”

适用范围：

- `Makefile`
- `tests/run_programs_parallel.sh`
- `tests/run_cross_platform_tests.sh`
- `tests/verify_proof_optimization.sh`
- `docs/todo_macos_migration.md`
- `docs/todo_mini_to_full.md`
- `docs/todo_std_refactor.md`
- `docs/std_async_design.md`
- `docs/UYA_BUILD_RUN.md`

本阶段核心目标：

- 冻结 Linux / macOS 的最终验收矩阵
- 把 hosted、`pthread`、`--nostdlib`、`std.async` 的验证入口收口成稳定命令
- 明确哪些结果已经通过，哪些仍然 blocked，并在文档中留下真实状态
- 避免“代码看起来都写完了，但没有统一验收入口和最终状态说明”

---

## 默认路线决策

### 推荐默认方案

**推荐把 Phase 8 定义为“验收入口收口 + 结果记账 + 文档同步”**：

- [ ] `make check` 继续作为 Linux `x86_64` 主线全量验证入口
- [ ] macOS hosted 路径使用独立入口，不再被 `--nostdlib` / `pthread` / async 阻塞
- [ ] `pthread`、`--nostdlib`、`std.async` 维持各自独立验证入口
- [ ] 文档必须显式记录“通过 / 未通过 / 阻塞原因”，而不是只保留愿景描述
- [ ] 验收矩阵以真实平台结果为准，不接受“Linux 上推断 Darwin 应该可以”

### 推荐的收口方式

**推荐把验收收口成三层结果**：

- [ ] 平台主线：
  - [ ] Linux `x86_64`
  - [ ] macOS `x86_64`
  - [ ] macOS `arm64`
- [ ] 能力分线：
  - [ ] hosted
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] `std.async` / `kqueue`
- [ ] 文档分线：
  - [ ] 总 TODO
  - [ ] 标准库重构 TODO
  - [ ] async 设计文档
  - [ ] 构建/运行文档

理由：

- [ ] 前 1-7 阶段已经把实现工作拆开，Phase 8 的职责不再是继续扩功能，而是把结果真正汇总
- [ ] 若没有独立结果记账，后续很难判断“是没做完、做完未验证，还是已经通过”
- [ ] 若把所有内容重新塞回一个总命令，后续会再次被高风险子系统拖住

### 长期可选方案

**长期可选：继续把验收矩阵推进到 CI / 自动化矩阵**

- [ ] 后续可再把各入口接入 CI 或远程构建节点
- [ ] 该目标不应阻塞当前文档收口与人工验收矩阵落地

---

## 本阶段完成定义

满足以下条件即可视为 Phase 8 完成：

- [ ] Linux `x86_64` 的主线验收入口与结果明确
- [ ] macOS `x86_64` hosted 验收入口与结果明确
- [ ] macOS `arm64` hosted 验收入口与结果明确
- [ ] `pthread` / `--nostdlib` / `std.async` 各自拥有独立入口与独立状态
- [ ] `todo_macos_migration.md`、`todo_mini_to_full.md`、`todo_std_refactor.md`、`std_async_design.md` 的状态描述一致
- [ ] 文档中对未完成项写明 blocked 原因，而不是模糊留空

---

## 明确不在本阶段做的事

- [ ] 不继续扩展新的平台目标
- [ ] 不在 Phase 8 重新设计 `pthread` / `--nostdlib` / async 的实现方案
- [ ] 不把 Linux-only 测试强行改造成跨平台测试
- [ ] 不要求一开始就把所有 macOS 子系统重新并回单一 `make check`

若某个改动需要重开实现路线或新增大规模平台功能，说明已经越过 Phase 8 边界，应回到前面阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 8 应该做到哪里

在 Phase 8 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：冻结最终验收矩阵与完成定义
- [ ] Commit 2：收口命令矩阵与验证入口命名
- [ ] Commit 3：准备结果记账格式与文档同步骨架

做到这里，Linux 的主要职责已经完成：验收规则、命令入口和文档框架已经准备好。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为此时要填写真实平台结果，而不是继续写结构：

- [ ] macOS `x86_64` hosted 主线验证
- [ ] macOS `x86_64` 的 `pthread` / `--nostdlib` / async 独立验证
- [ ] macOS `arm64` hosted 主线验证
- [ ] macOS `arm64` 的 `pthread` / `--nostdlib` / async 独立验证

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好文档，也**不能在 Linux 上宣布完成**：

- [ ] macOS `x86_64` 验收通过结论
- [ ] macOS `arm64` 验收通过结论
- [ ] Darwin `pthread` 通过结论
- [ ] Darwin `--nostdlib` 通过结论
- [ ] Darwin async / `kqueue` 通过结论

这些内容只能算“表格和模板已准备”，真正完成必须以 macOS 真机结果为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 填真实结果并完成最终收口

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase4.md](todo_macos_phase4.md) 的 hosted 基线
- [ ] 先完成 [todo_macos_phase5.md](todo_macos_phase5.md) 的 `pthread` 路线
- [ ] 先完成 [todo_macos_phase6.md](todo_macos_phase6.md) 的 `--nostdlib` 路线
- [ ] 先完成 [todo_macos_phase7.md](todo_macos_phase7.md) 的 async / `kqueue` 路线
- [ ] Linux 上执行：
  - [ ] `make check`
- [ ] 记录当前收口前的现实状态：
  - [ ] `Makefile` 当前仍主要暴露 Linux `--nostdlib` 主线入口
  - [ ] `uya-hosted` / `b-hosted` / `tests-hosted` / `check-hosted` 若未真正落地，不应提前开始 Phase 8 验收
  - [ ] `tests/run_cross_platform_tests.sh` 当前更偏向 `@asm` 跨平台脚本，不等于完整 macOS 迁移验收脚本
  - [ ] 若 `tests/run_cross_platform_tests.sh` 继续保留，其职责必须在 Phase 8 中重新定义
  - [ ] 文档中若存在“计划里说有命令、代码里还没有命令”的情况，应以实际入口为准修正文档

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 冻结最终验收矩阵与完成定义 | 迁移文档、总 TODO | 不再模糊“什么算迁移完成” |
| 2 | 收口命令矩阵与脚本职责 | `Makefile`、测试脚本、运行文档 | 命令名与职责一致 |
| 3 | 准备结果记账格式与文档同步骨架 | `todo_mini_to_full`、`todo_std_refactor`、设计文档 | 文档收口结构稳定 |
| 4 | macOS `x86_64` 验收与结果入账 | 命令入口、主文档 | `x86_64` 真实结果 |
| 5 | macOS `arm64` 验收与最终文档收口 | 同上 | `arm64` 真实结果 |

---

## Commit 1：冻结最终验收矩阵与完成定义

**建议提交名**：`docs: freeze macos migration acceptance matrix`

### 目标

- 明确最终应该验收哪些平台、哪些能力、哪些命令
- 统一“完成”的定义

### 修改文件

- [ ] [../docs/todo_macos_migration.md](../docs/todo_macos_migration.md)
- [ ] [../docs/todo_mini_to_full.md](../docs/todo_mini_to_full.md)

### 任务清单

- [ ] 冻结平台矩阵：
  - [ ] Linux `x86_64`
  - [ ] macOS `x86_64`
  - [ ] macOS `arm64`
- [ ] 冻结能力矩阵：
  - [ ] hosted
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] `std.async` / `kqueue`
- [ ] 明确最终文档里必须记录的状态：
  - [ ] 通过
  - [ ] 未通过
  - [ ] blocked

### 验证

- [ ] 各阶段文档的完成标准与主迁移文档不冲突

### 完成标准

- [ ] “迁移完成” 的含义已经冻结，不再因后续讨论反复变化

---

## Commit 2：收口命令矩阵与脚本职责

**建议提交名**：`build: align migration verification entrypoints`

### 目标

- 把最终要给人执行的命令入口收口成稳定名字
- 把脚本职责从“计划中的名字”对齐到“实际存在或即将存在的入口”

### 修改文件

- [ ] [../Makefile](../Makefile)
- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] [../tests/run_cross_platform_tests.sh](../tests/run_cross_platform_tests.sh)
- [ ] [../tests/verify_proof_optimization.sh](../tests/verify_proof_optimization.sh)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 任务清单

- [ ] 冻结 Linux 主线入口：
  - [ ] `make check`
- [ ] 冻结 macOS hosted 主线入口：
  - [ ] `make from-c`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
  - [ ] `make tests-hosted`
  - [ ] `make check-hosted`
- [ ] 冻结 macOS 独立能力入口：
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] async / `kqueue`
- [ ] 重新定义 `run_cross_platform_tests.sh` 的职责：
  - [ ] 若继续保留，则明确它是 `@asm` / 平台检测专项脚本
  - [ ] 不把它误写成“完整 macOS 迁移验收脚本”

### 验证

- [ ] 文档命令名与实际入口一致
- [ ] 不再出现“前一个阶段写的是一种命名，最终使用的是另一种命名”

### 完成标准

- [ ] 用户可以根据文档直接找到最终验证入口

---

## Commit 3：准备结果记账格式与文档同步骨架

**建议提交名**：`docs: prepare migration status ledger`

### 目标

- 为最终真实验收结果准备统一记录方式
- 让后续 macOS 验证结果能直接回填，而不是散落在各个文档里

### 修改文件

- [ ] [../docs/todo_macos_migration.md](../docs/todo_macos_migration.md)
- [ ] [../docs/todo_mini_to_full.md](../docs/todo_mini_to_full.md)
- [ ] [../docs/todo_std_refactor.md](../docs/todo_std_refactor.md)
- [ ] [../docs/std_async_design.md](../docs/std_async_design.md)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 任务清单

- [ ] 约定最终记录格式：
  - [ ] 平台
  - [ ] 能力
  - [ ] 验证命令
  - [ ] 当前状态
  - [ ] 阻塞原因或备注
- [ ] 统一总 TODO、迁移 TODO、设计文档里的术语：
  - [ ] hosted
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] `std.async` / `kqueue`
- [ ] 为未完成项预留明确说明，而不是空白占位

### 验证

- [ ] 文档之间不再互相冲突

### 完成标准

- [ ] 文档已经具备回填真实平台结果的稳定骨架

---

## Commit 4：macOS `x86_64` 验收与结果入账

**建议提交名**：`darwin: record x86_64 migration results`

### 目标

- 在 macOS `x86_64` 上完成真实验收
- 把结果正式写回命令矩阵和文档矩阵

### 修改文件

- [ ] [../Makefile](../Makefile) 或对应验证脚本
- [ ] [../docs/todo_macos_migration.md](../docs/todo_macos_migration.md)
- [ ] [../docs/todo_mini_to_full.md](../docs/todo_mini_to_full.md)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 任务清单

- [ ] 验证 macOS `x86_64` hosted：
  - [ ] `make from-c`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
  - [ ] `make tests-hosted`
  - [ ] `make check-hosted`
- [ ] 验证 macOS `x86_64` 子系统：
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] async / `kqueue`
- [ ] 把每项结果写回文档：
  - [ ] pass
  - [ ] fail
  - [ ] blocked

### 验证

- [ ] 文档中记录的 `x86_64` 状态与实际命令结果一致

### 完成标准

- [ ] macOS `x86_64` 的最终状态已可被他人复核

---

## Commit 5：macOS `arm64` 验收与最终文档收口

**建议提交名**：`darwin: record arm64 migration results`

### 目标

- 在 macOS `arm64` 上完成真实验收
- 把全部文档收口到最终一致状态

### 修改文件

- [ ] [../Makefile](../Makefile) 或对应验证脚本
- [ ] [../docs/todo_macos_migration.md](../docs/todo_macos_migration.md)
- [ ] [../docs/todo_mini_to_full.md](../docs/todo_mini_to_full.md)
- [ ] [../docs/todo_std_refactor.md](../docs/todo_std_refactor.md)
- [ ] [../docs/std_async_design.md](../docs/std_async_design.md)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 任务清单

- [ ] 验证 macOS `arm64` hosted：
  - [ ] `make from-c`
  - [ ] `make uya-hosted`
  - [ ] `make b-hosted`
  - [ ] `make tests-hosted`
  - [ ] `make check-hosted`
- [ ] 验证 macOS `arm64` 子系统：
  - [ ] `pthread`
  - [ ] `--nostdlib`
  - [ ] async / `kqueue`
- [ ] 最终同步所有收口文档：
  - [ ] 总 TODO
  - [ ] 标准库重构 TODO
  - [ ] async 设计文档
  - [ ] 构建/运行文档

### 验证

- [ ] 文档中记录的 `arm64` 状态与实际命令结果一致
- [ ] 全部收口文档对平台状态描述一致

### 完成标准

- [ ] macOS 迁移的最终验收状态已经形成一套统一、可重复执行、可复核的记录

---

## 建议的最小验证矩阵

### Linux 最终基线

- [ ] `make check`

### macOS hosted 基线

- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] `make b-hosted`
- [ ] `make tests-hosted`
- [ ] `make check-hosted`

### macOS 独立子系统基线

- [ ] `pthread` 独立入口
- [ ] `--nostdlib` 独立入口
- [ ] async / `kqueue` 独立入口

### 文档最终一致性基线

- [ ] `todo_macos_migration.md`
- [ ] `todo_mini_to_full.md`
- [ ] `todo_std_refactor.md`
- [ ] `std_async_design.md`
- [ ] `UYA_BUILD_RUN.md`

---

## 阶段结束后应立即进入的下一步

Phase 8 完成后，macOS 迁移主线即可视为进入“维护与增量优化”阶段：

1. 对未通过但已有明确 blocker 的子项单独开后续任务
2. 视条件把验收矩阵接入自动化环境

若 Phase 8 最终收口的结果是“部分子系统仍 blocked，但状态和原因清晰可复核”，这仍然比“所有文档都写着支持中，但没人知道现在到底能跑什么”更可接受。

