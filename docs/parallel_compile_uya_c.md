# 能否把 `uya.c` 拆开让 gcc 并行编译？

## 结论（当前自举产物）

**不建议**用脚本对 `bin/uya.c` / `backup/uya.c` 做「按行」或「大致均分」拆分后多路 `gcc -c` 再链接。

原因：生成的 C 里存在大量 **`static` 函数**（文件内链接）。拆成多个 `.c` 后，这些符号在别的翻译单元**不可见**，会出现未定义引用或重复定义；除非对整份 C 做完整语法级拆分并改写链接方式，否则**无法保证正确**。

可行方向见下文「推荐做法」。

## 为何不能简单拆分

- `static` 函数/变量只在**当前** `.c` 内有效；拆到 `part2.c` 后，`part1.c` 里对它们的调用会失败。
- 若用脚本去掉 `static`，会误伤 `static const char strN[]` 等数据，且仍需保证**每个函数体完整**落在同一 TU，不能从中间截断。
- 自举生成的 `uya.c` 是**单一大翻译单元**设计，没有稳定的「模块边界」注释供脚本安全切分。

## 推荐做法（不改代码生成器）

### 1. ccache（增量编译）

第二次及以后编译同一 `uya.c` 往往明显变快：

```bash
# 先安装 ccache（未安装时不要写 CC='ccache cc'，否则会报「ccache: 未找到命令」）
# Debian/Ubuntu: sudo apt install ccache
export CC="ccache cc"
make from-c
```

或使用仓库提供的 [`scripts/ccache_from_c.sh`](../scripts/ccache_from_c.sh)：**未安装 ccache 时会自动去掉 `ccache` 前缀**，用普通 `cc` 继续编。

### 故障：`bash: ccache: 未找到命令`

说明本机没有安装 **ccache**。任选其一：

1. 安装：`sudo apt install ccache`（或发行版对应包名）  
2. 不要设置 `CC='ccache cc'`，直接：`make from-c`  
3. 使用：`./scripts/ccache_from_c.sh from-c`（无 ccache 时会回退）

### 2. GCC LTO（链接阶段并行优化）

单文件 `gcc x.c` 时，前端仍单线程；开启 **LTO** 后，**链接阶段**可并行做部分优化（取决于 GCC 版本与 `-flto` 模式）：

```bash
make from-c CFLAGS='-std=c99 -O2 -g -fno-builtin -Werror -flto=auto -fuse-linker-plugin -pipe'
```

注意：LTO 会改变链接行为，若遇问题请去掉 `-flto` 再试。

### 3. 真正并行编译多份 `.c`

需要 **Uya 编译器在 C99 后端直接输出多个 `.c` 文件**（或一个 `.h` + 多个 `.c`），由 `make -j` 分别 `gcc -c`。这是**编译器功能改动**，不是对现有 `uya.c` 做文本拆分能安全替代。

**现已支持（实验性）**：`uya build ... --split-c-dir <dir>`（或 `UYA_SPLIT_C_DIR`），生成 `uya_part1.c` / `uya_part2.c` + `Makefile`，链接阶段走 `make -j`。说明见 [`multi_file_codegen.md`](multi_file_codegen.md)。

## 与 `make` 并行的关系

`make -j` 能并行的是**多个**编译目标；若目标只有一个 `uya.c` → 一个二进制，**make 并行无法并行化单个 gcc 进程**。

启用 **`--split-c-dir`** 且存在多份 `.c` 目标时，`make -j` 才能并行执行多次 `gcc -c`。

---

**更新日期**：2026-03-23
