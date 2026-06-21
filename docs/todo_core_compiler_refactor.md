# Core 编译器重构 TODO

**日期**：2026-06-20
**状态**：Phase 1-7 已完成；后续 microcontainer/microapp 删除已同步到主线
**来源**：`docs/core_compiler_refactor_plan.md`
**目标**：按阶段把当前 full 主入口拆出一个功能单一、边界清晰、可验证的 `uya-core` 编译器入口。

> 当前状态说明：本文中早期出现的 `microapp` / `kernel.image` / `kernel.payload` 记录属于执行时的历史基线；后续已按用户要求删除 microcontainer/microapp 功能、相关库、示例、文档和专项测试，full 入口不再保留这些能力。

---

## 执行规则

- 按 Phase 顺序推进，不跳过未完成的前置项。
- 完成一项后立即把对应复选框改为 `[x]`，并补充验证记录。
- 若发现任务定义与当前源码不一致，先更新本文档，再继续实现。
- 不删除有意义的测试、seed 或语言规范文档。
- Phase 1 / Phase 2 只调整入口依赖和构建目标，不做物理目录迁移。

---

## Phase 0：基线确认

- [x] 确认当前工作树状态。
  - 验证：`git status --short`
  - 结果：仅有 `docs/core_compiler_refactor_plan.md` 与 `docs/todo_core_compiler_refactor.md` 两个未跟踪文档。
- [x] 确认当前环境是否已有 `bin/uya`；若没有，记录需要从 seed 冷启动。
  - 验证：`test -x bin/uya || echo "bin/uya missing"`
  - 结果：`bin/uya missing`，后续需要通过 seed 冷启动。
- [x] 冷启动或确认可用编译器。
  - Linux 默认验证：`make from-c`
  - macOS 本机验证：`make from-c-native`
  - 结果：Linux 环境运行 `make from-c` 成功，生成 `bin/uya`。
- [x] 记录当前 Makefile 编译目标和测试目标。
  - 验证：`make help`
  - 结果：当前 Makefile 已有 `from-c`、`uya`、`uya-hosted`、`b`、`tests`、`tests-uya`、`cmds`、`upm-check`、`microapp-check`、`check`、`check-hosted`、`backup-all`、`release`、`install` 等目标；尚无 `uya-core` / `check-core`。
- [x] 盘点 `src/main.uya` 当前导入的非 core 模块。
  - 重点：`cmd.upm.upm_lib`、`exec`、`microapp`、`kernel.image`、`kernel.payload`
  - 结果：`src/main.uya` 顶层直接导入 `microapp`、`exec`、`kernel.image`、`kernel.payload`、`cmd.upm.upm_lib` 及多个 UPM 类型/函数；同时 `CommandType` 包含 image、outlibc 等非 core 命令。

---

## Phase 1：定义 core 边界

- [x] 明确 `uya-core` 保留的核心能力。
  - 输入读取
  - 模块依赖解析
  - package mode 只读解析
  - lexer / parser / AST merge
  - checker / safety proof
  - C99 codegen
  - 可选链接
  - 语言级 `test` 运行入口
  - 结果：保留边界与 `docs/core_compiler_refactor_plan.md` 一致；当前 `src/main.uya` 已有 `build` / `check` / `run` / `test` 命令路径，可作为 core 入口拆分的行为基线。
- [x] 明确 `uya-core` 不包含的能力。
  - UPM fetch / publish / add / remove / lockfile 更新
  - 已删除的历史 formatter CLI
  - exec VM / bytecode 后端
  - microapp / image / payload 命令
  - benchmark / release 历史工具
  - 结果：非 core 能力对应当前 `src/main.uya` 中的 `pack-image`、`inspect-image`、`verify-image`、`--app microapp`、`--exec` / `--vm`、`--outlibc` 及 UPM CLI 能力；后续应留在 full 入口或独立命令。
