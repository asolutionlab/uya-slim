# Core 编译器重构计划

**日期**：2026-06-20
**状态**：已执行 Phase 1；microcontainer/microapp 已从当前主线删除
**目标**：把当前臃肿的 `uya` 主入口拆成一个功能单一、边界清晰、可自举验证的 core 编译器。

---

## 1. 背景

当前仓库的编译器主入口位于 `src/main.uya`。它已经不只是编译器入口，还承担了多类平台型能力：

- 编译管线：lexer / parser / checker / safety proof / C99 codegen。
- CLI 编排：`build` / `check` / `run` / `test` 等命令。
- 包管理：`cmd.upm.upm_lib`。
- 实验后端：`exec` bytecode / VM。
- 已删除的历史工具入口。

这些能力放在同一个主入口里，会让核心编译器的维护、测试、冷启动和发布边界变得不清晰。重构目标是把 core 编译器从总控平台中剥离出来；microcontainer/microapp 路线已按后续决策从当前主线删除。

---

## 2. 重构目标

新增一个相对干净的 core 编译器形态，例如 `uya-core`。

`uya-core` 只负责：

1. 读取 `.uya` 源文件。
2. 解析模块依赖。
3. 解析 package mode 下的 `uya.toml`、source root、module root 与依赖 alias 映射。
4. 执行 lexer / parser / AST merge。
5. 执行 checker / safety proof。
6. 执行 C99 codegen。
7. 可选调用宿主 C 工具链完成链接。
8. 执行语言级 `test` 语法对应的最小测试运行入口。

`uya-core` 不负责：

- UPM fetch / publish / add / remove / lockfile 更新等包管理 CLI。
- formatter CLI。
- exec VM / bytecode 后端。
- HTTP / TLS / TFLM / benchmark 工具链。
- release 历史文档和实验路线图管理。

### 2.1 依赖边界

UPM 需要拆成两层，而不是整体移出 core：

| 能力 | core 是否保留 | 说明 |
|------|---------------|------|
| `uya.toml` discovery | 保留 | `build` / `check` / `run` 需要知道 package root 与 source root。 |
| source root / module root 计算 | 保留 | 直接影响 `use` 解析和多文件依赖收集。 |
| dependency alias -> source root 映射 | 保留 | package mode 下的模块身份解析依赖它。 |
| lockfile 读取 | 可保留只读子集 | 只允许服务构建输入解析，不在 core 中更新 lockfile。 |
| fetch / registry / git / path materialize | 移出 core | 属于包管理命令，不应进入 core 编译器主入口。 |
| `upm add/remove/publish` | 移出 core | 独立为外部命令或 `bin/cmd/upm`。 |

因此 Phase 1 的目标不是删除所有 `upm_lib` 依赖，而是先抽出一个 package resolution 子集，供 core 编译器使用；其余 UPM CLI 能力再拆成独立命令。

---

## 3. 推荐目录形态

```text
src/
  compiler/
    pipeline.uya
    options.uya
    diagnostics.uya
  cli/
    main_core.uya
  lexer.uya
  parser/
  checker/
  codegen/c99/
  driver/
  cmd/
    upm/
  experimental/
    exec/
```

说明：

- `src/compiler/` 提供稳定的编译管线 API。
- `src/cli/main_core.uya` 只做 core CLI 参数解析和编译管线调用。
- `src/cmd/upm/`、formatter、exec VM 不进入 core 主入口。
- 现有 `src/main.uya` 可暂时保留为 full 入口，降低迁移风险。
- Phase 1 / Phase 2 只调整入口依赖和构建目标，不移动现有目录。
- 物理目录迁移必须单独立项，并同步更新 `use` 路径、Makefile、测试脚本和文档引用。

---

## 4. 阶段计划

### Phase 1：切出 core 编译器入口

目标：不删功能，只新增干净入口。

