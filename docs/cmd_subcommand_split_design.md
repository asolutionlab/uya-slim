# Uya 子命令外置化设计：`uya` → `cmd/xxx`

**状态**: design draft
**更新日期**: 2026-05-03
**范围**: `build` / `run` / `test` / `fmt` / `upm` 五个公开小命令

---

## 1. 背景

当前 `src/main.uya` 同时承担编译器入口、命令行解析、`build/run/test` 编译运行逻辑、microapp 辅助命令、`fmt` 子命令跳转、`--outlibc` 等职责。`src/fmt.uya` 已经具备独立 CLI 入口 `uyafmt_main()`，但公开路径仍是 `uya fmt` 内嵌调用。

本设计将公开小命令改为由 `uya` 主程序调度同目录下的 `cmd/xxx` 可执行程序：

```text
bin/
  uya
  cmd/
    build
    run
    test
    fmt
    upm

src/
  main.uya                  # 主入口：公开子命令调度 + 自举兼容入口
  cmd/
    build/main.uya
    run/main.uya
    test/main.uya
    fmt/main.uya
    upm/main.uya
    common/...              # 可选：共享命令包装与驱动代码
```

安装后保持同样的相对布局，例如 `out/bin/uya` 调用 `out/bin/cmd/build`。

---

## 2. 目标

- `uya build ...` 调用 `$(dirname uya)/cmd/build ...`。
- `uya run ...` 调用 `$(dirname uya)/cmd/run ...`。
- `uya test ...` 调用 `$(dirname uya)/cmd/test ...`。
- `uya fmt ...` 调用 `$(dirname uya)/cmd/fmt ...`。
- `uya upm ...` 调用 `$(dirname uya)/cmd/upm ...`。
- 每个 `xxx` 的入口源码放在 `src/cmd/xxx/main.uya`。
- 构建系统能生成 `bin/cmd/xxx` 可执行程序，并在 `make install` 时安装到 `$(INSTALL_BINDIR)/cmd/xxx`。
- 直接运行 `bin/cmd/xxx ...` 与 `uya xxx ...` 保持等价退出码和参数语义。
- 保留历史隐式编译入口 `uya <file.uya> ...`，用于自举、`src/compile.sh` 和旧脚本兼容。

---

## 3. 非目标

- 不重新设计 Uya 语言语法、BNF 或内建函数。
- 不在本轮重做包管理器完整功能；`upm` 可以先提供可执行骨架和帮助信息。
- 不移动 `pack-image` / `inspect-image` / `verify-image` / `--outlibc`，除非后续单独立项。
- 不要求第一阶段让 `bin/uya` 变成极小纯 dispatcher；为避免自举死锁，主程序仍保留隐式编译能力。

---

## 4. 关键约束

### 4.1 自举不能死锁

如果 `uya build` 立即外置，而构建 `cmd/build` 又依赖 `uya build`，会形成循环。解决方案：

- 公开显式子命令 `uya build/run/test/fmt/upm` 走外置 `cmd/xxx`。
- 隐式编译入口 `uya <source> -o <out> ...` 继续走主程序内部编译驱动。
- `src/compile.sh` 和新增 `make cmds` 使用隐式入口编译 `src/cmd/xxx/main.uya`。
- `make from-c` / `make uya` 完成 `bin/uya` 后，应继续生成 `bin/cmd/*`。

这样即使 `bin/cmd/build` 尚不存在，仓库仍能用 `bin/uya src/cmd/build/main.uya -o bin/cmd/build --c99` 生成它。

### 4.2 参数必须原样传递

调度器不得用 shell 拼接命令字符串，避免空格、引号、`--`、运行时参数和路径字符被错误解释。优先使用 `execve`：

```text
uya run app.uya -- a "b c"
↓
execve("<uya_dir>/cmd/run", ["<uya_dir>/cmd/run", "app.uya", "--", "a", "b c", null], envp)
```

`execve` 成功后不返回；失败时打印清晰错误并返回类 shell 退出码：找不到命令返回 `127`，不可执行返回 `126`，其他失败返回 `1`。

### 4.3 直接运行也要可用

每个命令程序应接受两种 argv 形式：

```text
bin/cmd/build main.uya -o app
bin/cmd/build build main.uya -o app   # 兼容调试或旧包装，允许但不推荐
```