- [x] 从 UPM 中划出 package resolution 只读子集。
  - 保留：`uya.toml` discovery、source root、module root、alias root、lockfile 只读输入。
  - 移出：fetch、registry、git/path materialize、publish、add/remove、lockfile 写入。
  - 结果：core 只读子集保留 manifest discovery/parser、source/module root、compile_input、resolved_graph alias -> source_root、`UPMPackageBuildPlan` / `UPMPackageContext` 和必要的只读 lockfile 输入；移出 UPM CLI、fetch/git/registry/proxy、materialize、publish、diagnostics、lockfile 写入。当前 `upm_prepare_package_graph_plan` 仍会经过 resolver/fetcher/lockfile 写入路径，后续需拆出 read-only package resolution 模块后才能作为 core 依赖。
- [x] 为 core 编译选项设计最小数据结构。
  - 目标文件：`src/compiler/options.uya`
  - 设计结果：`options.uya` 只定义 core 命令、输入、输出、编译和运行选项，不直接读取 `argv`，也不导入 UPM CLI、microapp、exec VM、formatter。
  - 设计结果：核心结构建议为 `UyaCoreCommand`（`check` / `build` / `run` / `test`）、`UyaCoreInputOptions`（输入路径数组、输入数量、module root 覆盖、manifest 覆盖）、`UyaCoreOutputOptions`（输出路径、临时 C 路径、split-C 目录、line directive 开关）、`UyaCoreCompileOptions`（安全证明、优化等级、nostdlib、stack size、async frame heap fallback）和 `UyaCoreRunOptions`（运行时参数数组与数量）。
  - 设计结果：CLI 入口负责把 `argv` 下标转换成上述路径和值；pipeline 只消费结构体，避免把 full 入口的 `parse_args` 标量参数继续扩散。
- [x] 为 core 编译管线设计最小 API。
  - 目标文件：`src/compiler/pipeline.uya`
  - 初始 API：`check`、`build_c99`、`run`、`test`
  - 设计结果：对外 API 建议为 `uya_core_check(options, result)`、`uya_core_build_c99(options, result)`、`uya_core_run(options, result)`、`uya_core_test(options, result)`，其中 `result` 返回 generated C 路径、linked executable 路径和运行退出码等最小结果。
  - 设计结果：内部共享 `uya_core_compile_to_c99(options, stop_after_checker, result)`，负责输入解析、依赖收集、lexer/parser、AST merge、checker、安全证明、优化和 C99 codegen；`run` / `test` 只在此基础上增加宿主链接和执行。
  - 设计结果：`pipeline.uya` 允许依赖 `main`、`parser`、`checker`、`driver`、`codegen.c99`、`std`、`libc` 和后续拆出的 package read-only 模块；禁止依赖 `exec`、`microapp`、`kernel.image`、`kernel.payload` 和 UPM CLI/fetch/publish 模块。
  - 设计结果：full 入口的 `CommandType` / `BackendType` 不进入 core API；core 默认 C99 后端，`check` 用 `stop_after_checker` 表达，不再通过 “LLVM 默认后端但输出 .c 时切 C99” 的历史行为转义。

---

## Phase 2：新增 core 入口

- [x] 新建 `src/compiler/options.uya`。
  - 要求：只包含 core 编译选项，不引用 UPM CLI、microapp、exec VM、formatter。
  - 验证：`./bin/uya check src/compiler/options.uya`
  - 结果：通过；文件仅定义 core command/input/output/compile/run/result 结构和默认初始化函数，无非 core 模块导入。
- [x] 新建 `src/compiler/pipeline.uya`。
  - 要求：复用现有 lexer / parser / checker / C99 codegen，不复制大段主入口逻辑。
  - 验证：`./bin/uya check src/compiler/pipeline.uya --project-root src/`
  - 结果：通过；`pipeline.uya` 直接导入 `arena`、`ast`、`lexer`、`parser`、`checker`、`driver`、`codegen.c99` 和 `compiler.options`，未导入 `src/main.uya`、`exec`、`microapp`、`kernel.image`、`kernel.payload` 或 UPM CLI。当前实现已接入 check/build C99/run/test 的核心路径；package mode 的 UPM 只读解析仍按 Phase 1 结果待拆分。
