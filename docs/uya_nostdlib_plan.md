# uya-nostdlib 构建计划

## 目标

构建一个不依赖系统 libc 的自托管 Uya 编译器，所有 C 标准库函数由 Uya 自身实现。

## 当前状态

### 已完成

#### 1. `extern "libc" fn` 语法支持 ✅

- **语法**：`extern "libc" fn name(...) type;` 或 `export extern "libc" fn name(...) type { }`
- **用途**：显式声明 C 标准库函数，或用 Uya 实现替代 C 标准库函数
- **编译器修改**（C 版本和 Uya 版本已完成）：
  - `ast.h/ast.uya`：添加 `fn_decl_extern_lib_name` 字段
  - `parser.c/parser.uya`：支持解析 `extern "libc" fn` 语法
  - `checker.c/checker.uya`：允许 `extern "libc" fn` 使用 FFI 指针类型
  - `codegen/function.c/function.uya`：生成裸函数名（无模块前缀）

#### 2. `extern` 变量支持 ✅

- **语法**：
  - `extern const name: type;` - 导入只读 C 变量
  - `extern var name: type;` - 导入可变 C 变量
  - `export const name: type = value;` - 导出只读常量
  - `export var name: type = value;` - 导出可变变量
- **文档**：`docs/uya.md` 5.2.3 章节、`docs/changelog.md`、`docs/grammar_formal.md`、`docs/grammar_quick.md`
- **编译器实现**：C 编译器和 Uya 自举编译器均已完成（详见 `docs/extern_var_impl_plan.md`）

#### 3. `lib/libc/` 模块创建 ✅

已创建文件：
- `lib/libc/syscall.uya` - 系统调用常量和封装（Linux x86_64）
- `lib/libc/mem.uya` - 内存操作函数（memcpy, memset, memmove 等）
- `lib/libc/string.uya` - 字符串操作函数（strlen, strcmp, strcpy 等）

### 待解决

#### 循环依赖问题 ⚠️

**问题描述**：
编译器代码（`src/`）如果使用 `use libc.xxx` 导入 `lib/libc/` 模块，会导致循环依赖：
- 编译 Uya 编译器需要先有 libc 函数
- libc 函数实现需要 Uya 编译器编译

**当前状态**：编译器代码仍使用 `extern fn` 声明，不引用 `lib/libc/`。

## 解决方案

### 方案 A：两阶段构建（推荐）

```
阶段 1：使用系统 libc 构建编译器
┌─────────────────────────────────────┐
│  src/*.uya + extern fn (系统 libc)  │
│           ↓                         │
│      bin/uya (依赖系统 libc)        │
└─────────────────────────────────────┘

阶段 2：用编译器构建 lib/libc
┌─────────────────────────────────────┐
│  lib/libc/*.uya (export extern "libc" fn)  │
│           ↓                         │
│      lib/libc.a (纯 Uya 实现)       │
└─────────────────────────────────────┘

阶段 3：构建 nostdlib 版本
┌─────────────────────────────────────┐
│  src/*.uya + 链接 lib/libc.a        │
│           ↓                         │
│  bin/uya-nostdlib (无系统 libc 依赖) │
└─────────────────────────────────────┘
```

**优点**：
- 清晰的构建阶段
- 无需修改编译器代码结构
- 可增量构建

**实现步骤**：
1. [ ] 修改 Makefile 添加 `lib/libc.a` 目标
2. [ ] 修改 Makefile 添加 `uya-nostdlib` 目标
3. [ ] 创建链接脚本，将 `lib/libc.a` 静态链接

### 方案 B：分离编译

将编译器分为两部分：
- `src/core/` - 核心编译逻辑，不依赖任何外部模块
- `src/platform/` - 平台相关代码，可依赖 `lib/libc/`

**优点**：
- 架构清晰
- 便于移植

**缺点**：
- 需要大量重构
- 增加维护成本

### 方案 C：桥接层

在 bridge.c 中实现必要的 libc 函数，编译器使用这些桥接函数。

**优点**：
- 改动最小
- 快速实现

**缺点**：
- 不是纯 Uya 实现
- 违背项目目标

## 待办事项

### 编译器实现（已完成）

