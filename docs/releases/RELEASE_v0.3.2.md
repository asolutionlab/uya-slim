# Uya v0.3.2 版本说明

**发布日期**：2026-02-15

本版本在 v0.3.1 基础上，实现**可变参数函数支持**、**extern 变量/常量**、**Scheme C 双入口架构**，并完成**自举编译器与 C 编译器输出一致性**对比验证。

---

## 核心亮点

### 1. 可变参数函数支持

**新增内置函数**：
- **`@va_start(&ap, last)`**：在可变参数函数内初始化 va_list
- **`@va_end(&ap)`**：结束 va_list
- **`@va_arg(ap, Type)`**：从 va_list 按类型提取下一个参数
- **`@va_copy(&dest, src)`**：复制 va_list

**`va_list` 是编译器内置类型**，大小与目标平台相关。

**用途**：支持纯 Uya 实现 libc.stdarg 和 vprintf 系列函数，完全兼容 C ABI。

**示例**：
```uya
fn my_printf(fmt: &const byte, ...) i32 {
    var ap: va_list;
    @va_start(&ap, fmt);
    const c: i32 = @va_arg(ap, i32);
    @va_end(&ap);
    return c;
}

// 接收 va_list 参数的函数
fn my_vprintf(fmt: &const byte, ap: va_list) i32 {
    const c: i32 = @va_arg(ap, i32);
    return c;
}
```

**格式化函数增强**：
- `fprintf`/`sprintf`/`snprintf` 新增格式支持：`%g`、`%.17g`、`%zu`、`%*s`、`%u`
- 支持科学计数法解析（如 `1.5e1`）

### 2. extern 变量/常量支持

**导入 C 全局变量**：
```uya
extern const errno: i32;         // 导入只读 C 变量
extern var stdout: &FILE;        // 导入可变 C 变量
```

**导出 Uya 全局变量给 C**：
```uya
export const VERSION: &const byte = "1.0.0";  // 导出只读常量
export var counter: i32 = 0;                   // 导出可变变量
```

**export extern "libc" fn 语法**：
```uya
export extern "libc" fn fprintf(stream: &FILE, fmt: &const byte, ...) i32;
```
- 支持用 Uya 实现替代 C 标准库函数

### 3. Scheme C 双入口架构

**架构变更**：
| 声明方式 | 生成的 C 函数名 | 用途 |
|---------|----------------|------|
| `export fn main()` | `main_main()` | 应用入口 |
| `export extern fn main(argc, argv)` | `main()` | C 入口（供 C 调用） |
| `fn main()` | `uya_main()` | 旧架构兼容 |

**新增模块**：
- `lib/std/runtime/entry/entry.uya`：提供 C 入口函数

**优势**：
- 支持标准 C main 签名
- 与 C 生态无缝集成
- 向后兼容旧代码

### 4. 自举编译器一致性

**验证命令**：
```bash
make b   # C 编译器与自举编译器生成的 C 文件完全一致
```

**关键修复**：
- `libc.readdir` 使用 `sys_getdents64` 实现
- `libc.fprintf` 支持 `%*s` 格式（宽度从参数获取）
- 浮点字面量输出与 C 版 `%.17g` 一致
- 栈限制优化，避免深层递归段错误

---

## 模块变更概览

### C 编译器（compiler-c）

| 模块 | 变更要点 |
|------|----------|
| `codegen/c99/function.c` | `export fn` 生成模块前缀；`export extern fn main` 生成 C 入口 |
| `codegen/c99/main.c` | 重写第九步支持多种 main 函数生成 |
| `codegen/c99/expr.c` | `@va_start`/`@va_end`/`@va_arg`/`@va_copy` 展开 |
| `checker.c` | 可变参数函数内 va_* 使用检查；extern 变量检查 |
| `parser.c`, `lexer.c`, `ast.c/h` | va_* 内置函数解析；extern 变量语法 |

### 自举编译器（src）

| 模块 | 变更要点 |
|------|----------|
| `codegen/c99/function.uya` | `export fn` 前缀生成；extern 变量处理 |
| `codegen/c99/expr.uya` | `@va_start`/`@va_arg`/`@va_copy` 展开；`%*s` 格式修复 |
| `checker.uya` | va_* 使用位置检查 |
| `main.uya` | 依赖收集增强 |
| `compile.sh` | 静态链接优化 |

### 标准库（lib）

| 模块 | 变更要点 |
|------|----------|
| `libc/stdio.uya` | fprintf 支持 `%*s`、`%g`、`%zu` 等格式 |
| `libc/stdlib.uya` | `readdir` 使用 `sys_getdents64` 实现 |
| `std/runtime/entry/` | 新增 C 入口模块 |

### 测试

- 新增 `test_va_builtin.uya` 测试可变参数内置函数
- 新增 `error_va_start_non_varargs.uya` 测试错误检测
- 341 个测试全部通过
- 默认并行测试（8 线程）

---

## 测试验证

```bash
make uya && ldd bin/uya    # not a dynamic executable（零依赖）
make b                     # 自举对比一致 ✓
make tests-c               # C 版测试通过
make tests-uya             # 自举版测试通过（341/341）
```

---

## 文件变更统计（相对 v0.3.1）

- **约 27 个提交**
- 主要涉及：
  - `compiler-c/`：codegen、checker、parser、lexer
  - `src/`：自举编译器对应模块
  - `lib/`：libc 标准库增强
  - `tests/`：新增测试用例

---

## 版本对比

### v0.3.1 → v0.3.2 变更摘要

| 类别 | 内容 |
|------|------|
| **语言/内置** | `@va_start`、`@va_end`、`@va_arg`、`@va_copy` 内置函数；`va_list` 内置类型 |
| **语言/语法** | `extern const/var` 变量声明；`export extern "libc" fn` 语法 |
| **架构** | Scheme C 双入口架构（`export fn main` → `main_main`） |
| **标准库** | libc.fprintf 格式增强（`%*s`、`%g`、`%zu`）；libc.readdir 实现 |
| **代码生成** | 浮点字面量输出与 C 一致；extern 变量生成 |
| **自举** | 自举对比一致；栈限制优化 |
| **测试** | 并行测试默认启用；341 测试全部通过 |
| **文档** | 自举内存优化计划；libc 错误机制重构计划 |

---

## 相关资源

- **语言规范**：`docs/uya.md`
- **语法规范**：`docs/grammar_formal.md`、`docs/grammar_quick.md`
- **内置函数**：`docs/builtin_functions.md`
- **变更日志**：`docs/changelog.md`
- **上一版说明**：`docs/releases/RELEASE_v0.3.1.md`

---

**v0.3.2 实现可变参数函数支持、extern 变量/常量、Scheme C 双入口架构，并完成自举编译器与 C 编译器输出一致性验证，为标准库扩展与 C 生态集成提供坚实基础。**