- [x] 新建 `src/cli/main_core.uya`。
  - 支持：`check`、`build`、`run`、`test`
  - 不支持：`upm`、image/microapp、exec VM 专项命令；历史 `fmt` 命令已删除。
  - 验证：`./bin/uya check src/cli/main_core.uya --project-root src/`
  - 结果：通过；入口只解析 core 子命令和 core 编译选项，非 core 子命令会显式报错，不导入 full 入口或非 core 模块。
- [x] 保留现有 `src/main.uya` 作为 full 入口。
  - 要求：迁移期 full 入口行为不退化。
  - 验证：`git diff -- src/main.uya`
  - 验证：`./bin/uya --version`
  - 结果：`src/main.uya` 无差异，现有 full 入口返回 `v0.10.0`。
- [x] 避免 core 入口导入非 core 模块。
  - 检查：`rg -n "use (exec|microapp|kernel\\.image|kernel\\.payload|cmd\\.upm)" src/cli src/compiler`
  - 结果：无匹配；`src/cli` 与 `src/compiler` 当前没有直接导入 `exec`、`microapp`、`kernel.image`、`kernel.payload` 或 `cmd.upm`。
- [x] Makefile 新增 `make uya-core`。
  - 输出：`bin/uya-core`
  - 不替代现有 `make uya`。
  - 验证：`make uya-core`
  - 验证：`test -x bin/uya-core`
  - 验证：`./bin/uya-core --version`
  - 验证：`make help`
  - 结果：通过；`make uya-core` 生成并链接 `bin/uya-core`，`./bin/uya-core --version` 输出 `uya-core v0.10.0`，`make help` 同时保留 `make uya` 并列出 `make uya-core`。

---

## Phase 3：core 最小闭环验证

- [x] 从 seed 构建基础编译器。
  - 验证：`make from-c`
  - 结果：通过；`make from-c` 从 `bin/uya.c` 重新构建 `bin/uya`。
- [x] 构建 core 编译器。
  - 验证：`make uya-core`
  - 结果：通过；`make uya-core` 使用重新构建后的 `bin/uya` 生成并链接 `bin/uya-core`。
- [x] core `check` 正向用例通过。
  - 验证：`./bin/uya-core check tests/check_cli_no_main.uya`
  - 结果：通过；checker-only 路径接受无 `main` 的检查用例。
- [x] core `check` 错误用例失败且诊断明确。
  - 验证：`./bin/uya-core check tests/error_check_missing_brace.uya`
  - 结果：通过；命令按预期退出 1，并诊断 `tests/error_check_missing_brace.uya:3:1` 语法分析失败。
- [x] core C99 build 生成 C 文件。
  - 验证：`./bin/uya-core build tests/arithmetic.uya --c99 -o /tmp/arithmetic.c`
  - 验证：`test -s /tmp/arithmetic.c`
  - 结果：通过；生成 `/tmp/arithmetic.c`，文件非空。
- [x] 宿主 C 编译器能链接并运行 core 生成物。
  - 验证：编译 `/tmp/arithmetic.c` 并运行生成的二进制。
  - 验证：`cc -std=c99 -O2 -fno-builtin -Werror /tmp/arithmetic.c -o /tmp/arithmetic -lm`
  - 验证：`/tmp/arithmetic`
  - 结果：通过；生成物运行 5 个测试，失败数为 0。
- [x] `@c_import` smoke 通过。
  - 验证：`./bin/uya-core build tests/test_c_import_file.uya -o /tmp/test_c_import_file --c99`
  - 验证：`cc -x c -std=c99 -O2 -fno-builtin -Werror /tmp/test_c_import_file tests/fixtures/c_import/add_impl.c -o /tmp/test_c_import_file_bin -lm`
  - 验证：`/tmp/test_c_import_file_bin`
  - 结果：通过；生成物与 `fixtures/c_import/add_impl.c` 链接后运行 1 个测试，失败数为 0。
- [x] 多文件 / cross-deps smoke 通过。
  - 验证：`./bin/uya-core check tests/cross_deps/test_structs_main.uya tests/cross_deps/test_structs_a.uya tests/cross_deps/test_structs_b.uya`
  - 结果：通过；原单文件命令无法覆盖 cross-deps，已按执行规则修正为三文件输入，core checker 列出 3 个输入并通过。
