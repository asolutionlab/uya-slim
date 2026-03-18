# 多平台共享基础详细待办

本文档细化 [todo_multiplatform_migration.md](todo_multiplatform_migration.md) 中的**共享平台基础**主线。

适用范围：`Makefile`、`src/compile.sh`、`src/main.uya`、`src/codegen/c99/main.uya`、测试脚本、`docs/UYA_BUILD_RUN.md`。

---

## 核心目标

- 统一的 `host/target`、`cc_driver`、`RUNTIME_MODE`（hosted / nostdlib）
- Darwin / Windows / 交叉编译 后续共用的构建语义

---

## Linux 上共享基础进度（文档同步）

| Commit | 内容 | Linux 状态 |
|--------|------|------------|
| 1 | 术语与 `HOST_*`/`TARGET_*`/`CC_DRIVER` 等 | [x] Makefile、`UYA_BUILD_RUN.md`、多平台文档已对齐 |
| 2 | 顶层构建 + `compile.sh` 去 `gcc`、nostdlib 分路径 | [x] |
| 3 | `main.uya` build/run/test 链接 | [x] `link_with_toolchain()` + `CC`/`CC_DRIVER`/`CC_TARGET_FLAGS`/`TARGET_OS`/`TARGET_ARCH`，无 `/usr/lib/gcc/.../12` 硬编码 |
| 4 | 测试脚本 `CC_DRIVER` | [x] `run_programs_parallel.sh`、`run_cross_platform_tests.sh` |
| 5 | 生成 C 的 target 宏 | [x] `UYA_TARGET_OS_*`、`UYA_TARGET_ARCH_*` 与 `@asm_target` 并存（`codegen/c99/main.uya`） |

**仍属后续 Phase（非共享基础「完成」标准）**：Darwin/Windows 运行时行为、非 Linux nostdlib、IOCP/kqueue。

---

## 统一模型（摘要）

`HOST_OS`、`HOST_ARCH`、`TARGET_OS`、`TARGET_ARCH`、`TARGET_TRIPLE`、`RUNTIME_MODE`、`LINK_MODE`、`TOOLCHAIN`、`ZIG`、`CC`、`CC_DRIVER`、`CC_TARGET_FLAGS`。

默认：`RUNTIME_MODE=hosted`；`TOOLCHAIN=system` 时 `CC_DRIVER` 继承 `CC`；`TOOLCHAIN=zig` 时为 `$(ZIG) cc`。

---

## 详细提交说明（归档）

以下为原始拆分，**Commit 1～5 在 Linux 侧已按上表落实**；若需扩平台行为，在 Darwin/Windows 专档继续跟踪。

### Commit 1：固定共享平台模型

- [x] `todo_multiplatform_migration.md`、`Makefile` 注释、`UYA_BUILD_RUN.md`

### Commit 2：顶层构建入口

- [x] `CC ?= cc`、`CC_DRIVER`、`HOST_*`、`TARGET_*`、`compile.sh` 与 nostdlib 分路径、非 Linux nostdlib 报错

### Commit 3：编译器 `build/run/test`

- [x] `link_with_toolchain`、环境变量驱动的宿主链接

### Commit 4：测试入口

- [x] 两测试脚本统一 `CC_DRIVER` / `CC_TARGET_FLAGS`、`TARGET_EXE_SUFFIX`

### Commit 5：codegen 目标宏

- [x] `UYA_TARGET_PLATFORM`、`UYA_TARGET_OS_*`、`UYA_TARGET_ARCH_*`（与 `TARGET_OS`/`TARGET_ARCH` 编译器参数一致）

验证：Linux `make check` / `make check-hosted`。

---

## 共享基础「完成」后

Darwin syscall、Windows PE、非 Linux nostdlib、kqueue/IOCP 等在各自平台 Phase 验收，不在本文档宣称「共享基础未完成」— **Linux 可做的共享基础铺垫已做完**。
