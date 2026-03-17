# macOS 迁移 Phase 1 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 1：构建链平台化**，目标是把这一阶段拆到“可按提交推进”的粒度。

适用范围：

- `Makefile`
- `src/compile.sh`
- `tests/run_programs_parallel.sh`
- `tests/run_cross_platform_tests.sh`

本阶段核心目标：

- 去掉 hosted 构建路径对 `gcc` 的硬依赖
- 让普通 hosted 编译/链接路径可配置为 `cc`
- 为 Darwin hosted bring-up 打基础
- 不提前卷入 `@syscall`、`osal`、`pthread`、`async`、`--nostdlib` 深水区

---

## 本阶段完成定义

满足以下条件即可视为 Phase 1 完成：

- [ ] `Makefile` 不再把 hosted 路径写死为 `gcc`
- [ ] `src/compile.sh` 的普通 hosted 编译/链接路径改为使用 `CC`
- [ ] 测试脚本改为使用 `CC`
- [ ] 存在 hosted 版自举入口，不依赖 `--nostdlib`
- [ ] Darwin hosted 路径具备最小分支和清晰报错
- [ ] Linux 现有 hosted 行为不回归

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 1 应该做到哪里

在 Phase 1 中，Linux 侧推荐**做到 Commit 4 为止**：

- [ ] Commit 1：Makefile 引入 `CC`
- [ ] Commit 2：`compile.sh` 的 hosted 路径改用 `CC`
- [ ] Commit 3：新增 hosted 自举目标
- [ ] Commit 4：测试脚本改用 `CC`

做到这里，Linux 的主要职责已经完成：构建链抽象、hosted 主线分离、脚本去 `gcc` 绑定。

### 从哪里开始必须切到 macOS

**Commit 5 开始必须在 macOS 上做主验证**，因为这一提交的目标就是让 Darwin hosted 路径真正落地：

- [ ] Darwin hosted 分支落位
- [ ] Darwin 下 `make from-c`
- [ ] Darwin 下 `make uya-hosted`
- [ ] Darwin 下最小程序编译与运行

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin 条件分支
- [ ] Darwin 链接参数
- [ ] Darwin 报错路径
- [ ] Darwin hosted smoke 命令

这些内容只能算“代码已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-4**：可以在 Linux 上完成并回归
- **Commit 5**：必须切到 macOS 做实现收口和验收

---

## 明确不在本阶段做的事

- [ ] 不实现 Darwin `@syscall`
- [ ] 不修改 `src/main.uya` 的宿主路径发现
- [ ] 不修改 `lib/libc/syscall.uya`
- [ ] 不修改 `lib/syscall/`
- [ ] 不迁移 `osal`
- [ ] 不迁移 `pthread`
- [ ] 不实现 Darwin `--nostdlib`
- [ ] 不实现 `kqueue`

若某个改动需要触碰上述内容，说明已经越过 Phase 1 边界，应回退到后续阶段处理。

---

## 执行前检查

- [ ] 先在 Linux 执行 `make check`
- [ ] 若 `bin/uya` 不存在，先执行 `make from-c`
- [ ] 记录当前 `gcc` 直接调用点：
  - [ ] `Makefile`
  - [ ] `src/compile.sh`
  - [ ] `tests/run_programs_parallel.sh`
  - [ ] `tests/run_cross_platform_tests.sh`

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | Makefile 引入 `CC` 抽象 | `Makefile` | `make from-c` |
| 2 | `compile.sh` hosted 路径改用 `CC` | `src/compile.sh` | `./compile.sh --c99 -e` |
| 3 | 新增 hosted 自举目标 | `Makefile` | `make uya-hosted` / `make b-hosted` |
| 4 | 测试脚本改用 `CC` | `tests/run_programs_parallel.sh`、`tests/run_cross_platform_tests.sh` | 单文件测试 smoke |
| 5 | Darwin hosted 分支落位 | `src/compile.sh`、`Makefile` | macOS smoke |

---

## Commit 1：Makefile 引入 `CC` 抽象

**建议提交名**：`build: add configurable host compiler in Makefile`

### 目标

- 先把顶层构建入口从 `gcc` 绑定解开
- 仅处理“明显属于 hosted 路径”的调用
- 尽量不改变现有目标语义

### 修改文件

- [ ] [../Makefile](../Makefile)

### 任务清单

- [ ] 新增 `CC ?= cc`
- [ ] 审核 `Makefile` 中每个 `gcc` 调用点，按两类处理：
  - [ ] hosted 路径：改用 `$(CC)`
  - [ ] `--nostdlib` / Linux-only 路径：暂不改语义，只为后续留注释
- [ ] 至少处理以下 hosted 场景：
  - [ ] `from-c`
  - [ ] `uya-std`
  - [ ] `release`
- [ ] 在注释中说明：
  - [ ] hosted 构建优先通过 `CC`
  - [ ] `uya` / `b` / `check` 仍保留现状，后续再拆 hosted 版目标

### 验证

- [ ] Linux：`make from-c`
- [ ] Linux：`CC=cc make from-c`
- [ ] Linux：`CC=gcc make from-c`

### 完成标准

- [ ] Makefile hosted 路径不再强依赖 `gcc`
- [ ] Linux 行为不回归
- [ ] `uya` / `b` / `check` 暂不被破坏

---

## Commit 2：`compile.sh` hosted 路径改用 `CC`

**建议提交名**：`build: use CC in hosted compile.sh path`

### 目标

- 把 `src/compile.sh` 的普通编译/链接路径改为使用可配置编译器
- 暂时不改 `--nostdlib` 的平台语义