- [x] package mode smoke 通过。
  - 验证：选取 `tests/fixtures/upm/` 下一个最小包夹具，确认 `uya.toml` / alias root 不退化。
  - 验证：`./bin/uya-core check tests/fixtures/upm/path_dep/app`
  - 结果：通过；core package mode 从 `uya.toml` 读取 `source-dir = "src"`，并通过 path dependency alias 收集到 `hello_pkg/src/file.uya`，checker 通过。
- [x] 语言级 `test` smoke 通过。
  - 验证：`./bin/uya-core test tests/test_test_basic.uya`
  - 结果：通过；`tests/test_test_basic.uya` 运行 2 个语言级测试，失败数为 0。原 TODO 的 `tests/test_basic.uya` 在当前仓库不存在，已按执行规则修正为现有基础测试文件。

---

## Phase 4：拆出非 core 能力

- [x] UPM CLI 保持独立构建。
  - 验证：`make cmds`
  - 结果：通过；命令先重建 full `bin/uya`，随后构建 `src/cmd/upm/main.uya` 并生成 `bin/cmd/upm`。
- [x] core 入口不依赖 UPM fetch / registry / publish / add / remove。
  - 验证：对 `src/cli/main_core.uya` 和 `src/compiler/` 做 import 检查。
  - 验证：`rg -n "^use .*cmd\\.upm|^use .*upm|^use .*fetch|^use .*registry|^use .*publish" src/cli/main_core.uya src/compiler`
  - 验证：`rg -n "cmd\\.upm|UPM|upm_|fetch|registry|publish|lockfile|materialize" src/cli/main_core.uya src/compiler`
  - 结果：通过；两条检查均无匹配，core 入口只保留本地只读 manifest/path dependency 解析，不导入 UPM CLI、fetch、registry、publish 或 lockfile/materialize 路径。
- [x] formatter 不进入 core 默认入口。
  - 当前状态：formatter 功能已移除，不再保留源码入口、独立命令或 Makefile 路径。
  - 结果：core/full 拆分不再需要验证 formatter 独立构建。
- [x] exec VM 标记为实验能力，不进入 core 默认入口。
  - 验证：core import 检查无 `use exec`。
  - 验证：`rg -n "^use exec|\\bexec\\b|--exec|--vm" src/cli/main_core.uya src/compiler`
  - 验证：`./bin/uya-core build tests/arithmetic.uya --exec`
  - 验证：`./bin/uya-core run tests/arithmetic.uya --vm`
  - 结果：通过；core 源码没有 `use exec`，唯一 `exec` 命中是 shell 运行 wrapper 的 POSIX `exec "$1"`；`--exec` 和 `--vm` 均被 `uya-core` 作为未知 core 选项拒绝。
- [x] microapp / image / payload 命令保留在 full 或独立入口。
  - 验证：core import 检查无 `use microapp`、`use kernel.image`、`use kernel.payload`。
  - 验证：`rg -n "^use microapp|^use kernel\\.image|^use kernel\\.payload|microapp|pack-image|inspect-image|verify-image|payload" src/cli/main_core.uya src/compiler`
  - 验证：`./bin/uya-core pack-image tests/arithmetic.uya`
  - 验证：`./bin/uya-core build tests/arithmetic.uya --app microapp`
  - 验证：`./bin/uya-core verify-image tests/arithmetic.uya`
  - 结果：通过；core 无 `use microapp`、`use kernel.image` 或 `use kernel.payload`。搜索只命中 core CLI 的非 core 子命令拒绝逻辑和 C99 codegen 显式关闭 `microapp_softvm_mode`；`pack-image`、`verify-image`、`--app microapp` 均被 `uya-core` 拒绝。
- [x] full 入口在迁移期仍可构建。
  - 验证：`make uya` 或当前等价 full 构建目标。
  - 结果：通过；`make uya` 使用当前 full `src/main.uya` 重新生成并链接 `bin/uya`，迁移期 full 入口仍可构建。

