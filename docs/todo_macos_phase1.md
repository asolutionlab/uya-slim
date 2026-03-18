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

**Linux 上可宣称完成项**（真机验收见下表「Commit 5」）：

- [x] `Makefile` 不再把 hosted 路径写死为 `gcc`（`CC` / `CC_DRIVER`）
- [x] `src/compile.sh` 的普通 hosted 编译/链接路径使用 `CC_DRIVER`
- [x] 测试脚本使用 `CC_DRIVER` / `CC_TARGET_FLAGS`（`run_programs_parallel.sh`、`run_cross_platform_tests.sh`）
- [x] 存在 hosted 版自举入口（`uya-hosted` / `b-hosted` / `check-hosted`）
- [x] Darwin：nostdlib 不误走 Linux CRT；`from-c` 在 macOS+Linux nostdlib 备份上明确报错；`macos_hosted_smoke.md` + 测试默认跳过列表
- [x] Linux：`make check` / `make check-hosted` / `make backup` 路径可回归

**仍须在 macOS 真机收口**：Commit 5 验证矩阵（`make uya-hosted`、最小程序等）。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 1 应该做到哪里

在 Phase 1 中，Linux 侧推荐**做到 Commit 4 为止**：

- [x] Commit 1：Makefile 引入 `CC` / `CC_DRIVER` 等
- [x] Commit 2：`compile.sh` hosted 路径改用 `CC_DRIVER`
- [x] Commit 3：新增 hosted 自举目标
- [x] Commit 4：测试脚本改用可配置编译器

### 从哪里开始必须切到 macOS

**Commit 5 开始必须在 macOS 上做主验证**：

- [x] Darwin hosted 脚手架（脚本/文档/报错路径）— **Linux 已写好**
- [ ] macOS：`make from-c`（若未来提供 hosted 备份策略再测；当前 nostdlib 备份在 Mac 上 from-c 会报错，属预期）
- [ ] macOS：`make uya-hosted` / 最小程序 / `--nostdlib` 清晰错误 — **待真机**

### Linux 可以继续做但不能算完成的事项

以下内容 **代码可在 Linux 准备**，**完成**以 macOS 验证为准：

- Darwin 链接在真机上的实际行为
- Darwin hosted smoke 全绿

### 一句话执行规则

- **Commit 1-4**：在 Linux 完成并回归 ✅
- **Commit 5**：macOS 真机收口验证 ⏳

---

## 明确不在本阶段做的事（边界说明）

以下 **本阶段不实施**（转入后续 Phase）：

- 不实现 Darwin `@syscall`
- 不修改 `src/main.uya` 的宿主路径发现（Phase 2）
- 不修改 `lib/libc/syscall.uya`、`lib/syscall/`、`osal`、`pthread` 的 Darwin 语义
- 不实现 Darwin `--nostdlib`、不实现 `kqueue`

---

## 执行前检查（Linux）

- [x] `make check` 或 `make check-hosted`
- [x] `bin/uya` 缺失时 `make from-c`（Linux x86_64 + nostdlib 备份）
- [x] `gcc` 直接调用点已收敛：`Makefile`、`compile.sh`、两测试脚本均以 `CC_DRIVER` 为主

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | Makefile 引入 `CC` 抽象 | `Makefile` | `make from-c` |
| 2 | `compile.sh` hosted 路径 | `src/compile.sh` | `./compile.sh --c99 -e` |
| 3 | hosted 自举目标 | `Makefile` | `make uya-hosted` / `b-hosted` |
| 4 | 测试脚本 | 两 `tests/*.sh` | smoke |
| 5 | Darwin 脚手架 + 真机验收 | `compile.sh`、`Makefile`、文档 | **macOS** |

---

## Commit 1～4（Linux）— 已完成

- Makefile：`CC`、`CC_DRIVER`、`HOST_*`、`TARGET_*`、`RUNTIME_MODE`、`LINK_MODE`、`TOOLCHAIN`、`ZIG`；`from-c` 对 Linux nostdlib 备份用 crti/crtn；`release` 等走 `CC_DRIVER`。
- `compile.sh`：`CC_DRIVER`、`--nostdlib` 传编译器、hosted/nostdlib 分离、自举对比带 `--nostdlib`。
- `uya-hosted` / `b-hosted` / `check-hosted`。
- `run_programs_parallel.sh`：`CC_DRIVER`、macOS 默认跳过列表；`run_cross_platform_tests.sh`：同模型。

验证（Linux）：`make from-c`、`CC=cc`/`CC=gcc`、`make uya-hosted`、`make check-hosted`。

---

## Commit 5：Darwin hosted 分支落位

### 任务清单（Linux 可完成部分）

- [x] `compile.sh`：`TARGET_OS=macos` 与 nostdlib 拒绝误走 Linux
- [x] hosted 在 Darwin 上为普通 `cc … .c -o`
- [x] Makefile `from-c`：macOS + Linux nostdlib 备份时报错；`help` 指向 `macos_hosted_smoke.md`
- [x] 测试脚本 Darwin 跳过列表；`macos_hosted_smoke.md`
- [ ] **macOS 真机**：`uya-hosted`、`hello`、nostdlib 报错路径 — 收口

---

## 建议的最小验证矩阵

### Linux 回归（每个相关提交后）

- [x] `make from-c`
- [x] `make uya-hosted` / `make check-hosted`

### Darwin 首次 bring-up

- [ ] 见 `docs/macos_hosted_smoke.md`

---

## 阶段结束后应立即进入的下一步

1. [todo_macos_migration.md](todo_macos_migration.md) Phase 2：宿主平台抽象
2. Phase 3：`@syscall` / syscall / osal / runtime
3. Phase 4：hosted 自举与主测试基线
