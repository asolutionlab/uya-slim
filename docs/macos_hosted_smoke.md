# macOS hosted 迁移、交叉产物与冒烟验证

本文档配合 [todo_macos_phase1.md](todo_macos_phase1.md) Commit 5+ 与 Phase 2（宿主路径），说明在 **Darwin** 上如何先做 **hosted** 验证。

## 当前限制（随迁移推进会缩小）

| 能力 | 状态 |
|------|------|
| Linux 上用 `zig cc` 交叉产出 macOS hosted 编译器 | **已验证**：`arm64` / `x86_64` Mach-O 产物均可生成 |
| macOS 上原生运行 hosted 编译器并继续自举 | **待真机 smoke 验证**：交叉产物已具备，运行语义仍需在 Darwin 上确认 |
| `make from-c` | **hosted 主线可用**：优先使用 `backup/uya-hosted-macos-<arch>.c`；若回退到 `backup/uya.c`（Linux nostdlib `_start`）则仍不可用 |
| `make uya`（`--nostdlib`） | **未实现**：见 Phase 6 |
| 未设 `UYA_ROOT` 时编译器自找 `lib/` | **代码已接**：Darwin 上 `_NSGetExecutablePath` + `realpath`，但首次真机 smoke 仍建议显式设置 `UYA_ROOT` 做保底 |

## Linux 侧交叉产物准备（已验证）

如果你当前在 Linux 上推进 Darwin hosted bring-up，推荐先重建一个新的 Linux hosted 编译器，再用它交叉出 macOS 产物：

```bash
cd src

# 1. 先重建 Linux hosted 编译器
./compile.sh --c99 -e --name uya-hosted-stage-linux --no-safety-proof

# 2. 交叉出 Apple Silicon macOS 编译器
UYA_COMPILER="../bin/uya-hosted-stage-linux" \
TOOLCHAIN=zig \
ZIG=/home/winger/zig/zig \
TARGET_OS=macos \
TARGET_ARCH=arm64 \
TARGET_TRIPLE=aarch64-macos-none \
./compile.sh --c99 -e --name uya-hosted-macos-arm64 --no-safety-proof

# 3. 交叉出 Intel macOS 编译器
UYA_COMPILER="../bin/uya-hosted-stage-linux" \
TOOLCHAIN=zig \
ZIG=/home/winger/zig/zig \
TARGET_OS=macos \
TARGET_ARCH=x86_64 \
TARGET_TRIPLE=x86_64-macos-none \
./compile.sh --c99 -e --name uya-hosted-macos-x86_64 --no-safety-proof
```

截至 2026-04-17，上述链路已经实测生成：

- `Mach-O 64-bit arm64 executable`
- `Mach-O 64-bit x86_64 executable`

推荐把生成的仓库整体同步到 Mac，再继续做 native smoke。

## 推荐冒烟步骤（macOS）

### macOS 构建

1. 在仓库根目录：
   ```bash
   export UYA_ROOT="$(pwd)/lib/"   # 首次 smoke 建议显式设置，避免 lib/ 路径发现问题干扰
   ```

2. 先确认交叉产物基本可执行：
   ```bash
   file ./bin/uya-hosted-macos-arm64
   file ./bin/uya-hosted-macos-x86_64
   ```

3. 在对应架构的 Mac 上，先用 hosted 编译器做一个最小 hosted smoke：
   ```bash
   ./bin/uya-hosted-macos-arm64 build tests/programs/test_bounds_check.uya -o /tmp/test_bounds_check.c --c99 -e
   /tmp/test_bounds_check
   ```

   Intel Mac 将编译器换成 `./bin/uya-hosted-macos-x86_64`。

4. 再做第一轮主测试 smoke：
   ```bash
   TEST_PROFILE=hosted make tests-hosted
   ```

5. 若需要观察未过滤的 Darwin 问题面，再关闭默认跳过列表：
   ```bash
   SKIP_DARWIN_DEFAULT=0 ./tests/run_programs_parallel.sh --uya --c99
   ```

当前最值得优先关注的 Darwin 真机点：

- `getcwd`
- `stat` / `fstat` / `lstat`
- `readdir` / `getdirentries64`
- `clock_gettime` / `nanosleep`
- `pthread` 相关语义

## Darwin 默认跳过的测试

环境变量 **`SKIP_DARWIN_DEFAULT=1`**（默认，在 `HOST_OS=macos` 时）：跳过依赖 Linux syscall / epoll / osal 等尚未在 Darwin 对齐的用例。列表在 `tests/run_programs_parallel.sh` 内维护，随平台能力扩展而缩减。

设为 **`SKIP_DARWIN_DEFAULT=0`** 可关闭该过滤。

## 相关文档

- [todo_macos_migration.md](todo_macos_migration.md) — 总路线
- [todo_macos_phase1.md](todo_macos_phase1.md) — Phase 1 构建链
- [UYA_BUILD_RUN.md](UYA_BUILD_RUN.md) — 工具链与环境变量