---

## Phase 5：core 门禁和自举

- [x] 新增 `make check-core`。
  - 内容：core 构建、core smoke、错误测试、多文件、package mode、`@c_import`、split-C。
  - 验证：`make check-core`
  - 结果：通过；Makefile 新增 `check-core` 目标并列入 `.PHONY` / `make help`，门禁覆盖 `uya-core` 构建、正向 check、错误诊断、多文件 cross-deps、package mode、`@c_import` 生成/链接/运行和 split-C 生成/链接/运行。
- [x] `uya-core` 能生成自身 C99。
  - 验证：使用 `bin/uya-core` 编译 core 入口。
  - 验证：`./bin/uya-core build src/cli/main_core.uya --project-root src/ --c99 --no-split-c -o /tmp/uya_core_stage2.c`
  - 验证：`test -s /tmp/uya_core_stage2.c`
  - 结果：通过；`bin/uya-core` 可独立解析 core 入口及 70 个依赖文件，并生成非空 C99 输出 `/tmp/uya_core_stage2.c`。
- [x] `uya-core` 能链接出 `bin/uya-core-stage2`。
  - 验证：stage2 二进制可运行 `--version` 或等价 smoke。
  - 验证：`cc -std=c99 -O2 -fno-builtin -Werror /tmp/uya_core_stage2.c -o bin/uya-core-stage2 -lm`
  - 验证：`bin/uya-core-stage2 --version`
  - 结果：通过；由 `bin/uya-core` 生成的 C99 可被宿主 C 编译器链接为 `bin/uya-core-stage2`，stage2 输出 `uya-core v0.10.0`。
- [x] 明确是否做 core C 输出一致性比较。
  - 若不比较，必须在文档或提交说明中解释原因。
  - 决策：本阶段不做 core C 输出字节级一致性比较。
  - 说明：当前 C99 生成物仍包含路径、分片布局和生成顺序等未规范化因素，过早加入字节级比较会把非语义差异变成门禁噪音；Phase 5 以 stage2 可生成、可链接、可运行和 `make check-core` smoke 作为自举判据。
  - 文档同步：`docs/core_compiler_refactor_plan.md` Phase 3 已写入同一决策和后续前提。
- [x] `make check-core` 稳定通过。
  - 验证：`make check-core`
  - 结果：通过；在新增门禁并完成 stage2 决策记录后再次运行，core 构建、checker smoke、错误诊断、多文件、package mode、`@c_import` 和 split-C 全部通过。
- [x] `make check` 继续通过，确认 full 仓库能力不退化。
  - 验证：`make check`
  - 首次结果：失败；当前 sandbox 检测到不支持 loopback socket，但 10 个 HTTP/WebSocket/shared DNS loopback 用例未纳入既有 `LOOPBACK_SKIP_TESTS`，导致 full 主测试集环境性失败。
  - 修复：更新 `tests/run_programs_parallel.sh`，把 `test_https_websocket_loopback`、`test_http_uyagin`、`test_http_uyagin_websocket`、`test_http_websocket_async`、`test_http_websocket_backpressure`、`test_http_websocket_handshake`、`test_http_websocket_heartbeat`、`test_http_websocket_json`、`test_http_websocket_reconnect` 和 `test_async_runtime_shared_dns` 加入 loopback 不可用环境下的跳过清单；支持 loopback 的环境仍会执行这些测试。
  - 复验：`make check`
  - 结果：通过；full 自举、主测试集、UPM、exec VM、microapp、SIMD、切片形参、C99 回归、`@syscall` 交叉和 benchmark C99 smoke 均通过。

---

## Phase 6：发布与安装边界

- [x] 明确迁移期二进制命名。
  - 候选：`uya-core`、`uya-full`、现有 `uya`
  - 决策：迁移期使用 `uya-core` 作为新增精简入口，现有 `uya` 继续作为 full 兼容入口，本阶段不引入 `uya-full` 重命名；`uya-core-stage2` 仅作为本地自举验证产物。
  - 文档同步：`docs/core_compiler_refactor_plan.md` 的目标形态已说明 `uya-core`、`uya` 和 `uya-core-stage2` 的角色。