公开调度器推荐传递第一种形式，即去掉 `uya` 后面的子命令名。

### 4.4 模块解析需要项目根

`src/cmd/xxx/main.uya` 位于子目录。若命令入口需要 `use cmd.common.*` 或 `use fmt`，编译器依赖收集必须以 `src/` 作为项目根，而不是 `src/cmd/xxx/`。实现时推荐新增或复用一个“项目根覆盖”机制：

- `compile_files` 增加 `project_root_override` 参数，非空时优先作为模块查找根。
- `src/compile.sh` 增加 `--entry cmd/build/main.uya` 和 `--project-root src/` 等价能力。
- 如果暂不改 `compile.sh`，Makefile 也可以显式传入命令入口和依赖文件，但仍要确保 `use` 解析稳定。

---

## 5. 目标架构

### 5.1 `src/main.uya` 职责

`src/main.uya` 进入 `main()` 后先做最小分流：

1. `argc < 2`：打印主帮助。
2. `argv[1]` 是 `build/run/test/fmt/upm`：调用 `dispatch_cmd(argv[1], drop_first_subcommand=true)`。
3. `argv[1]` 是 `--version` / `-v`：主程序直接处理。
4. `argv[1]` 是 `pack-image` / `inspect-image` / `verify-image` / `--outlibc`：第一阶段仍由主程序直接处理。
5. 其他情况：按历史默认 `build` 语义走内部编译驱动，用于 `uya file.uya -o out`。

建议新增辅助函数：

```uya
fn is_external_cmd(name: &byte) i32
fn build_cmd_path(cmd_name: &byte, out: &byte, out_cap: usize) i32
fn dispatch_external_cmd(cmd_name: &byte, strip_subcommand: i32) i32
```

这些函数应保持短小，并复用已有 `get_compiler_dir()`、`PATH_MAX`、`get_target_exe_suffix()` 或等价平台后缀逻辑。

### 5.2 `build/run/test` 命令程序

三者应共享编译驱动，避免复制 `src/main.uya` 的大量实现。推荐结构：

```text
src/cmd/common/compiler_driver.uya
  export fn compiler_driver_main(default_command: CommandType, argv_start: i32) i32

src/cmd/build/main.uya
  export fn main() i32 { return compiler_driver_main(CommandType.COMMAND_BUILD, 1); }

src/cmd/run/main.uya
  export fn main() i32 { return compiler_driver_main(CommandType.COMMAND_RUN, 1); }

src/cmd/test/main.uya
  export fn main() i32 { return compiler_driver_main(CommandType.COMMAND_TEST, 1); }
```

落地时可以先把当前 `parse_args()` 和 `main()` 中的编译主流程拆为可复用函数，再让 `src/main.uya` 的隐式入口与 `src/cmd/*` 共用同一份源码。

### 5.3 `fmt` 命令程序

`src/fmt.uya` 已提供两个入口：

- `fmt_main()`：适配 `uya fmt ...`，从 `argv[2]` 开始解析。
- `uyafmt_main()`：适配独立工具，从 `argv[1]` 开始解析。

`src/cmd/fmt/main.uya` 应优先调用 `uyafmt_main()`；如检测到 `argv[1] == "fmt"`，可调用兼容路径或跳过该参数。

### 5.4 `upm` 命令程序

当前规范文档中提到官方包管理器名称 `uyapm`，但本轮用户入口指定为 `upm`。第一阶段建议实现最小可执行骨架：

```text
uya upm --help      # 退出 0，打印 upm 用法
uya upm --version   # 退出 0，打印 Uya/upm 版本
uya upm <其他命令>  # 退出 2，提示功能尚未实现
```

后续可把 `upm` 作为短命令，`uyapm` 作为独立工具名或别名，另行写包管理设计。

---

## 6. 构建系统设计

### 6.1 Makefile 目标

建议新增变量和目标：

```make
UYA_CMD_NAMES := build run test fmt upm
UYA_CMD_BINS := $(patsubst %,bin/cmd/%,$(UYA_CMD_NAMES))

.PHONY: cmds cmd-build cmd-run cmd-test cmd-fmt cmd-upm
cmds: $(UYA_CMD_BINS)

bin/cmd/%: uya
	@$(MAKE) cmd-$*
```

