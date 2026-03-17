# macOS 迁移 Phase 6 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 6：`--nostdlib` Darwin 路线**，目标是把这一阶段拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做
- macOS 上 `--nostdlib` 的第一阶段目标应该如何定义

适用范围：

- `src/compile.sh`
- `Makefile`
- `lib/std/runtime/runtime.uya`
- `lib/std/runtime/entry/entry.uya`
- `docs/UYA_BUILD_RUN.md`

本阶段核心目标：

- 让 macOS 上的 `--nostdlib` 有一个现实可执行的目标定义
- 拆分 Linux 与 Darwin 的启动/链接路径
- 不再把 Linux 的 `_start + syscall exit(60) + -static + crti.o/crtn.o` 直接当成 Darwin 方案
- 为后续 macOS 上的 `--nostdlib` 程序、以及条件允许时的自举验证打基础

---

## 默认路线决策

### 推荐默认方案

**推荐先把 macOS `--nostdlib` 定义为：**

- [ ] 不依赖 C 标准库 API
- [ ] 拥有自定义启动/退出路径
- [ ] 允许在第一阶段依赖系统启动对象或平台要求的最小装载机制
- [ ] **不强求第一阶段就实现“完全静态链接”**

理由：

- [ ] macOS 与 Linux 的静态链接生态差异很大
- [ ] 现有 Linux `-static -nostdlib` 路径不能直接平移到 Darwin
- [ ] 如果一开始就把目标定义成“完全静态、零系统启动依赖”，项目风险会显著放大

### 长期可选方案

**长期可选：继续追求更强的零依赖定义**

- [ ] 若后续需要，可再把目标提升为“更严格的 freestanding / 极低系统依赖”
- [ ] 该目标不应阻塞当前 macOS 主线迁移

---

## 本阶段完成定义

满足以下条件即可视为 Phase 6 完成：

- [ ] `src/compile.sh` 的 `--nostdlib` 路径明确区分 Linux 与 Darwin
- [ ] Darwin 不再误走 Linux `_start` 模板
- [ ] Darwin `x86_64` / `arm64` 拥有明确的 `--nostdlib` 启动策略
- [ ] `std.runtime.runtime` 的退出路径不再写死 Linux `SYS_exit=60`
- [ ] `std.runtime.entry` 与 `--nostdlib` 的参数/入口语义保持一致
- [ ] macOS 上最小 `--nostdlib` 程序可编译、可链接、可运行
- [ ] Linux 现有 `--nostdlib` 路径不回归

---

## 明确不在本阶段做的事

- [ ] 不迁移 `pthread`
- [ ] 不恢复 async / `kqueue`
- [ ] 不要求本阶段直接把 macOS `--nostdlib` 纳入默认 `check`
- [ ] 不要求第一轮就让 macOS `--nostdlib` 进入完整自举

若某个改动需要依赖这些内容，说明已经越过 Phase 6 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 6 应该做到哪里

在 Phase 6 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：定义 Darwin `--nostdlib` 目标与验收边界
- [ ] Commit 2：拆分 `compile.sh` 中的 Linux / Darwin `--nostdlib` 路径
- [ ] Commit 3：收敛 runtime 中的 Linux-only 启动/退出假设

做到这里，Linux 的主要职责已经完成：目标边界、脚本结构和 runtime 抽象已经成型。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时要真正验证 Darwin 的启动、链接和退出语义：

- [ ] Darwin `x86_64` `_start` / 入口路径
- [ ] Darwin `arm64` `_start` / 入口路径
- [ ] Darwin 的链接参数、启动对象和装载行为
- [ ] 最小 `--nostdlib` 程序的启动、参数传递、退出

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin `_start`
- [ ] Darwin CRT / 启动对象策略
- [ ] Darwin `--nostdlib` 链接参数
- [ ] Darwin 最小程序通过结论

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
- [ ] 记录当前 `--nostdlib` 的强 Linux 绑定点：
  - [ ] `src/compile.sh` 内嵌 x86-64 Linux `_start`
  - [ ] `_start` 里写死 `movq $60, %rax` 作为 `exit syscall`
  - [ ] `gcc -print-file-name=crti.o/crtn.o`
  - [ ] `-nostdlib -static`
  - [ ] `Makefile` 的 `b` 仍绑定 `./compile.sh --c99 -e -b --nostdlib`
  - [ ] `docs/UYA_BUILD_RUN.md` 明确写着当前仅支持 Linux x86-64
  - [ ] `lib/std/runtime/runtime.uya` 仍写死 `@syscall(60, code)`

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 定义 Darwin `--nostdlib` 目标边界 | 文档、Makefile 注释 | Linux 文档与入口不回归 |
| 2 | 拆分 Linux / Darwin `--nostdlib` 脚本路径 | `src/compile.sh` | Linux `--nostdlib` 不回归 |
| 3 | 收敛 runtime 启动/退出假设 | `lib/std/runtime/*` | Linux 最小 `--nostdlib` 程序不回归 |
| 4 | Darwin `x86_64` 最小 `--nostdlib` bring-up | `src/compile.sh`、runtime | macOS x86_64 最小程序 |
| 5 | Darwin `arm64` 收口与可选自举预研 | 同上 | macOS arm64 最小程序 |

---

## Commit 1：定义 Darwin `--nostdlib` 目标边界

**建议提交名**：`nostdlib: define darwin success criteria`

### 目标

- 正式明确 Darwin `--nostdlib` 第一阶段追求什么、不追求什么
- 避免后续实现过程中反复摇摆

### 修改文件