- [x] 更新安装布局。
  - 目标：安装 core 入口时不强制安装非 core 命令。
  - 实现：新增 `make install-core`，安装 `uya-core` 和 `lib/`，不运行 `make cmds`，不安装 `bin/cmd/*`；现有 `make install` 保留 full 兼容安装语义。
  - 文档同步：`docs/core_compiler_refactor_plan.md` 已说明 `make install-core` 与 `make install` 的迁移期职责。
  - 验证：`make install-core PREFIX=/tmp/uya-install-core-check`
  - 验证：`test -x /tmp/uya-install-core-check/bin/uya-core`
  - 验证：`test ! -e /tmp/uya-install-core-check/bin/cmd`
  - 验证：`/tmp/uya-install-core-check/bin/uya-core --version`
  - 验证：`make help`
  - 结果：通过；core-only 安装生成 `uya-core v0.10.0`，且安装前缀未出现非 core 命令目录。
- [x] 更新 seed / backup 策略。
  - 明确 core seed 与 full seed 是否分开维护。
  - 决策：迁移期不拆分两套 seed；`backup/uya.c`、host/arch `backup/uya-*.c`、`backup/uya-hosted*.c` 和 `backup/uyacache/` 继续表示 full `src/main.uya` 编译器。
  - 决策：`bin/uya-core.c` 由 `make uya-core` 派生生成，`bin/uya-core-stage2` 仅作本地自举 smoke；本阶段不新增或提交 `backup/uya-core.c`。
  - 文档同步：`docs/core_compiler_refactor_plan.md` 已写入 seed / backup 策略和后续拆分触发条件。
  - 验证：核对 Makefile 现有 `backup`、`backup-seed`、`backup-hosted-seed`、`backup-all-seed`、`backup-all`、`release-flow` 均继续围绕 full `uya` seed；未引入 core seed 目标。
- [x] 更新 release 文档和 Makefile help。
  - 要求：用户能区分 `make uya-core`、`make uya`、`make check-core`、`make check`。
  - Makefile help：已明确 `make uya` 是 full 兼容入口、`make uya-core` 是精简 core 入口、`make check-core` 是 core 门禁、`make check` 是 full 门禁。
  - Release 文档：新增 `docs/releases/RELEASE_v0.10.1.md` 草案，记录 core/full 命令边界、install-core、seed 与 release 关系。
  - 验证：`make help`
  - 验证：`rg -n "make uya-core|make check-core|make check|make release|make install-core" docs/releases/RELEASE_v0.10.1.md Makefile`

---

## Phase 7：仓库清理

- [x] 删除或处理低风险临时文件。
  - 候选：`package-lock.json`
  - 候选：`.tmp_fmt_input.uya`
  - 候选：`.tmp_fmt_writeback.uya`
  - 候选：`.marscode/deviceInfo.json`
  - 处理：删除上述 4 个已跟踪临时/个人元数据文件；`package-lock.json` 无对应 `package.json`，两个 `.tmp_fmt_*.uya` 只是临时 formatter 输入，`.marscode/deviceInfo.json` 是个人设备 ID。
  - 防复发：`.gitignore` 新增 `.marscode/` 与 `.tmp_fmt_*.uya`。
  - 验证：`test ! -e package-lock.json`、`test ! -e .tmp_fmt_input.uya`、`test ! -e .tmp_fmt_writeback.uya`、`test ! -e .marscode/deviceInfo.json`
  - 验证：`git status --short -- package-lock.json .tmp_fmt_input.uya .tmp_fmt_writeback.uya .marscode/deviceInfo.json .gitignore`
  - 结果：通过；4 个候选文件均已不存在，Git 状态显示为删除，`.gitignore` 已更新；引用只剩清理计划/TODO 文档。
