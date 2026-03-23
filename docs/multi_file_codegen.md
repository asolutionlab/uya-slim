# 多文件 C 输出（`--split-c-dir`）

## 用途

在 C99 后端将生成代码拆成 **`uya_part1.c`**（前导、头文件与依赖、`const char` 字符串池）与 **`uya_part2.c`**（其余生成代码），并在输出目录写入 **`Makefile`**。

链接前用 **`cat uya_part1.c uya_part2.c > uya_split_all.c`** 合并为**与单文件模式顺序一致**的翻译单元，再 **`gcc -c uya_split_all.c`** 与链接。这样可保留两份源码便于阅读/增量，同时避免多 TU 下 `static`/前向声明顺序问题；真正的「多路 `gcc -c` 并行」需后续引入共享头或按 `.uya` 镜像拆分。

默认单文件 `uya.c` / 单条 `gcc` 路径不变；仅当指定本选项时启用上述多文件路径。

## 用法

```bash
# 命令行
uya build <输入.uya ...> --split-c-dir <目录> -o <可执行文件> --c99

# 或环境变量（命令行未指定时）
export UYA_SPLIT_C_DIR=/path/to/uyacache
```

- **`<目录>`**：将创建/使用 `uya_part1.c`、`uya_part2.c`、`Makefile`。
- **`-o`**：最终可执行文件路径，传给 `make UYA_OUT=...`。
- **并行度**：`make -j` 的任务数由环境变量 **`UYA_GCC_JOBS`** 控制（默认在实现中为 `4`，若未设置）。

## 与 `uya build` / `run` / `test`

生成 C 后若需要链接宿主工具链，多文件模式下会调用：

`make -C <split-dir> -j<jobs> UYA_OUT=<...> CC=... CFLAGS=... LDFLAGS=...`

与单文件模式下的一条 `cc ... one.c -o exe` 并列存在；**`--nostdlib`** 时链接参数会附加 `-nostdlib -static -lgcc`（与单文件行为对齐，且当前多文件 `nostdlib` 链接仅支持 **Linux** 目标）。

## 自举与 `compile.sh`

- **`src/compile.sh`**：若设置环境变量 **`UYA_SPLIT_C_DIR`**，主编译阶段与 `uya build` 一样生成 `uya_part1.c` / `uya_part2.c` + `Makefile`，链接时执行 **`make -C <dir> -j$UYA_GCC_JOBS`**（与 `src/main.uya` 中 `link_split_with_make` 使用相同的 `CC` / `CFLAGS` / `LDFLAGS` 约定）。
- **自举对比（`compile.sh --c99 -e -b`）**：
  - 默认：对两次生成的 **单文件 C** 做 **`diff`**（与此前一致）。
  - 若设置了 **`UYA_SPLIT_C_DIR`**，或设置 **`UYA_BOOTSTRAP_COMPARE_BIN=1`**（或 `true`/`yes`）：改为先由自举编译器生成输出，再链接出 **`$BUILD_DIR/uya_bootstrap_compare`**，与 **`bin/uya`** 做 **`cmp -s`**（字节级一致）；多文件自举输出写入 **`$BUILD_DIR/bootstrap_split_c`**，避免覆盖主编译的 split 目录。

## 实现说明（节选）

- 顶层非 `export` 函数在 split 模式下**不再**生成 `static`，以便跨两个翻译单元链接。
- 字符串常量在 part1 中为**文件级** `const char strN[]`（非 `static`），part2 开头生成对应 `extern` 声明。
- 宏展开等阶段追加的**延迟字符串**仍写入 part1；若遇极端用例与 part2 引用顺序冲突，可再收紧（当前以自举与测试通过为准）。

## 与 `make check` / 注意事项

- **不要在测试阶段依赖全局 `UYA_SPLIT_C_DIR`**：`make check` / `make tests` 会在调用 `tests/run_programs_parallel.sh` 时**显式清空** `UYA_SPLIT_C_DIR`。否则并行用例会拿不到 `-o` 指定的单文件 `.c`（split 模式下代码写入 `uya_part1/2.c`），且易与嵌套 `make` 行为冲突。
- **自举编译仍可使用 split**：若你在 shell 里 `export UYA_SPLIT_C_DIR=...` 后执行 `make check`，**`make uya` / `make b`** 仍会继承该变量，用于生成 `bin/uya`；仅测试子进程被清空。
- **外层 `make -j` 与嵌套 `make`**：此前在 GNU make 开启 jobserver 时，子进程中的 `make -C <split>` 若继承 `MAKEFLAGS` 可能**死锁（表现为卡死）**。实现上在嵌套 `make` 前清除 `MAKEFLAGS` / `MFLAGS` / `GNUMAKEFLAGS`（见 `link_split_with_make` 与 `compile.sh` 的 `env -u …`）。
- **路径**：请使用**绝对路径**或确认**当前工作目录**；相对路径 `.uyacache` 会随 `cwd` 指到不同目录。拼写错误（如 `.uyacach`）会生成到意料外的目录。

## 可选冒烟测试

仓库根目录执行：

```bash
bash tests/split_c_smoke.sh
```

**更新日期**：2026-03-23