### 修改文件

- [ ] [../src/compile.sh](../src/compile.sh)

### 任务清单

- [ ] 引入 `CC_CMD="${CC:-cc}"` 或等价变量
- [ ] 替换以下 hosted 路径中的 `gcc`：
  - [ ] 从 `backup/uya.c` 恢复编译器
  - [ ] 普通 `-e` 链接路径
  - [ ] 非 `--nostdlib` 的生成/链接命令
- [ ] 暂时保留 `--nostdlib` 路径的 Linux-only 逻辑，但补充注释：
  - [ ] 当前仍是 Linux 特化
  - [ ] Darwin 在 Phase 6 单独处理
- [ ] 如有需要，抽取一个“生成 hosted link command”的辅助块，避免后续 Darwin 分支继续复制逻辑

### 验证

- [ ] Linux：`cd src && CC=cc ./compile.sh --c99 -e`
- [ ] Linux：`cd src && CC=cc ./compile.sh --c99`
- [ ] Linux：确认普通 `-e` 仍可生成可执行文件

### 完成标准

- [ ] hosted 路径统一通过 `CC` 链接
- [ ] `--nostdlib` 路径仍保持原行为
- [ ] 没有把 Darwin 逻辑提前混进 `_start` 分支

---

## Commit 3：新增 hosted 自举目标

**建议提交名**：`build: add hosted bootstrap targets`

### 目标

- 为后续 macOS bring-up 提供正式的 hosted 验证入口
- 避免现有 `b` / `check` 始终强绑 `--nostdlib`

### 修改文件

- [ ] [../Makefile](../Makefile)

### 任务清单

- [ ] 新增 `uya-hosted`
- [ ] 新增 `b-hosted`
- [ ] 新增 `check-hosted`
- [ ] 明确 hosted 目标语义：
  - [ ] `uya-hosted`：普通链接构建编译器
  - [ ] `b-hosted`：普通链接自举对比
  - [ ] `check-hosted`：普通链接测试验证
- [ ] 保持现有目标不变：
  - [ ] `uya`
  - [ ] `b`
  - [ ] `check`
- [ ] 在帮助信息中加入 hosted 目标说明

### 验证

- [ ] Linux：`make uya-hosted`
- [ ] Linux：`make b-hosted`
- [ ] Linux：`make check-hosted`

### 完成标准

- [ ] hosted 自举路径成为正式入口
- [ ] 后续 macOS bring-up 可以不经过 `--nostdlib`

---

## Commit 4：测试脚本改用 `CC`

**建议提交名**：`test: make scripts use configurable compiler`

### 目标

- 去掉测试脚本对 `gcc` 的硬依赖
- 为 Darwin 跳过列表和平台分组预留结构

### 修改文件

- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] [../tests/run_cross_platform_tests.sh](../tests/run_cross_platform_tests.sh)

### 任务清单

- [ ] `run_programs_parallel.sh`
  - [ ] 引入 `CC=${CC:-cc}`
  - [ ] 所有链接调用改用 `$CC`
  - [ ] 预留 Darwin 跳过列表变量
  - [ ] 预留平台检测辅助函数
- [ ] `run_cross_platform_tests.sh`
  - [ ] 引入 `CC=${CC:-cc}`
  - [ ] 修复现有变量错误
  - [ ] 使用统一平台检测结果进行编译

### 验证

- [ ] Linux：运行一个简单单文件测试
- [ ] Linux：运行一个简单目录测试或 smoke 测试
- [ ] Linux：`CC=cc` 与 `CC=gcc` 都能工作

### 完成标准

- [ ] 测试脚本不再把 `gcc` 作为唯一工具链
- [ ] Darwin 平台测试分组有明确落点

---

## Commit 5：Darwin hosted 分支落位

**建议提交名**：`build: add darwin hosted path scaffold`

### 目标

- 在不实现 Darwin `--nostdlib` 的前提下，让 hosted 路径能清晰进入 macOS smoke
- 对暂不支持的路径给出明确错误，而不是误走 Linux 逻辑

### 修改文件

- [ ] [../src/compile.sh](../src/compile.sh)
- [ ] [../Makefile](../Makefile)

### 任务清单

- [ ] 在 `compile.sh` 中增加 Darwin 检测
- [ ] hosted 链接路径按 Darwin 分支选择参数
- [ ] `--nostdlib` 在 Darwin 上先明确报“不支持/后续阶段实现”，避免误用 Linux `_start`
- [ ] 在 Makefile 或帮助信息中补充说明：
  - [ ] macOS 当前仅保证 hosted 路径
  - [ ] `--nostdlib` 需要进入 Phase 6

### 验证

- [ ] macOS：`make from-c`
- [ ] macOS：`make uya-hosted`
- [ ] macOS：最小 hello world hosted 编译运行
- [ ] macOS：Darwin 下调用 `--nostdlib` 时得到清晰错误

### 完成标准

- [ ] Darwin hosted path 能进入 smoke 验证
- [ ] Darwin 不会误走 Linux `_start` / CRT 路径

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make from-c`
- [ ] `make uya-hosted`（从 Commit 3 开始）
- [ ] 选择 1 个简单测试文件跑通

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 5 开始执行
- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] 编译一个最小程序
- [ ] 运行最小程序

---

## 阶段结束后应立即进入的下一步

Phase 1 完成后，必须立刻进入以下主线，不建议先碰 `--nostdlib`：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 2：宿主平台抽象
2. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 3：`@syscall` / `syscall` / `osal` / runtime
3. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 4：hosted 自举与主测试基线

