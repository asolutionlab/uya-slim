# macOS 迁移 Phase 2 详细待办

本文档细化 [todo_macos_migration.md](todo_macos_migration.md) 中的 **Phase 2：编译器宿主平台抽象**，目标是把宿主相关逻辑拆到“可按提交推进”的粒度，并明确：

- Linux 应该执行到哪里
- 哪些工作必须在 macOS 上做

适用范围：

- `src/main.uya`

本阶段核心目标：

- 抽象编译器自身路径发现逻辑
- 去掉 `src/main.uya` 中 Linux-only 的宿主工具路径假设
- 收敛 `dirent` 布局访问
- 收敛临时输出路径与 build/run/test 的宿主路径逻辑
- 为 Darwin hosted bring-up 提供真实可验证的宿主层支撑

---

## 本阶段完成定义

满足以下条件即可视为 Phase 2 完成：

- [ ] `src/main.uya` 的宿主逻辑不再依赖 Linux-only 的硬编码 GCC PATH
- [ ] `get_compiler_dir()` 拥有清晰的 Linux / Darwin 路径分支
- [ ] `UYA_ROOT`、工具查找、默认路径推导逻辑被收敛到明确的 helper 中
- [ ] `dirent` 访问不再散落在多个调用点依赖 magic offset
- [ ] build/run/test 生成的临时路径经过统一封装
- [ ] macOS 上 hosted 路径能完成最小 build/run/test 验证
- [ ] Linux 行为不回归

---

## 明确不在本阶段做的事

- [ ] 不实现 Darwin `@syscall`
- [ ] 不修改 `lib/libc/syscall.uya`
- [ ] 不修改 `lib/syscall/`
- [ ] 不迁移 `osal`
- [ ] 不迁移 `pthread`
- [ ] 不实现 Darwin `--nostdlib`
- [ ] 不实现 `kqueue`
- [ ] 不重构标准库运行时入口

若某个改动需要触碰这些内容，说明已经越过 Phase 2 边界，应转入后续阶段处理。

---

## Linux 截止点与 macOS 必做项

### Linux 在 Phase 2 应该做到哪里

在 Phase 2 中，Linux 侧推荐**做到 Commit 3 为止**：

- [ ] Commit 1：抽取宿主路径与命令 helper
- [ ] Commit 2：去掉 Linux-only GCC PATH 假设
- [ ] Commit 3：封装 `dirent` 与临时路径逻辑

做到这里，Linux 的主要职责已经完成：宿主逻辑收敛、接口抽象成型、Darwin 分支可插入。

### 从哪里开始必须切到 macOS

**Commit 4 开始必须在 macOS 上做主验证**，因为这时要真正验证 Darwin 的宿主行为：

- [ ] Darwin 路径发现分支
- [ ] Darwin 下 `UYA_ROOT` 推导
- [ ] Darwin 下 build/run/test 临时路径
- [ ] Darwin 下目录扫描和模块发现

### Linux 可以继续做但不能算完成的事项

以下内容即便在 Linux 上先写好代码，也**不能在 Linux 上宣布完成**：

- [ ] Darwin 的 `get_compiler_dir()` 分支
- [ ] Darwin 的 `UYA_ROOT` 默认推导
- [ ] Darwin 的 `dirent` 行为适配
- [ ] Darwin 的 build/run/test 宿主命令验证

这些内容只能算“代码已准备”，真正完成必须以 macOS 真机验证为准。

### 一句话执行规则

- **Commit 1-3**：可以在 Linux 上完成并回归
- **Commit 4-5**：必须切到 macOS 做实现收口和验收

---

## 执行前检查

- [ ] 先完成 [todo_macos_phase1.md](todo_macos_phase1.md) 的核心目标
- [ ] Linux 上执行：
  - [ ] `make check`
  - [ ] `make uya-hosted`（若已存在）
- [ ] 记录 `src/main.uya` 当前强 Linux 绑定点：
  - [ ] `get_compiler_dir()` 使用 `/proc/self/exe`
  - [ ] `dirent_get_type()` / `dirent_get_name()` 使用 Linux x86-64 偏移
  - [ ] `link_with_gcc()` 使用硬编码 PATH + `gcc`
  - [ ] `/tmp/uya_output.c`
  - [ ] `/tmp/uya_out`

---

## 提交顺序总览

| 提交 | 目标 | 主要文件 | 验证重点 |
|------|------|----------|----------|
| 1 | 抽取宿主 helper | `src/main.uya` | Linux 不回归 |
| 2 | 去掉 Linux-only 工具路径假设 | `src/main.uya` | Linux build/run/test |
| 3 | 封装 `dirent` 与临时路径逻辑 | `src/main.uya` | Linux 模块发现 |
| 4 | 增加 Darwin 路径发现与 `UYA_ROOT` 分支 | `src/main.uya` | macOS `make from-c` / hosted smoke |
| 5 | Darwin 宿主行为收口 | `src/main.uya` | macOS build/run/test 与模块扫描 |

---

## Commit 1：抽取宿主路径与命令 helper

**建议提交名**：`host: extract path and command helpers in main.uya`

### 目标

- 先把 `src/main.uya` 中分散的宿主逻辑集中起来
- 在不改变行为的前提下，为 Darwin 分支预留插入点

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 抽取与宿主路径相关的 helper，例如：
  - [ ] 编译器目录获取
  - [ ] `UYA_ROOT` 组装
  - [ ] 临时输出路径生成
  - [ ] 运行产物路径生成
- [ ] 抽取与宿主命令构建相关的 helper，例如：
  - [ ] hosted 链接命令字符串生成
  - [ ] build/run/test 的输出路径选择
