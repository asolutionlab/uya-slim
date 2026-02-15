# Uya v0.3.3 版本说明

**发布日期**：2026-02-15

本版本在 v0.3.2 基础上，实现**测试框架**、**libc 模块 TDD 实现**、**应用程序入口规范化**，并修复自举编译器的关键 bug。

---

## 核心亮点

### 1. 测试框架

**新增 `lib/std/testing/testing.uya`**：

```uya
use std.testing.*;

fn test_feature() !void {
    try assert_eq_i32(result, expected, "description");
}

export fn main() i32 {
    test_suite_begin("Module Tests");
    run_test("feature", test_feature);
    return test_suite_end();
}
```

**核心组件**：
| 组件 | 说明 |
|------|------|
| `test_suite_begin(name)` | 开始测试套件 |
| `run_test(name, test_fn)` | 运行单个测试（宏） |
| `test_suite_end()` | 结束套件，返回失败数 |
| `assert_eq_i32/i64/u64` | 带消息断言 |
| `expect/expect_eq/expect_true` | 简写断言 |

**优势**：
- 错误即测试失败（`!void` 返回类型）
- 自动传播（`try` 关键字）
- 资源安全（`errdefer` 清理）
- 统一报告（框架自动统计）

### 2. libc 模块 TDD 实现

**新增测试文件**：
| 文件 | 测试内容 |
|------|----------|
| `test_ctype.uya` | `isalpha`、`isdigit`、`isalnum`、`isspace` 等 |
| `test_errno.uya` | `errno` 变量读写 |
| `test_stdio.uya` | `fopen`、`fclose`、`fprintf`、`fgets` 等 |
| `test_stdlib.uya` | `malloc`、`free`、`atoi`、`strtol` 等 |
| `test_string.uya` | `strlen`、`strcmp`、`strcpy`、`strcat` 等 |
| `test_unistd.uya` | `read`、`write`、`close`、`getpid` 等 |

**libc 模块完善**：
- `libc/ctype.uya`：字符分类函数完整实现
- `libc/errno.uya`：errno 变量定义
- `libc/stdio.uya`：标准 I/O 函数增强
- `libc/stdlib.uya`：内存分配和转换函数
- `libc/string.uya`：字符串操作函数
- `libc/unistd.uya`：POSIX 系统调用封装

### 3. 应用程序入口规范化

**规范变更**：
| 声明方式 | 编译结果 | 用途 |
|----------|----------|------|
| `export fn main() i32` | `main_main()` | 应用程序入口（推荐） |
| `export fn main() !i32` | `main_main()` | 带错误处理的应用程序入口 |
| `export extern fn main(argc, argv)` | `main()` | C 入口（供 C 调用） |
| `fn main()` | `uya_main()` | 旧架构兼容（不推荐） |

**零依赖编译**：
```bash
# 无需 bridge.c
bin/uya-c --c99 app.uya lib/std/runtime/entry/entry.uya -o app.c
gcc -std=c99 -no-pie app.c -o app -lm
```

**测试程序同样使用 `export fn main() i32`**，实现零依赖。

### 4. 自举编译器 Bug 修复

**关键修复**：
- **catch 表达式代码生成**：修复 `AST_CATCH_EXPR` 表达式类型范围判断
  - 问题：`stmt.type <= AST_STRING` 不包含 `AST_CATCH_EXPR`
  - 修复：改为 `stmt.type <= AST_VA_ARG` 覆盖所有表达式类型
- **字符串数量限制**：修复符号表容量不足导致的编译失败
- **栈限制优化**：增大自举编译器栈限制，支持深层递归

---

## 模块变更概览

### 标准库（lib）

| 模块 | 变更要点 |
|------|----------|
| `std/testing/testing.uya` | 新增测试框架 |
| `libc/ctype.uya` | 字符分类函数 |
| `libc/errno.uya` | errno 变量 |
| `libc/stdio.uya` | 标准 I/O 增强 |
| `libc/stdlib.uya` | 内存/转换函数 |
| `libc/string.uya` | 字符串操作 |
| `libc/unistd.uya` | POSIX 封装 |

### 自举编译器（src）

| 模块 | 变更要点 |
|------|----------|
| `codegen/c99/stmt.uya` | 修复 catch 表达式类型范围判断 |
| `codegen/c99/expr.uya` | 修复 try 表达式对 `!void` 类型的处理 |
| `compile.sh` | 增大栈限制到 64MB |
| `main.uya` | 增大 temp_arena_buffer |

### 测试（tests/programs）

| 文件 | 说明 |
|------|------|
| `test_ctype.uya` | ctype 模块测试（新框架） |
| `test_errno.uya` | errno 模块测试（新框架） |
| `test_stdio.uya` | stdio 模块测试（新框架） |
| `test_stdlib.uya` | stdlib 模块测试（新框架） |
| `test_string.uya` | string 模块测试（新框架） |
| `test_unistd.uya` | unistd 模块测试（新框架） |

### 文档（docs）

| 文件 | 变更要点 |
|------|----------|
| `testing_guide.md` | 新增测试规范文档 v1.1.0 |
| `uya.md` | 版本更新至 0.46，添加测试规范引用 |
| `uya_ai_prompt.md` | 版本更新至 0.46 |

---

## 测试验证

```bash
make uya && ldd bin/uya    # not a dynamic executable（零依赖）
make b                     # 自举对比一致 ✓
make tests-c               # C 版测试通过
make tests-uya             # 自举版测试通过
```

---

## 文件变更统计（相对 v0.3.2）

- **11 个提交**
- **29 个文件变更**
- **+2888 行，-60 行**

主要涉及：
- `lib/`：新增测试框架和 libc 模块
- `tests/programs/`：新增 TDD 测试文件
- `src/`：自举编译器 bug 修复
- `docs/`：规范文档更新

---

## 版本对比

### v0.3.2 → v0.3.3 变更摘要

| 类别 | 内容 |
|------|------|
| **测试框架** | `lib/std/testing` 模块，`test_suite_begin`/`run_test`/断言函数 |
| **libc 模块** | ctype、errno、stdio、stdlib、string、unistd TDD 实现 |
| **规范** | 应用程序入口规范化（`export fn main()`） |
| **零依赖** | 测试程序无需 bridge.c |
| **bug 修复** | catch 表达式代码生成、字符串数量限制、栈限制 |
| **文档** | 测试规范文档、语言规范更新 |

---

## 相关资源

- **语言规范**：`docs/uya.md`（v0.46）
- **测试规范**：`docs/testing_guide.md`（v1.1.0）
- **语法规范**：`docs/grammar_formal.md`、`docs/grammar_quick.md`
- **变更日志**：`docs/changelog.md`
- **上一版说明**：`docs/RELEASE_v0.3.2.md`

---

**v0.3.3 实现测试框架、libc 模块 TDD 实现、应用程序入口规范化，为后续标准库完善和测试驱动开发奠定基础。**
