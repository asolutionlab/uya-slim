# macOS hosted 迁移与冒烟验证

本文档配合 [todo_macos_phase1.md](todo_macos_phase1.md) Commit 5+ 与 Phase 2（宿主路径），说明在 **Darwin** 上如何先做 **hosted** 验证。

## 当前限制（随迁移推进会缩小）

| 能力 | 状态 |
|------|------|
| `make uya-hosted` / `make b-hosted` | 目标：在 macOS + `clang` 上可跑通 |
| `make from-c`（`backup/uya.c` 为 Linux nostdlib） | **不可用**：备份 C 内含 Linux x86_64 `_start`，需在 Mac 上从源码自举或换用将来提供的 Darwin/hosted 备份策略 |
| `make uya`（`--nostdlib`） | **未实现**：见 Phase 6 |
| 未设 `UYA_ROOT` 时编译器自找 `lib/` | **代码已接**：Darwin 上 `_NSGetExecutablePath`+`realpath`（需 macOS 上跑通验收） |

## 推荐冒烟步骤（macOS）

### 前置：Linux 准备 hosted 备份（推荐）

在 **Linux 上**执行：
```bash
make backup-hosted-seed   # 生成 backup/uya-hosted.c（hosted 单文件种子）
```
然后将仓库同步到 Mac。

### macOS 构建

1. 在仓库根目录：
   ```bash
   export UYA_ROOT="$(pwd)/lib/"   # 必须，直到 Phase 2 落地
   make from-c   # 自动使用 backup/uya-hosted.c
   make uya-hosted
   make b-hosted
   ```

2. 测试：
   ```bash
   TEST_PROFILE=hosted make tests-hosted
   # 或强制跑全部：
   SKIP_DARWIN_DEFAULT=0 ./tests/run_programs_parallel.sh --uya --c99
   ```
3. 运行测试（默认会跳过部分 Linux 专用用例，见下）：
   ```bash
   TEST_PROFILE=hosted make tests-hosted
   # 或强制跑全部（预期大量失败，直至 syscall/osal/async Darwin 完成）：
   SKIP_DARWIN_DEFAULT=0 ./tests/run_programs_parallel.sh --uya --c99
   ```

## Darwin 默认跳过的测试

环境变量 **`SKIP_DARWIN_DEFAULT=1`**（默认，在 `HOST_OS=macos` 时）：跳过依赖 Linux syscall / epoll / osal 等尚未在 Darwin 对齐的用例。列表在 `tests/run_programs_parallel.sh` 内维护，随平台能力扩展而缩减。

设为 **`SKIP_DARWIN_DEFAULT=0`** 可关闭该过滤。

## 相关文档

- [todo_macos_migration.md](todo_macos_migration.md) — 总路线
- [todo_macos_phase1.md](todo_macos_phase1.md) — Phase 1 构建链
- [UYA_BUILD_RUN.md](UYA_BUILD_RUN.md) — 工具链与环境变量