- [x] **AST 修改**
  - [x] `compiler-c/src/ast.h`：添加 `AST_EXTERN_VAR_DECL` 节点类型
  - [x] `src/ast.uya`：添加相应字段

- [x] **Parser 修改**
  - [x] `compiler-c/src/parser.c`：解析 `extern const/var` 和 `export const/var`
  - [x] `src/parser.uya`：同上

- [x] **Checker 修改**
  - [x] `compiler-c/src/checker.c`：类型检查（确保 C 兼容类型）
  - [x] `src/checker.uya`：同上

- [x] **Codegen 修改**
  - [x] `compiler-c/src/codegen/c99/`：生成 `extern type name;` 等
  - [x] `src/codegen/c99/`：同上

### lib/libc 完善（已完成，通过 lib/std/c/ 实现）

**说明**：libc 函数已在 `lib/std/c/` 中完整实现，编译器通过 `use std.c.*` 导入使用。

**已实现的功能**：

- [x] `stdio`（`lib/std/c/stdio.uya`）：fopen, fclose, fread, fwrite, fprintf, fputs, sprintf, snprintf, fgetc, fputc 等
- [x] `stdlib`（`lib/std/c/stdlib.uya`）：malloc, free, calloc, realloc, exit, abort, atoi, atol, atof, strtod, strtol, stat, readlink, opendir, readdir, closedir, getenv 等
- [x] `syscall`（`lib/std/c/syscall/syscall.uya`）：sys_read, sys_write, sys_open, sys_close, sys_exit, sys_getpid, sys_lseek, sys_access, sys_unlink, sys_mkdir, sys_rmdir, sys_chdir, sys_getcwd 等
- [x] `string`（`lib/std/c/string.uya` + `lib/std/string.uya`）：memcpy, memmove, memset, memcmp, memchr, strlen, strcmp, strncmp, strcpy, strncpy, strcat, strchr, strrchr, strstr 等

**lib/libc/ 保留用途**：
- `lib/libc/syscall.uya`：底层系统调用常量和 `extern "libc" fn` 封装
- `lib/libc/mem.uya`：内存操作函数（使用 `extern "libc" fn` 语法）
- `lib/libc/string.uya`：字符串操作函数（使用 `extern "libc" fn` 语法）

### Makefile 修改

- [x] 添加 `lib/libc.a` 目标（暂不需要，使用 lib/std/c/）
- [x] 添加 `uya-nostdlib` 目标
- [x] 添加 `-nostdlib -static -lgcc -lgcc_eh` 链接选项

### 测试

- [x] 单元测试：`extern "libc" fn` 语法
- [x] 单元测试：`extern const/var` 语法
- [x] 集成测试：`make uya-nostdlib` 构建成功
- [x] 集成测试：静态链接可执行文件正常运行

## 文件结构

```
uya/
├── compiler-c/          # C 编译器（自举引导）
│   └── src/
│       ├── ast.h        # 需要添加 extern 变量节点
│       ├── parser.c     # 需要添加 extern 变量解析
│       ├── checker.c    # 需要添加类型检查
│       └── codegen/     # 需要添加代码生成
├── src/                 # Uya 自举编译器
│   ├── ast.uya          # 需要添加 extern 变量节点
│   ├── parser.uya       # 需要添加 extern 变量解析
│   ├── checker.uya      # 需要添加类型检查
│   └── codegen/         # 需要添加代码生成
├── lib/
│   └── libc/            # Uya 实现的 libc
│       ├── syscall.uya  # 系统调用
│       ├── mem.uya      # 内存函数
│       └── string.uya   # 字符串函数
└── Makefile             # 需要添加构建目标
```

## 时间线

| 阶段 | 内容 | 状态 |
|------|------|------|
| 1 | `extern "libc" fn` 语法支持 | ✅ 已完成 |
| 2 | 文档更新 | ✅ 已完成 |
| 3 | `extern` 变量编译器实现 | ✅ 已完成 |
| 4 | `lib/libc` 完善 | ✅ 已完成 |
| 5 | Makefile 和 nostdlib 构建 | ✅ 已完成 |
| 6 | 测试和验证 | ✅ 已完成 |

---

*最后更新：2026-02-14*
