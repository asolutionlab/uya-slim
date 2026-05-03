# Uya 子命令外置化 TODO

**状态**: executable TODO
**更新日期**: 2026-05-03
**配套设计**: `docs/cmd_subcommand_split_design.md`

---

## 执行原则

- 先读 `docs/cmd_subcommand_split_design.md`、`docs/uya_ai_prompt.md` 和相邻测试。
- 不臆造 Uya 语法；不确定时先搜索 `src/`、`lib/`、`tests/` 的既有写法。
- 按 TDD 推进：先加调度测试，再改实现。
- 保留 `uya <file.uya> ...` 隐式编译入口，避免自举死锁。
- 公开 `uya build/run/test/fmt/upm` 必须走 `cmd/xxx`，不要静默回退内部实现。

---

## Phase 0：基线确认

- [ ] 查看工作树，确认没有未预期改动：`git status --short`。
- [ ] 阅读当前入口：`src/main.uya` 的 `CommandType`、`print_usage()`、`parse_args()`、`export fn main()`。
- [ ] 阅读 fmt 独立入口：`src/fmt.uya` 的 `fmt_main()` 与 `uyafmt_main()`。
- [ ] 阅读构建脚本：`Makefile` 的 `uya`、`from-c`、`install`、`clean` 目标，以及 `src/compile.sh` 的主文件选择逻辑。
- [ ] 跑最小基线，记录当前行为：

```bash
./bin/uya --version || true
./bin/uya build tests/test_errno.uya -o /tmp/uya_baseline_errno --no-split-c
./bin/uya test tests/test_errno.uya
./bin/uya fmt tests/test_errno.uya >/tmp/uya_baseline_fmt.out
```

---

## Phase 1：先补测试

- [ ] 新增 `tests/test_cmd_dispatch.sh`，脚本开头使用 `set -euo pipefail`。
- [ ] 测试开始时确认 `bin/uya` 存在；若 `bin/cmd/*` 不存在，提示先运行 `make cmds`。
- [ ] 覆盖 `uya build` 与直调 `cmd/build`：

```bash
./bin/uya build tests/test_errno.uya -o /tmp/uya_cmd_build --no-split-c
./bin/cmd/build tests/test_errno.uya -o /tmp/uya_cmd_build_direct --no-split-c
```

- [ ] 覆盖 `uya test` 与直调 `cmd/test` 退出码一致：

```bash
./bin/uya test tests/test_errno.uya
./bin/cmd/test tests/test_errno.uya
```

- [ ] 覆盖 `uya fmt` 与直调 `cmd/fmt` 输出一致：

```bash
./bin/uya fmt tests/test_errno.uya >/tmp/uya_cmd_fmt_a.out
./bin/cmd/fmt tests/test_errno.uya >/tmp/uya_cmd_fmt_b.out
cmp /tmp/uya_cmd_fmt_a.out /tmp/uya_cmd_fmt_b.out
```

- [ ] 覆盖 `uya upm --help` 与直调 `cmd/upm --help` 均退出 0。
- [ ] 覆盖缺失命令的错误路径：临时重命名 `bin/cmd/build`，确认 `./bin/uya build ...` 返回非 0，错误信息包含 `cmd/build` 和 `make cmds`。
- [ ] 将该脚本接入合适的 Makefile 快速目标，例如 `tests-uya` 或新增 `cmd-dispatch-check`，避免扩大默认慢路径前先本地验证。

---

## Phase 2：拆出共享编译驱动

- [ ] 在 `src/` 或 `src/cmd/common/` 创建共享驱动模块，避免复制 `src/main.uya` 的大段逻辑。
- [ ] 将当前 `parse_args()` 改造成可指定默认命令和起始参数的函数，例如：

```text
parse_args_from(default_command, argv_start, allow_optional_subcommand, ...)
```

- [ ] 将当前 `export fn main()` 中 `build/run/test` 共享流程提取为可复用函数，例如：

```text
compiler_driver_main(default_command, argv_start)
```

- [ ] 保持 `build`、`run`、`test` 的原有语义：默认 C99 后端、`run/test` 单文件 C、`run -- <args>`、test 默认栈、microapp 特殊路径、`@c_import` 链接计划。
- [ ] 保持 `pack-image`、`inspect-image`、`verify-image`、`--outlibc` 暂由主程序处理，不要在本阶段移动。
- [ ] 所有新增 `export fn` 前写 `///` 注释，说明功能、参数和返回值。
- [ ] 提取后先用隐式入口验证编译器仍能工作：

```bash
./bin/uya tests/test_errno.uya -o /tmp/uya_implicit_errno --no-split-c
```

---

## Phase 3：实现主程序调度器

- [ ] 在 `src/main.uya` 新增 `is_external_cmd(name)`，识别 `build/run/test/fmt/upm`。
- [ ] 新增 `build_external_cmd_path(cmd_name, out, out_cap)`，基于 `get_compiler_dir(get_argv(0), ...)` 生成 `cmd/<name>` 路径，Windows 目标补 `.exe`。
- [ ] 新增 `dispatch_external_cmd(cmd_name, strip_subcommand)`：
  - [ ] 构造新的 argv 数组，`argv[0]` 为 `cmd_path`。
  - [ ] `strip_subcommand != 0` 时从原 `argv[2]` 开始复制参数。
  - [ ] 保留 `--` 及其后的所有参数原样。
  - [ ] argv 末尾写入 `null`。
  - [ ] 使用 `execve(cmd_path, argv, saved_envp)` 或同等 argv API。
  - [ ] `execve` 失败时根据 errno 打印 `cmd_path`、原因和 `make cmds` 提示。