- 新建 `src/compiler/options.uya`，收敛核心编译选项。
- 新建 `src/compiler/pipeline.uya`，封装 `check` / `build_c99` / `run` 的核心流程。
- 从现有 UPM/package mode 逻辑中抽出只读 package resolution 子集，供 core 编译器解析 `uya.toml`、module root 与 alias root。
- 新建 `src/cli/main_core.uya`，只支持核心子命令：
  - `check`
  - `build`
  - `run`
  - `test`（保留语言级测试运行入口；不包含外部专项测试脚本编排）
- Makefile 新增 `make uya-core`。
- 初始目标是跑通一个最小闭环：
  - `make from-c`
  - `make uya-core`
  - `./bin/uya-core check tests/check_cli_no_main.uya`
  - `./bin/uya-core check tests/error_check_missing_brace.uya`（应失败且诊断明确）
  - `./bin/uya-core build tests/arithmetic.uya --c99 -o /tmp/arithmetic.c`
  - 使用宿主 C 编译器链接并运行 `/tmp/arithmetic.c`
  - `./bin/uya-core build tests/test_c_import_file.uya -o /tmp/test_c_import_file --c99`
  - `./bin/uya-core check tests/cross_deps/test_structs_main.uya`
  - 选择一个 `tests/fixtures/upm/` package mode smoke，验证 `uya.toml` / alias root 不退化
  - `./bin/uya-core test tests/test_basic.uya` 或等价语言级测试 smoke

Phase 1 不要求立刻替换默认 `bin/uya`，但必须证明 core 入口能覆盖当前编译器的基础用户路径。

### Phase 2：拆出非核心能力

目标：让 core 编译器不导入非核心模块。

- 将 UPM CLI 维持在 `src/cmd/upm/`，由 `make cmds` 或独立目标构建。
- 将 package resolution 只读子集沉到 core 可复用模块，避免 core 入口依赖 fetch / publish / registry 等能力。
- formatter 已移除，不再作为 core/full 拆分目标。
- 将 `src/exec/` 标记为实验后端，避免默认进入 core 编译器。
- microcontainer/microapp 已删除；不再拆成独立命令，也不进入 full/core 入口。
- 保留 full 入口一段时间，用于兼容现有发布流程和专项测试。

### Phase 3：收敛测试和发布边界

目标：区分 core 验证和 full 验证。

- 新增 core 快速门禁：
  - core 自举：`uya-core` 能生成自身 C99，并链接出 `bin/uya-core-stage2`。
  - 本阶段不做 core C 输出字节级一致性比较；当前 C99 生成物仍包含路径、分片布局和生成顺序等未规范化因素，过早加入字节级比较会把非语义差异变成门禁噪音。Phase 3 以 stage2 可生成、可链接、可运行和 `make check-core` smoke 作为自举判据；后续若先建立 deterministic C emission 或归一化比较脚本，再把输出一致性纳入门禁。
  - 语言基础测试。
  - checker 错误测试。
  - C99 codegen 基础回归。
  - package mode / alias root smoke。
  - `@c_import` smoke。
  - split-C smoke。
- full 门禁继续覆盖：
  - UPM。
  - exec VM。
  - HTTP / async / TLS / benchmark smoke。
- Makefile 中区分：
  - `make check-core`
  - `make check`
  - `make check-hosted`
  - `make upm-check`

`make check-core` 的职责是证明 core 编译器可作为普通语言用户的默认入口；`make check` 继续证明完整仓库功能不退化。

### Phase 4：仓库清理

目标：在 core 入口稳定后，清理明显无关或过时内容。

低风险候选：

- `package-lock.json`：当前没有对应 `package.json`，且未发现引用。
- `.tmp_fmt_input.uya` / `.tmp_fmt_writeback.uya`：历史 formatter smoke 临时文件；若仍残留可直接删除。
- `.marscode/deviceInfo.json`：个人 IDE / 设备元数据。

需要归档而不是直接删除的候选：

- 历史计划、完成报告、旧 release 文档。
- 仍有参考价值的 bug report。
- `compiler-c` / `compiler-mini` 时代说明。

不建议删除：

