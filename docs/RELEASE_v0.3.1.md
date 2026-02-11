# Uya v0.3.1 版本说明

**发布日期**：2026-02-10

本版本在 v0.2.32 基础上，实现**零动态依赖**的静态链接构建、**指针与整数互转**内置函数、**标准库与模块路径**增强，并完成**自举比对一致**与多项代码生成/类型检查修复。

---

## 核心亮点

### 1. 零依赖静态链接

**目标**：`bin/uya` 无任何动态库依赖，`ldd bin/uya` 显示 `not a dynamic executable`。

**实现**：
- **默认构建（`make uya`）**：使用 `gcc -static` 纯静态链接，不再链接 LLVM（C99 自举编译器不需要），生成完全静态可执行文件。
- **无标准库构建（`make uya-nostdlib`）**：使用 `-nostdlib -static`，显式链接 crt（crt1.o/crti.o/crtn.o）与 `-lc -lgcc`，适用于 freestanding 或零依赖场景。

**验证**：
```bash
make uya
ldd bin/uya   # 输出：not a dynamic executable
```

### 2. 指针与整数互转内置函数

**新增**：
- **`@ptr_from_usize(n: usize) -> *T`**：将无符号整数转换为指针（需在调用处推断目标类型 `T`）。
- **`@usize_from_ptr(p: *T) -> usize`**：将指针转换为无符号整数。

**用途**：与 C 互操作、低层内存布局、系统接口等。

**示例**：
```uya
var p: *i32 = @ptr_from_usize(0x1000 as usize);
var n: usize = @usize_from_ptr(p);
```

### 3. 标准库与模块路径增强

**模块与路径**：
- 支持**目录即模块**与**同目录多文件合并**：同一目录下多个 `.uya` 文件视为同一模块，路径收集支持排序与去重。
- 标准库文件路径提取支持**多级模块**与**多种路径格式**，类型检查器增强模块导入与错误处理。
- 语法文档补充同目录文件合并规则说明。

**标准库函数与代码生成**：
- 标准库函数处理支持**文件 I/O、字符串、内存操作**等，避免与 C 标准库/POSIX 名称冲突；系统函数名称冲突处理与 extern 声明输出修正，确保 C 代码生成正确原型。
- `@size_of` / `@align_of` 返回值显式转换为 `int32_t`，与 C 端一致。

### 4. 自举与代码生成修复

**自举**：
- 增大主 Arena 与 temp_arena 缓冲区，满足自举编译与代码生成所需内存。
- 路径收集逻辑支持排序与去重，避免重复添加与乱序依赖。

**代码生成与 linkage**：
- 函数**前向声明**与**定义**处，若存在同名 `extern` 声明则不再输出 `static`，与 C 编译器行为一致，消除自举对比在 linkage 上的差异。
- 兜底 `return 0;` / `return (T){0};` 等缩进与 C 编译器输出一致（8 空格），消除缩进 diff。

**验证**：
```bash
make b   # 自举对比一致 ✓
```

---

## 模块变更概览

### C 编译器（compiler-c）

| 模块 | 变更要点 |
|------|----------|
| `codegen/c99/*` | 标准库/POSIX 函数处理、字符串常量、数组初始化与返回值、系统函数名冲突；extern 与原型输出 |
| `checker.c` | 模块导入、错误处理、类型推断、模块路径（目录/文件模块）、标准库路径提取 |
| `ast.c/h`, `parser.c`, `lexer.c`, `main.c` | 指针内置函数、路径与依赖收集、入口与桥接逻辑 |

### 自举编译器（src）

| 模块 | 变更要点 |
|------|----------|
| `codegen/c99/function.uya` | 同名 extern 时不加 static（前向声明+定义）；兜底 return 缩进与 C 一致 |
| `codegen/c99/expr.uya`, `stmt.uya`, `types.uya`, `main.uya`, `global.uya` | 标准库函数、@size_of/@align_of 返回 int32_t、路径与依赖 |
| `checker.uya` | 模块路径、类型推断、标准库路径、错误处理 |
| `main.uya` | Arena 缓冲区大小、路径收集排序与去重 |
| `compile.sh` | 默认 `-static` 零依赖链接；`--nostdlib` 时 `-nostdlib -static` + crt + -lc -lgcc |

### 标准库与测试

- 标准库字符串等实现与测试调整；新增/更新指针内置函数、标准库、多级模块等测试。
- `run_programs.sh` 支持新模块与路径逻辑。

---

## 测试验证

- **C 版编译器（`--c99`）**：测试通过
- **自举版编译器（`--uya --c99`）**：测试通过
- **自举对比（`make b`）**：C 编译器与自举编译器生成的 C 文件完全一致
- **零依赖**：`make uya` 后 `ldd bin/uya` 为 `not a dynamic executable`

```bash
make uya && ldd bin/uya    # not a dynamic executable
make b                     # 自举对比一致
make tests-c               # C 版测试
make tests-uya             # 自举版测试
```

---

## 文件变更统计（相对 v0.2.32）

- **约 69 个文件变更**，约 **4778 行新增**，**1002 行删除**
- 主要涉及：codegen（C 与 Uya）、checker、main、compile.sh、标准库与测试

---

## 版本对比

### v0.2.32 → v0.3.1 变更摘要

| 类别 | 内容 |
|------|------|
| **构建** | 默认静态链接、0 动态依赖；`--nostdlib` 时 -nostdlib -static + crt + -lc -lgcc |
| **语言/内置** | @ptr_from_usize、@usize_from_ptr；@size_of/@align_of 返回 int32_t |
| **模块/路径** | 目录即模块、同目录合并、路径排序去重、多级模块与标准库路径提取 |
| **代码生成** | 标准库/POSIX 函数处理、系统函数名冲突、extern 与 static 与 C 一致、兜底 return 缩进 |
| **自举** | Arena 增大、路径收集修复、自举比对一致 |
| **文档** | 语法规则（同目录合并）、todo 与实现状态更新 |

---

## 相关资源

- **语言规范**：`docs/uya.md`
- **语法规范**：`docs/grammar_formal.md`、`docs/grammar_quick.md`
- **实现与待办**：`docs/compiler-c-spec/`、`docs/todo_mini_to_full.md`
- **上一版说明**：`docs/RELEASE_v0.2.32.md`

---

**v0.3.1 实现零依赖静态链接、指针与整数互转内置函数、标准库与模块路径增强，并完成自举比对一致与多项代码生成/类型检查修复，为无动态依赖部署与标准库扩展提供基础。**
