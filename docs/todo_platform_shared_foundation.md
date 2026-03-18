# 多平台共享基础详细待办

本文档细化 [todo_multiplatform_migration.md](todo_multiplatform_migration.md) 中的**共享平台基础**主线，目标是先把 Uya 当前的 Linux-only 宿主/工具链假设收敛成共享模型，再继续 Darwin、Windows 与交叉编译。

适用范围：

- `Makefile`
- `src/compile.sh`
- `src/main.uya`
- `src/codegen/c99/main.uya`
- `tests/run_programs_parallel.sh`
- `tests/run_cross_platform_tests.sh`
- `docs/UYA_BUILD_RUN.md`

---

## 核心目标

- 建立统一的 `host/target` 平台模型
- 建立统一的 `cc_driver` / toolchain 配置入口
- 区分 `hosted` 与 `nostdlib` 的 runtime/link 行为
- 为 Darwin 原生、Windows 原生和交叉编译三条后续主线提供共同底座

---

## 统一模型

共享基础阶段默认冻结如下维度：

- `HOST_OS`
- `HOST_ARCH`
- `TARGET_OS`
- `TARGET_ARCH`
- `TARGET_TRIPLE`
- `RUNTIME_MODE`
- `LINK_MODE`
- `TOOLCHAIN`
- `ZIG`
- `CC`
- `CC_DRIVER`
- `CC_TARGET_FLAGS`

默认策略：

- `HOST_*` 默认来自当前宿主
- `TARGET_*` 默认继承 `HOST_*`
- `RUNTIME_MODE=hosted` 为默认主线
- `RUNTIME_MODE=nostdlib` 仅在显式选择时启用
- `TOOLCHAIN=system` 时，`CC_DRIVER` 默认继承 `CC`
- `TOOLCHAIN=zig` 时，`CC_DRIVER` 默认展开为 `$(ZIG) cc`
- `ZIG` 默认指向 `/home/winger/zig/zig`，可按机器覆写
- `TARGET_TRIPLE` 非空时，优先经由 `CC_TARGET_FLAGS` 或 `-target` 落到外部工具链
- 共享基础、Windows 目标和交叉编译优先推荐 `zig cc`

---

## Linux 截止点与原生平台必做项

### Linux 在共享基础阶段应该做到哪里

共享基础阶段可在 Linux 上完整完成，因为它的职责是抽象和入口统一，而不是验证 Darwin/Windows 平台行为。

### 哪些内容虽可在 Linux 上写代码，但不算平台完成

以下内容不属于共享基础完成标准：

- [ ] Darwin syscall / runtime 行为正确
- [ ] Windows Win32 / PE-COFF 行为正确
- [ ] `--nostdlib` 非 Linux 平台 bring-up 完成
- [ ] IOCP / `kqueue` 后端通过

共享基础只负责把这些后续路线所需的抽象和入口铺好。

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 固定共享平台模型 | 文档、Makefile 注释 | 术语与入口统一 |
| 2 | 顶层构建入口工具链抽象 | `Makefile`、`src/compile.sh` | Linux 构建不回归 |
| 3 | 编译器 `build/run/test` 工具链抽象 | `src/main.uya` | `build/run` 不再硬绑 Linux GCC |
| 4 | 测试入口工具链抽象 | `tests/run_programs_parallel.sh`、`tests/run_cross_platform_tests.sh` | Linux 测试不回归 |
| 5 | 生成 C 的目标平台宏与文档同步 | `src/codegen/c99/main.uya`、文档 | target-aware C99 入口稳定 |

---

## Commit 1：固定共享平台模型

**建议提交名**：`platform: define shared host target model`

### 目标

- 在文档和构建入口中统一 host/target/runtime/link/toolchain 术语

### 修改文件

- [ ] [../docs/todo_multiplatform_migration.md](../docs/todo_multiplatform_migration.md)
- [ ] [../Makefile](../Makefile)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 完成标准

- [ ] 用户可以在同一套术语下理解原生构建、原生目标与交叉编译