- [ ] 在 `export fn main()` 开头做分流：
  - [ ] `argv[1]` 是外置命令：立即 `dispatch_external_cmd(argv[1], 1)`。
  - [ ] `argv[1]` 是 `--version` / `-v`：保持当前版本输出。
  - [ ] 其他显式内部命令保持原路径。
  - [ ] 非命令参数继续走隐式编译入口。
- [ ] 可选新增调试环境变量 `UYA_CMD_TRACE=1`，打印实际调度路径，便于测试确认没有走内部实现。
- [ ] 不要使用 `system()` 拼接公开子命令调用。

---

## Phase 4：新增 `src/cmd/xxx` 入口

- [ ] 创建 `src/cmd/build/main.uya`，入口调用共享驱动的 `COMMAND_BUILD`。
- [ ] 创建 `src/cmd/run/main.uya`，入口调用共享驱动的 `COMMAND_RUN`。
- [ ] 创建 `src/cmd/test/main.uya`，入口调用共享驱动的 `COMMAND_TEST`。
- [ ] 三个命令入口都支持可选重复子命令名，例如 `cmd/build build file.uya`。
- [ ] 创建 `src/cmd/fmt/main.uya`：
  - [ ] 默认调用 `uyafmt_main()`。
  - [ ] 若 `argv[1] == "fmt"`，跳过该参数或调用兼容入口。
- [ ] 创建 `src/cmd/upm/main.uya`：
  - [ ] `--help` / `-h` 打印用法并退出 0。
  - [ ] `--version` / `-v` 打印版本并退出 0。
  - [ ] 未实现命令打印提示并退出 2。
- [ ] 每个公开入口前写 `///` 注释，符合仓库 Uya 代码风格。

---

## Phase 5：改造构建系统生成 `bin/cmd/*`

- [ ] 在 `Makefile` 增加 `UYA_CMD_NAMES := build run test fmt upm`。
- [ ] 增加 `cmds`、`cmd-build`、`cmd-run`、`cmd-test`、`cmd-fmt`、`cmd-upm` 目标。
- [ ] `make cmds` 生成：

```text
bin/cmd/build
bin/cmd/run
bin/cmd/test
bin/cmd/fmt
bin/cmd/upm
```

- [ ] 命令构建优先使用隐式编译入口，避免循环依赖：

```bash
./bin/uya src/cmd/build/main.uya -o bin/cmd/build --c99 --no-split-c
```

- [ ] 若 `src/cmd/xxx/main.uya` 的 `use` 解析受项目根影响，优先增强 `src/compile.sh`：
  - [ ] 新增 `--entry <相对 src 的入口>`，默认仍是 `main.uya`。
  - [ ] 新增 `--project-root <目录>` 或等价内部变量，命令入口编译时设为 `src/`。
  - [ ] 输出名含 `/` 时创建 `src/build/cmd/` 和 `bin/cmd/`。
- [ ] `make uya` 成功生成 `bin/uya` 后调用或提示 `make cmds`；推荐默认自动生成，确保公开子命令可用。
- [ ] `make from-c` / `make from-c-native` 完成 `bin/uya` 后也应生成 `cmds`，否则冷启动后 `uya build` 会缺命令。
- [ ] `make clean` 清理 `bin/cmd/` 和 `src/build/cmd/`。
- [ ] `make install` 依赖 `cmds`，并复制 `bin/cmd/*` 到 `$(INSTALL_BINDIR)/cmd/`。
- [ ] `make help` 增加 `make cmds` 和安装布局说明。

---

## Phase 6：文档同步

- [ ] 更新 `docs/UYA_BUILD_RUN.md`：说明 `uya build/run/test` 由 `cmd/build`、`cmd/run`、`cmd/test` 执行。
- [ ] 更新 `docs/TESTING.md`：加入 `make cmds` 和 `tests/test_cmd_dispatch.sh`。
- [ ] 如 `upm` 帮助文字采用 `upm` 而不是 `uyapm`，在相关文档中说明二者关系或保留为后续 TODO。
- [ ] 如果没有改变语言语法、BNF 或内建函数，不需要升级 `docs/uya.md` 规范版本。

---

## Phase 7：验证与收口

- [ ] 格式/空白检查：

```bash
git diff --check
```

- [ ] 生成命令程序：

```bash
make cmds
ls -l bin/cmd/build bin/cmd/run bin/cmd/test bin/cmd/fmt bin/cmd/upm
```

- [ ] 跑新增调度测试：

```bash
./tests/test_cmd_dispatch.sh
```

- [ ] 跑快速编译/测试路径：

```bash
./bin/uya build tests/test_errno.uya -o /tmp/uya_cmd_errno --no-split-c
./bin/uya test tests/test_errno.uya
./bin/uya fmt tests/test_errno.uya >/tmp/uya_cmd_errno_fmt.out
./bin/uya upm --help
```

- [ ] 验证安装布局：

```bash
make install PREFIX=/tmp/uya-cmd-install
/tmp/uya-cmd-install/bin/uya upm --help
/tmp/uya-cmd-install/bin/uya build tests/test_errno.uya -o /tmp/uya_installed_errno --no-split-c
```

- [ ] 跑自举快速验证：

```bash
make tests-uya
```

- [ ] 收口或准备提交前运行完整规则：

```bash
make clean
make backup-all
```

---

## 回滚策略

- [ ] 如果 `cmd/xxx` 构建失败，先保持 `src/main.uya` 的隐式编译入口可用，不要破坏 `make uya`。
- [ ] 如果公开调度失败，可临时只让 `fmt/upm` 外置，`build/run/test` 保持内部，但测试中标记未完成项。
- [ ] 不要删除旧逻辑；先抽成共享驱动，再由主程序和命令入口共用。
- [ ] 不要提交 `bin/cmd/*` 生成物，除非仓库策略后来明确要求跟踪这些产物。