- [x] 更新当前开发指导中残留的 `compiler-c` / `compiler-mini` 路径。
  - 规则：当前开发指导和测试脚本提示必须指向 `make from-c` / `make from-c-native` / `make uya` / `make uya-hosted`。
  - 更新：`docs/DEVELOPMENT.md` 改为当前 seed / full / core / hosted 路线，移除 `make uya-c`、`make tests-c` 和旧 C 编译器目录作为当前开发路径。
  - 更新：`docs/testing_guide.md`、`tests/multifile/module_test/README.md`、`tests/test_export_for_c_usage.c` 的编译示例改为 `./bin/uya build ... --c99`。
  - 更新：`tests/run_cross_platform_tests.sh` 与 `tests/run_asm_tests.sh` 的缺编译器提示改为 `make from-c` / `make uya-hosted`。
  - 验证：`rg -n -e "compiler-c" -e "compiler-mini" -e "make uya-c\\b" -e "make tests-c\\b" -e "\\btests-c\\b" -e "bin/uya-c\\b" -e "build/compiler-mini" -e "\\buya-c\\b" docs/DEVELOPMENT.md docs/testing_guide.md tests/multifile/module_test/README.md tests/run_cross_platform_tests.sh tests/run_asm_tests.sh tests/test_export_for_c_usage.c`
  - 结果：通过；上述当前开发指导/测试提示文件已无旧 C 编译器路线命中。
- [x] 给历史 release notes 或历史文档加“历史路径，仅用于版本记录”说明。
  - 新增：`docs/releases/README.md`，说明早期 release notes 中的 `compiler-c/`、`compiler-mini/`、`bin/uya-c`、`make tests-c` 等旧路径仅用于版本记录，当前入口以 Makefile / DEVELOPMENT / AGENTS 为准。
  - 更新：`docs/ASM_TODO.md`、`docs/asm_design.md`、`docs/extern_var_impl_plan.md`、`docs/number_literals_enhancement.md`、`docs/syscall_design.md`、`docs/todo_mini_to_full.md`、`docs/uya_nostdlib_plan.md` 顶部加入同样的历史路径说明。
  - 更新：`docs/builtin_functions.md` 的 `compiler-c-spec/UYA_MINI_SPEC.md` 参考改为“历史路径，仅用于版本记录”。
  - 验证：`rg -n "历史路径说明|历史路径，仅用于版本记录" docs/releases/README.md docs/ASM_TODO.md docs/asm_design.md docs/extern_var_impl_plan.md docs/number_literals_enhancement.md docs/syscall_design.md docs/todo_mini_to_full.md docs/uya_nostdlib_plan.md docs/builtin_functions.md`
- [x] 为已完成的 TODO / PLAN / REPORT 建立 `docs/archive/` 归档索引。
  - 新增：`docs/archive/README.md`。
  - 处理：建立已完成或历史归档候选索引，不物理移动原文件，避免破坏现有交叉引用。
  - 覆盖：`ASM_TODO.md`、`ASM_STAGE3_COMPLETION_REPORT.md`、`ASM_FIXES_REPORT.md`、`ASM_STATUS_REPORT.md`、`ASM_IMPLEMENTATION_PROGRESS.md` 和 `todo_async_full_language_dynamic_resources_completed.md`。
  - 说明：`todo_core_compiler_refactor.md` 与 `core_compiler_refactor_plan.md` 仍在执行中，暂不归档。
  - 验证：`test -f docs/archive/README.md`
  - 验证：`rg -n "ASM_TODO|todo_async_full_language_dynamic_resources_completed|todo_core_compiler_refactor" docs/archive/README.md`
- [x] 归档前运行文档校验。
  - 验证：`git diff --check`
  - 结果：通过；当前文档、脚本和 Makefile diff 未发现 whitespace/error。

---

## 完成条件

- [x] `uya-core` 可作为普通语言用户的默认编译入口。
  - 证据：`make check-core` 通过，覆盖 core check、错误诊断、多文件、package mode、`@c_import` 和 split-C。
  - 证据：`./bin/uya-core run tests/arithmetic.uya` 通过，生成、链接并运行 5 个语言级测试，失败数为 0。