- [ ] 保证当前 Linux 行为不变，只做结构收敛

### 验证

- [ ] Linux：编译器仍可构建
- [ ] Linux：build/run/test 基础命令不回归

### 完成标准

- [ ] `src/main.uya` 中宿主逻辑不再明显散落
- [ ] 后续 Darwin 分支可以在 helper 层落位

---

## Commit 2：去掉 Linux-only 工具路径假设

**建议提交名**：`host: remove hardcoded gcc path from main.uya`

### 目标

- 解决 `src/main.uya` 里直接写死 `PATH=/usr/lib/gcc/... gcc ...` 的宿主假设
- 让编译器在宿主命令层面与 Phase 1 的 `CC` 抽象一致

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 将 `link_with_gcc()` 重命名为更中性的函数名，例如：
  - [ ] `link_with_cc()`
  - [ ] `link_with_host_cc()`
- [ ] 不再硬编码 Linux GCC 安装路径
- [ ] 工具选择优先级收敛为：
  - [ ] `CC`
  - [ ] 默认 `cc`
  - [ ] 必要时保留清晰报错
- [ ] 统一 build/run/test 路径中的宿主编译命令生成

### 验证

- [ ] Linux：build 模式仍可工作
- [ ] Linux：run 模式仍可工作
- [ ] Linux：test 模式仍可工作

### 完成标准

- [ ] `src/main.uya` 不再依赖 Linux GCC PATH
- [ ] hosted 命令构建逻辑与 Phase 1 保持一致

---

## Commit 3：封装 `dirent` 与临时路径逻辑

**建议提交名**：`host: encapsulate dirent and temp path handling`

### 目标

- 把 Linux `dirent` 偏移访问从业务逻辑中隔离出去
- 把 `/tmp/uya_output.c`、`/tmp/uya_out` 之类的路径生成收敛成单点逻辑

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 收敛 `dirent_get_type()` / `dirent_get_name()` 的调用点
- [ ] 如有需要，新增目录扫描辅助函数，避免业务逻辑反复直接操作裸偏移
- [ ] 抽取：
  - [ ] `build_default_c_output_path()`
  - [ ] `build_default_run_output_path()`
  - [ ] 或等价 helper
- [ ] 明确临时路径策略：
  - [ ] 若沿用 `/tmp`，写清这是“过渡默认值”
  - [ ] 若引入 `TMPDIR`，需保留回退到 `/tmp`

### 验证

- [ ] Linux：模块发现不回归
- [ ] Linux：目录遍历不回归
- [ ] Linux：build/run/test 的默认输出路径不回归

### 完成标准

- [ ] `dirent` 偏移不再散落于业务代码
- [ ] 临时路径生成逻辑单点收敛
- [ ] Darwin 分支具备清晰插入点

---

## Commit 4：增加 Darwin 路径发现与 `UYA_ROOT` 分支

**建议提交名**：`host: add darwin compiler path and UYA_ROOT branch`

### 目标

- 正式引入 Darwin 的宿主路径发现逻辑
- 让编译器在 macOS 上能正确找到自己和标准库根目录

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 为 `get_compiler_dir()` 增加 Darwin 分支
- [ ] 保留 Linux 分支与回退逻辑
- [ ] 校准 `get_uya_root()` 的默认推导逻辑
- [ ] 明确当 `UYA_ROOT` 缺失或路径获取失败时的报错与回退行为

### 验证

- [ ] macOS：`make from-c`
- [ ] macOS：`make uya-hosted`
- [ ] macOS：编译器能正确定位 `lib/`

### 完成标准

- [ ] Darwin 下编译器目录获取真实可用
- [ ] Darwin 下 `UYA_ROOT` 推导真实可用

---

## Commit 5：Darwin 宿主行为收口

**建议提交名**：`host: validate darwin dirent and temp path behavior`

### 目标

- 把 macOS 上真正会出错的宿主行为逐项跑通
- 完成 Phase 2 的事实验收

### 修改文件

- [ ] [../src/main.uya](../src/main.uya)

### 任务清单

- [ ] 校准 Darwin 下目录扫描行为
- [ ] 校准 Darwin 下 `dirent` 访问行为
- [ ] 校准 Darwin 下 build/run/test 的默认路径与执行流
- [ ] 修正最小 smoke 中暴露的宿主层问题

### 验证

- [ ] macOS：最小 build 成功
- [ ] macOS：最小 run 成功
- [ ] macOS：最小 test 成功
- [ ] macOS：模块发现与标准库定位成功

### 完成标准

- [ ] macOS hosted 宿主层行为真实可用
- [ ] Phase 2 可以交付给 Phase 3 / Phase 4 继续推进

---

## 建议的最小验证矩阵

### Linux 每个提交后的最小回归

- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] 选择 1 个简单 build/run/test smoke 用例

### Darwin 首次 bring-up 验证

- [ ] 从 Commit 4 开始执行
- [ ] `make from-c`
- [ ] `make uya-hosted`
- [ ] 编译器能找到 `UYA_ROOT`
- [ ] 最小 build/run/test 能完成

---

## 阶段结束后应立即进入的下一步

Phase 2 完成后，必须立刻进入以下主线：

1. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 3：`@syscall` / `syscall` / `osal` / runtime
2. [todo_macos_migration.md](todo_macos_migration.md) 的 Phase 4：hosted 自举与主测试基线

不建议在 Phase 2 完成后立即跳去做 `pthread`、`--nostdlib` 或 `async`，因为这些都依赖宿主层已经在 macOS 上真实稳定。