---

## Commit 2：顶层构建入口工具链抽象

**建议提交名**：`build: add shared toolchain variables`

### 目标

- 去掉 `Makefile` 和 `src/compile.sh` 中的 `gcc` 硬编码
- 让顶层构建与 compile.sh 共用统一工具链变量

### 修改文件

- [ ] [../Makefile](../Makefile)
- [ ] [../src/compile.sh](../src/compile.sh)

### 任务清单

- [ ] `Makefile` 引入 `CC ?= cc`
- [ ] `Makefile` 引入 `CC_DRIVER`、`CC_TARGET_FLAGS`、`HOST_*`、`TARGET_*`、`RUNTIME_MODE`、`LINK_MODE`
- [ ] `compile.sh` 使用 `CC_DRIVER` 替代直接 `gcc`
- [ ] `compile.sh` 将 hosted 链接与 `--nostdlib` 链接彻底分开
- [ ] 非 Linux `nostdlib` 路径在未实现时给出清晰错误，而不是误走 Linux `_start`

### 验证

- [ ] Linux：`make from-c`
- [ ] Linux：`make uya`
- [ ] Linux：`make uya-hosted`

### 完成标准

- [ ] 顶层构建入口和 `compile.sh` 的工具链抽象已统一

---

## Commit 3：编译器 `build/run/test` 工具链抽象

**建议提交名**：`compiler: remove linux gcc path assumptions`

### 目标

- 清除 `src/main.uya` 中的 Linux GCC 路径硬编码
- 让 `build/run/test` 的链接步骤共享同一套工具链配置

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 将 `link_with_gcc()` 抽象成通用宿主链接入口
- [ ] build/run/test 路径改用 `CC` / `CC_DRIVER` / `CC_TARGET_FLAGS`
- [ ] 非 Linux `nostdlib` 路径先给出明确“未实现”错误
- [ ] 不再依赖 `/usr/lib/gcc/x86_64-linux-gnu/12`

### 验证

- [ ] Linux：`bin/uya build ...`
- [ ] Linux：`bin/uya run ...`

### 完成标准

- [ ] 编译器自身的宿主链接逻辑已与顶层构建抽象对齐

---

## Commit 4：测试入口工具链抽象

**建议提交名**：`tests: unify compiler and linker driver`

### 目标

- 让主测试入口、多文件测试和跨平台脚本都共享相同工具链入口

### 修改文件

- [ ] [../tests/run_programs_parallel.sh](../tests/run_programs_parallel.sh)
- [ ] [../tests/run_cross_platform_tests.sh](../tests/run_cross_platform_tests.sh)

### 任务清单

- [ ] 测试脚本改用 `CC_DRIVER` / `CC_TARGET_FLAGS`
- [ ] 按 `TARGET_OS` 派生可执行文件后缀
- [ ] 修复 `run_cross_platform_tests.sh` 的构建目录变量问题
- [ ] 为平台跳过列表和 hosted profile 预留统一入口

### 验证

- [ ] Linux：`make tests`
- [ ] Linux：`make tests-hosted`

### 完成标准

- [ ] 顶层测试入口不再强绑 `gcc`

---

## Commit 5：生成 C 的目标平台宏与文档同步

**建议提交名**：`codegen: emit target-aware c99 prelude`

### 目标

- 在生成的 C99 代码中提供统一目标平台宏
- 让 `C99-only` 与后续交叉编译具备更稳定的目标平台入口

### 修改文件

- [ ] [../src/codegen/c99/main.uya](../src/codegen/c99/main.uya)
- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)

### 任务清单

- [ ] 生成统一的 target-aware 平台宏
- [ ] 保留现有 `@asm_target` 兼容路径
- [ ] 更新文档，说明当前 `@syscall` 仍未跨出 Linux x86-64，但构建链已具备 target-aware 入口

### 验证

- [ ] Linux：`make check`

### 完成标准

- [ ] 共享基础完成，Darwin / Windows / cross 之后都能站在同一套 build/codegen 语义上推进