每个 `cmd-%` 目标使用隐式编译入口或增强后的 `src/compile.sh`：

```text
bin/uya src/cmd/<name>/main.uya -o bin/cmd/<name> --c99 --no-split-c
```

如果命令入口依赖 `src/` 下共享模块，优先改造 `src/compile.sh --entry cmd/<name>/main.uya --project-root src/`，由脚本统一处理依赖、CFLAGS、LDFLAGS、nostdlib/hosted 差异和输出目录创建。

### 6.2 输出目录

需要确保以下目录自动创建：

- `bin/cmd/`
- `src/build/cmd/`（若生成 `src/build/cmd/<name>.c`）
- split-C 输出目录（如命令构建允许多文件 C）

第一阶段建议命令程序默认 `--no-split-c`，降低构建系统变量交叉影响；确认稳定后再允许 split-C。

### 6.3 `make install`

安装目标应复制：

```text
bin/uya               → $(INSTALL_BINDIR)/uya
bin/cmd/<name>        → $(INSTALL_BINDIR)/cmd/<name>
lib/                  → $(LIBDIR)/...
docs/                 → $(DOCDIR)/...
tests/                → $(TESTSDIR)/...
```

安装前应依赖或检查 `cmds`，避免安装出只有 `uya` 没有 `cmd/*` 的不完整布局。

### 6.4 `make clean`

`make clean` 应清理生成物：

- `bin/cmd/`
- `src/build/cmd/`
- 命令构建产生的临时 C、对象文件和 split-C 目录

不要清理 `src/cmd/*` 源码。

---

## 7. 测试策略

### 7.1 新增调度测试

建议新增 `tests/test_cmd_dispatch.sh`，覆盖：

- `bin/uya build tests/test_errno.uya -o /tmp/uya_cmd_build --no-split-c` 成功。
- `bin/cmd/build tests/test_errno.uya -o /tmp/uya_cmd_build_direct --no-split-c` 成功。
- `bin/uya test tests/test_errno.uya` 与 `bin/cmd/test tests/test_errno.uya` 退出码一致。
- `bin/uya fmt tests/test_errno.uya` 与 `bin/cmd/fmt tests/test_errno.uya` 输出一致。
- `bin/uya upm --help` 与 `bin/cmd/upm --help` 退出 0。
- 临时隐藏 `bin/cmd/build` 后，`bin/uya build ...` 给出明确错误并返回非 0。

### 7.2 回归验证

开发阶段优先运行：

```bash
git diff --check
make cmds
./tests/test_cmd_dispatch.sh
./bin/uya test tests/test_errno.uya
```

收口阶段运行：

```bash
make tests-uya
make check
```

准备提交前按仓库规则运行：

```bash
make clean
make backup-all
```

---

## 8. 兼容性与风险

- **缺少 `cmd/xxx`**：公开子命令应失败并提示运行 `make cmds` 或重新安装，不建议静默回退内部实现。
- **旧脚本使用 `uya file.uya`**：继续由隐式编译入口支持。
- **旧脚本使用 `uya build ...`**：构建后行为应等价，但依赖 `bin/cmd/build` 存在。
- **参数转义风险**：必须使用 `execve` 或等价 argv API，不使用 `system("cmd ...")` 拼接。
- **项目根风险**：`src/cmd/xxx` 的 `use` 解析必须有测试覆盖，防止只在仓库根可用、安装后失效。
- **自举种子风险**：如果 `make backup-all` 更新 `backup/uya.c`，同一提交应包含对应备份；`bin/cmd/*` 属于本地产物，不应手动加入提交。

---

## 9. 完成定义

- `make cmds` 生成 `bin/cmd/build`、`bin/cmd/run`、`bin/cmd/test`、`bin/cmd/fmt`、`bin/cmd/upm`。
- `uya build/run/test/fmt/upm` 均实际执行对应 `cmd/xxx`。
- `bin/cmd/xxx ...` 可直接运行。
- `src/cmd/xxx/main.uya` 是每个命令的入口源码。
- `make install` 安装 `cmd/xxx`，安装后的 `uya xxx` 可用。
- 相关快速测试、`make tests-uya` 和最终 `make backup-all` 按阶段通过。