- `src/`
- `lib/`
- `tests/`
- `backup/`
- 核心规范文档：`docs/uya.md`、`docs/uya_ai_prompt.md`、`docs/grammar_formal.md`、`docs/grammar_quick.md`、`docs/builtin_functions.md`

---

## 5. 过时内容处理策略

发现文档或脚本中残留 `compiler-c` / `compiler-mini` 路径时，按以下规则处理：

1. 如果是当前开发指导或测试脚本提示，更新为当前入口：
   - `make from-c`
   - `make from-c-native`
   - `make uya`
   - `make uya-hosted`
2. 如果是 release notes 或历史记录，保留原文，但可在文档顶部标注“历史路径，仅用于版本记录”。
3. 如果是已完成的 TODO，可移动到 `docs/archive/`，但不要在没有索引的情况下静默删除。

---

## 6. 验证标准

每个阶段完成后至少满足：

- `git diff --check` 通过。
- core 入口能完成 `check` 和 C99 `build`。
- core 入口能链接并运行至少一个正向程序。
- core 入口能覆盖一个错误测试、一个多文件测试、一个 package mode smoke 和一个 `@c_import` smoke。
- 相关快速测试通过。
- 没有删除有意义的回归测试。
- full 入口在迁移期仍可用，直到明确替代完成。

准备提交前仍遵循仓库规则：

```bash
make clean
make backup-all
```

如果只是文档整理，不需要运行完整 `make check`，但至少运行：

```bash
git diff --check
```

---

## 7. 决策原则

- 先拆入口，再删功能。
- 先保留兼容 full 入口，再让 core 入口独立稳定。
- 先把包管理、formatter、exec VM 从主入口剥离，再考虑目录迁移。
- 包管理要拆 CLI 能力，不要误删 core 编译所需的 package resolution。
- 不把测试、seed、语言规范当作“臃肿”处理。
- 删除前先确认是否属于构建冷启动、发布备份或回归验证链路。

---

## 8. 目标形态

迁移期保留两个入口：

- `uya-core`：新增的精简 core 编译器入口，面向普通语言用户和编译器开发；安装时可单独安装。
- `uya`：迁移期继续作为 full 兼容入口，保留 release、UPM、exec VM 和专项测试能力；本阶段不改名为 `uya-full`，避免破坏现有脚本、seed 和发布流程。
- `uya-core-stage2`：仅作为本地 core 自举验证产物，不作为安装或发布二进制。

安装布局在迁移期区分两个目标：

- `make install-core`：安装 `uya-core` 和 `lib/`，不构建或安装 `bin/cmd/*`。
- `make install`：保留 full 兼容安装语义，安装 `uya`、`bin/cmd/*` 和 `lib/`，供 UPM 等兼容入口使用。

seed / backup 策略在迁移期不拆分两套可信根：

- `backup/uya.c`、`backup/uya-$(HOST_OS)-$(HOST_ARCH).c`、`backup/uya-hosted*.c` 和 `backup/uyacache/` 继续表示 full `src/main.uya` 编译器种子与备份。
- `make backup-all`、`make backup-all-seed` 和 `make release` 继续围绕 full `uya` 更新和验证 seed，避免同时维护 `full seed` 与 `core seed` 两套发布入口。
- `bin/uya-core.c` 由 `make uya-core` 从当前 full 编译器生成，是本地构建产物；本阶段不提交 `backup/uya-core.c`。
- `bin/uya-core-stage2` 只用于 core 自举 smoke，不进入安装、seed 或 release 产物。
- 只有当 `uya-core` 被明确提升为默认发布入口，或需要独立冷启动 core 编译器时，再单独设计 `backup/uya-core.c` 及 host/arch 变体，并同步更新 `from-c`、`backup-all` 和 `release`。

最终是否让 `uya-core` 取代默认 `uya`，应在以下条件满足后再决定：

- `make check-core` 稳定通过。
- core 自举链路稳定。
- package mode 构建能力不退化。
- full 入口的非核心能力已有独立命令或清晰兼容入口。
- release seed 与安装布局已同步更新。