- [x] package mode 构建能力不退化。
  - 证据：`./bin/uya-core check tests/fixtures/upm/path_dep/app` 通过。
  - 结果：core package mode 从 `uya.toml` 读取 `source-dir = "src"`，并只读解析 path dependency alias，收集到 app `main.uya` 与 `hello_pkg/src/file.uya` 两个输入后 checker 通过。
- [x] core 自举链路稳定。
  - 证据：`./bin/uya-core build src/cli/main_core.uya --project-root src/ --c99 --no-split-c -o /tmp/uya_core_stage2.c` 通过，收集 70 个依赖文件并生成 C99。
  - 证据：`test -s /tmp/uya_core_stage2.c` 通过，`wc -c /tmp/uya_core_stage2.c` 显示生成物大小为 7527931 字节。
  - 证据：`cc -std=c99 -O2 -fno-builtin -Werror /tmp/uya_core_stage2.c -o bin/uya-core-stage2 -lm` 通过。
  - 证据：`bin/uya-core-stage2 --version` 输出 `uya-core v0.10.0`。
- [x] full 入口非核心能力仍可通过独立命令或兼容入口访问。
  - 证据：`./bin/uya --version` 输出 `v0.10.0`，迁移期 full 兼容入口仍可启动。
  - 证据：`make cmds` 通过，先重建 full `bin/uya`，再构建 `src/cmd/upm/main.uya` 并生成 `bin/cmd/upm`。
  - 证据：`test -x bin/cmd/upm` 通过，独立 UPM 命令产物存在。
  - 说明：formatter 功能已移除，不再提供构建目标或独立命令兼容入口。
  - 关联验证：Phase 5 的 `make check` 已覆盖 full 自举、UPM、exec VM、microapp、SIMD、C99 回归和 benchmark C99 smoke。
- [x] `make check-core` 稳定通过。
  - 证据：完成条件阶段重新运行 `make check-core` 通过。
  - 覆盖：构建 `bin/uya-core`、`--version`、正向 checker、错误诊断、多文件 cross-deps、package mode、`@c_import` 生成/链接/运行和 split-C 生成/链接/运行。
  - 结果：`@c_import` 用例 1 个测试通过，split-C arithmetic 用例 5 个测试全部通过，最终输出 `core 编译器门禁通过`。
- [x] `make check` 继续通过。
  - 证据：完成条件阶段重新运行 `make check` 通过。
  - 覆盖：full 自举、主测试集、证明优化、默认顶层函数发射、UPM、exec VM、microapp、SIMD select C、切片形参 C99、结构体数组字段复制、typed route 泛型、macOS hosted 单文件 seed extern、`@syscall` AArch64/ARM32 交叉、SIMD NEON/AArch64/ARM32 和 `benchmarks/http_bench.uya` C99 smoke。
  - 结果：最终汇总显示 `总计: 1 个测试`、`通过: 1`、`失败: 0`，并输出 `验证通过`。
- [x] release seed 与安装布局已同步。
  - 证据：`make install-core PREFIX=/tmp/uya-install-core-final` 通过，重新构建 `bin/uya-core` 后安装 `uya-core` 和 `lib/`。
  - 证据：`test -x /tmp/uya-install-core-final/bin/uya-core` 与 `test ! -e /tmp/uya-install-core-final/bin/cmd` 均通过，core-only 安装前缀未包含非 core 命令目录。
  - 证据：`/tmp/uya-install-core-final/bin/uya-core --version` 输出 `uya-core v0.10.0`。
  - 证据：Makefile 的 `backup`、`backup-seed`、`backup-hosted-seed`、`backup-all-seed`、`backup-all` 和 `release-flow` 区段继续围绕 full `uya` / `backup/uya.c` / `backup/uya-hosted*.c` / `backup/uyacache/`，未新增 core seed 复制或 `backup/uya-core.c` 规则。
  - 文档同步：`docs/core_compiler_refactor_plan.md` 与 `docs/releases/RELEASE_v0.10.1.md` 均明确本阶段不维护独立 core seed；`bin/uya-core.c` 是本地构建产物，`bin/uya-core-stage2` 只作自举 smoke，不安装、不发布、不作为 seed 提交。