- [ ] [../docs/UYA_BUILD_RUN.md](../docs/UYA_BUILD_RUN.md)
- [ ] [../Makefile](../Makefile) 注释或帮助信息
- [ ] 相关 TODO 文档

### 任务清单

- [ ] 明确 Darwin `--nostdlib` 第一阶段目标：
  - [ ] 无 libc API 依赖
  - [ ] 可启动、可传参、可退出
  - [ ] 不强求完全静态
- [ ] 明确 Darwin `--nostdlib` 暂不承诺：
  - [ ] 与 Linux 完全相同的链接方式
  - [ ] 直接进入默认 `check`
  - [ ] 立即进入完整自举

### 验证

- [ ] 文档表述与主迁移策略一致

### 完成标准

- [ ] Darwin `--nostdlib` 目标定义清晰，不再模糊

---

## Commit 2：拆分 Linux / Darwin `--nostdlib` 脚本路径

**建议提交名**：`build: split linux and darwin nostdlib paths`

### 目标

- 把 `src/compile.sh` 中 Linux 专用 `--nostdlib` 路径隔离出来
- 为 Darwin 预留完全独立的入口

### 修改文件

- [ ] [../src/compile.sh](../src/compile.sh)

### 任务清单

- [ ] 把当前 Linux `_start` 模板与链接命令封装成独立分支
- [ ] 增加 Darwin 分支骨架
- [ ] Darwin 分支在未实现前应给出清晰错误，而不是误用 Linux 路径
- [ ] 保留 hosted 路径不受影响

### 验证

- [ ] Linux：现有 `--nostdlib` 构建不回归
- [ ] Linux：hosted 构建不回归

### 完成标准

- [ ] Linux / Darwin `--nostdlib` 路径彻底分开
- [ ] Darwin 不会误走 Linux `_start` 模板

---

## Commit 3：收敛 runtime 启动/退出假设

**建议提交名**：`runtime: remove linux-only nostdlib assumptions`

### 目标

- 把 runtime 中写死的 Linux `exit` / 启动假设收敛成可替换结构
- 保证后续 Darwin `--nostdlib` 能共用 runtime 语义

### 修改文件

- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)
- [ ] [../lib/std/runtime/entry/entry.uya](../lib/std/runtime/entry/entry.uya)

### 任务清单

- [ ] 收敛 `_uya_exit()` 的 Linux `SYS_exit=60` 假设
- [ ] 明确 `std.runtime.entry` 在 `--nostdlib` / hosted 下的角色边界
- [ ] 确保参数保存、入口函数调用、退出路径语义一致

### 验证

- [ ] Linux：最小 `--nostdlib` 程序不回归
- [ ] Linux：hosted 程序不回归

### 完成标准

- [ ] runtime 不再写死 Linux-only `--nostdlib` 假设

---

## Commit 4：Darwin `x86_64` 最小 `--nostdlib` bring-up

**建议提交名**：`darwin: bring up minimal x86_64 nostdlib path`

### 目标

- 在 macOS x86_64 上跑通最小 `--nostdlib` 程序
- 验证 Darwin 下的启动、参数与退出路径

### 修改文件

- [ ] [../src/compile.sh](../src/compile.sh)
- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)
- [ ] 必要的 Darwin 相关辅助文件

### 任务清单

- [ ] 落地 Darwin x86_64 的最小 `_start` / 入口策略
- [ ] 确认链接参数与必要启动对象
- [ ] 验证最小程序：
  - [ ] 可启动
  - [ ] 能看到参数
  - [ ] 能正常退出

### 验证

- [ ] macOS x86_64：最小 `--nostdlib` 程序编译成功
- [ ] macOS x86_64：最小 `--nostdlib` 程序运行成功

### 完成标准

- [ ] Darwin x86_64 最小 `--nostdlib` 成立

---

## Commit 5：Darwin `arm64` 收口与可选自举预研

**建议提交名**：`darwin: bring up arm64 nostdlib path`

### 目标

- 在 macOS arm64 上跑通最小 `--nostdlib`
- 在条件允许时评估是否进入 `b` 级别自举预研

### 修改文件

- [ ] [../src/compile.sh](../src/compile.sh)
- [ ] [../lib/std/runtime/runtime.uya](../lib/std/runtime/runtime.uya)
- [ ] 必要的 Darwin 相关辅助文件

### 任务清单

- [ ] 落地 Darwin arm64 的最小 `_start` / 入口策略
- [ ] 校准参数传递与退出路径
- [ ] 若条件允许，评估：
  - [ ] 是否存在 `b-hosted` 之后的 `b-nostdlib-darwin` 预研入口

### 验证

- [ ] macOS arm64：最小 `--nostdlib` 程序编译成功
- [ ] macOS arm64：最小 `--nostdlib` 程序运行成功

### 完成标准

- [ ] Darwin arm64 最小 `--nostdlib` 成立
- [ ] Darwin `--nostdlib` 进入可独立演进状态

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make from-c`
- [ ] 现有 Linux `--nostdlib` 路径不回归
- [ ] `make check-hosted` 不回归

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] macOS x86_64：最小 `--nostdlib` 程序启动/退出
- [ ] macOS arm64：最小 `--nostdlib` 程序启动/退出

---

## 阶段结束后应立即进入的下一步

Phase 6 完成后，后续主线应继续：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 7：`std.async` / `kqueue`

若 Darwin `--nostdlib` 仅完成最小程序级别验证，也属于可接受结果；不应因为它尚未进入完整自举而阻塞 async 阶段推进。

