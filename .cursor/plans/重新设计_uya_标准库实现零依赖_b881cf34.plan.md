---
name: 重新设计 Uya 标准库实现零依赖
overview: 抛开 std.c，重新设计一套纯 Uya 标准库（使用 std.* 命名空间），让自举编译器完全零外部依赖，包括移除 bridge.c 的依赖。
todos:
  - id: ptr_builtins
    content: 实现指针转换内置函数 @ptr_from_usize 和 @usize_from_ptr（Lexer、Parser、Checker、Codegen）
    status: pending
  - id: syscall_layer
    content: 实现系统调用层（lib/std/syscall/linux.uya），封装所有 Linux 系统调用
    status: pending
  - id: runtime_support
    content: 实现运行时支持（lib/std/runtime/runtime.uya），替代 bridge.c 的功能（get_argc, get_argv, get_stderr, ptr_diff）
    status: pending
    dependencies:
      - syscall_layer
      - ptr_builtins
  - id: mem_operations
    content: 实现内存操作模块（lib/std/mem/mem.uya），包括 memcpy, memset, memmove, memcmp, memchr
    status: pending
  - id: string_operations
    content: 实现字符串操作模块（lib/std/string/string.uya），包括 strlen, strcmp, strchr, strstr 等
    status: pending
    dependencies:
      - mem_operations
  - id: file_io
    content: 实现文件 I/O 模块（lib/std/io/file.uya, stream.uya），包括 fopen, fread, fwrite, fclose, fprintf 等
    status: pending
    dependencies:
      - syscall_layer
      - string_operations
  - id: formatting
    content: 实现格式化模块（lib/std/fmt/fmt.uya），包括 sprintf, snprintf
    status: pending
    dependencies:
      - string_operations
  - id: process_control
    content: 实现进程控制模块（lib/std/process/process.uya），包括 exit, getenv
    status: pending
    dependencies:
      - syscall_layer
      - file_io
  - id: filesystem
    content: 实现文件系统模块（lib/std/fs/fs.uya），包括 stat, opendir, readdir, closedir, readlink
    status: pending
    dependencies:
      - syscall_layer
  - id: numeric_conversion
    content: 实现数值转换函数（atoi, atol, atof, strtod, strtol），可放在 std.string 或新建 std.conv
    status: pending
    dependencies:
      - string_operations
  - id: update_extern_decls
    content: 修改 src/extern_decls.uya，移除所有 extern 声明，改为 use std.* 导入
    status: pending
    dependencies:
      - runtime_support
      - mem_operations
      - string_operations
      - file_io
      - formatting
      - process_control
      - filesystem
      - numeric_conversion
  - id: update_compiler_sources
    content: 修改自举编译器源代码（main.uya, checker.uya, parser.uya, codegen/*.uya），替换所有 C 标准库调用为 std.* 调用
    status: pending
    dependencies:
      - update_extern_decls
  - id: update_compile_script
    content: 修改 src/compile.sh，移除 bridge.c 生成和依赖，更新编译流程以包含新标准库
    status: pending
    dependencies:
      - update_compiler_sources
  - id: testing
    content: 创建测试用例验证所有标准库函数，确保自举编译器可以零依赖编译和运行
    status: pending
    dependencies:
      - update_compile_script
---

# 重新设

计 Uya 标准库实现零依赖

## 目标

设计并实现一套全新的 Uya 标准库（使用 `std.*` 命名空间），让自举编译器完全零外部依赖，包括：

- 移除对 C 标准库的所有依赖
- 移除 bridge.c 的依赖
- 所有功能完全用 Uya 实现，基于系统调用

## 架构设计

### 新标准库目录结构

```javascript
lib/std/
├── syscall/          # 系统调用封装（底层）
│   └── linux.uya     # Linux 系统调用封装
├── io/               # 文件 I/O（std.io）
│   ├── file.uya      # 文件操作（fopen, fread, fwrite, fclose 等）
│   └── stream.uya    # 流操作（fprintf, fputs, fgetc 等）
├── string/            # 字符串操作（std.string）
│   └── string.uya    # 字符串函数（strlen, strcmp, strchr 等）
├── mem/               # 内存操作（std.mem）
│   └── mem.uya       # 内存函数（memcpy, memset 等）
├── process/           # 进程控制（std.process）
│   └── process.uya   # 进程函数（exit, getenv 等）
├── fs/                # 文件系统（std.fs）
│   └── fs.uya        # 文件系统函数（stat, opendir, readdir 等）
├── fmt/               # 格式化（std.fmt）
│   └── fmt.uya       # 格式化函数（sprintf, snprintf 等）
└── runtime/           # 运行时支持（std.runtime）
    └── runtime.uya    # 运行时函数（get_argc, get_argv, get_stderr 等）
```



### 模块命名规范

- 使用 `std.*` 命名空间（如 `std.io`, `std.string`）
- 与 `std.c.*` 区分开，表示这是纯 Uya 标准库
- 模块路径映射：`lib/std/io/file.uya` → `use std.io.file;`

## 实现步骤

### 阶段 0：指针转换内置函数

**目标**：实现 `@ptr_from_usize` 和 `@usize_from_ptr` 内置函数，用于指针和整数之间的安全转换。**函数签名**：

```uya
@ptr_from_usize(value: usize) &void  // 从 usize 转换为指针
@usize_from_ptr(ptr: &void) usize   // 从指针转换为 usize
```

**实现任务**：

1. **Lexer**（`compiler-c/src/lexer.c` 和 `src/lexer.uya`）：

- 在 `is_builtin_function` 中添加 `ptr_from_usize` 和 `usize_from_ptr` 识别
- 更新错误消息中的内置函数列表

2. **AST**（`compiler-c/src/ast.h`）：

- 添加 `AST_PTR_FROM_USIZE` 和 `AST_USIZE_FROM_PTR` 节点类型
- 在 AST 节点 union 中添加相应数据结构

3. **Parser**（`compiler-c/src/parser.c` 和 `src/parser.uya`）：

- 解析 `@ptr_from_usize(expr)` 和 `@usize_from_ptr(expr)`
- 验证参数类型和数量

4. **Checker**（`compiler-c/src/checker.c` 和 `src/checker.uya`）：

- 类型检查：`@ptr_from_usize` 参数必须是 `usize`，返回 `&void`
- 类型检查：`@usize_from_ptr` 参数必须是指针类型，返回 `usize`

5. **Codegen**（`compiler-c/src/codegen/c99/expr.c` 和 `src/codegen/c99/expr.uya`）：

- `@ptr_from_usize`：生成 `(void *)(uintptr_t)value`
- `@usize_from_ptr`：生成 `(uintptr_t)ptr`

**测试用例**：

- `test_ptr_from_usize.uya`：测试 usize 转指针
- `test_usize_from_ptr.uya`：测试指针转 usize
- `test_ptr_arithmetic.uya`：使用这两个函数实现指针算术

### 阶段 1：系统调用层（std.syscall）

**文件**：`lib/std/syscall/linux.uya`**功能**：

- 封装所有 Linux 系统调用
- 提供统一的错误处理接口
- 支持文件操作、进程控制、内存管理等系统调用

**关键函数**：

- `sys_read`, `sys_write`, `sys_open`, `sys_close`
- `sys_exit`, `sys_getpid`
- `sys_mmap`, `sys_munmap`
- `sys_stat`, `sys_getdents64`
- 等等

### 阶段 2：运行时支持（std.runtime）

**文件**：`lib/std/runtime/runtime.uya`**功能**：

- 替代 bridge.c 的功能
- 实现 `get_argc()`, `get_argv()`, `get_stderr()`, `ptr_diff()`

**实现方式**：

- `get_argc`/`get_argv`：通过读取 `/proc/self/cmdline` 或使用 `auxv` 获取
- `get_stderr`：返回固定的文件描述符 2
- `ptr_diff`：使用 `@usize_from_ptr` 和 `@ptr_from_usize` 实现指针差计算

### 阶段 3：内存操作（std.mem）

**文件**：`lib/std/mem/mem.uya`**功能**：

- 实现 `memcpy`, `memset`, `memmove`, `memcmp`, `memchr`
- 纯 Uya 实现，无外部依赖

### 阶段 4：字符串操作（std.string）

**文件**：`lib/std/string/string.uya`**功能**：

- 实现 `strlen`, `strcmp`, `strncmp`, `strcpy`, `strncpy`, `strcat`
- 实现 `strchr`, `strrchr`, `strstr`
- 纯 Uya 实现

### 阶段 5：文件 I/O（std.io）

**文件**：`lib/std/io/file.uya`, `lib/std/io/stream.uya`**功能**：

- `file.uya`：`fopen`, `fclose`, `fread`, `fwrite`
- `stream.uya`：`fgetc`, `fputc`, `fputs`, `fprintf`, `fflush`
- 基于系统调用实现

### 阶段 6：格式化（std.fmt）

**文件**：`lib/std/fmt/fmt.uya`**功能**：

- 实现 `sprintf`, `snprintf`
- 支持基本格式化（%s, %d, %x 等）
- 纯 Uya 实现

### 阶段 7：进程控制（std.process）

**文件**：`lib/std/process/process.uya`**功能**：

- `exit`：进程退出
- `getenv`：环境变量（通过读取 `/proc/self/environ`）

### 阶段 8：文件系统（std.fs）

**文件**：`lib/std/fs/fs.uya`**功能**：

- `stat`：文件状态
- `opendir`, `readdir`, `closedir`：目录操作
- `readlink`：符号链接
- 基于系统调用实现

### 阶段 9：数值转换（std.string 或新建 std.conv）

**功能**：

- `atoi`, `atol`, `atof`：字符串转数字
- `strtod`, `strtol`：字符串转数字（C 兼容）
- 纯 Uya 实现

### 阶段 10：集成到自举编译器

**修改文件**：

- `src/extern_decls.uya`：移除所有 extern 声明，改为 `use std.*`
- `src/main.uya`：替换所有 C 标准库调用为 `std.*` 调用
- `src/checker.uya`：替换所有 C 标准库调用
- `src/parser.uya`：替换所有 C 标准库调用
- `src/codegen/c99/*.uya`：替换所有 C 标准库调用
- `src/compile.sh`：移除 bridge.c 生成，更新链接步骤

**编译流程修改**：

- 移除 `-nostdlib` 模式下的 bridge.c 依赖
- 标准库自动包含在编译中
- 更新 `UYA_ROOT` 环境变量指向 `lib/`

## 关键技术点

### 1. 命令行参数获取

**方案 A**：读取 `/proc/self/cmdline`

```uya
// 读取 /proc/self/cmdline 文件
// 解析 null 分隔的参数列表
```

**方案 B**：使用 `auxv`（辅助向量）

```uya
// 从进程启动时的 auxv 获取 argc/argv
// 需要系统调用或特殊处理
```



### 2. 环境变量获取

**方案**：读取 `/proc/self/environ`

```uya
// 读取 /proc/self/environ 文件
// 解析 null 分隔的环境变量列表
```



### 3. 指针差计算

**方案**：使用 `@usize_from_ptr` 和 `@ptr_from_usize` 实现

```uya
fn ptr_diff(ptr1: &byte, ptr2: &byte) i32 {
    const u1: usize = @usize_from_ptr(ptr1 as &void);
    const u2: usize = @usize_from_ptr(ptr2 as &void);
    return (u1 - u2) as i32;
}
```



### 4. stderr 获取

**方案**：直接返回文件描述符 2，或使用系统调用获取

## 测试验证

### 测试步骤

1. **单元测试**：每个标准库模块独立测试
2. **集成测试**：测试自举编译器编译过程
3. **零依赖验证**：
   ```bash
                  # 编译自举编译器
                  cd src && ./compile.sh --c99 --nostdlib
                  
                  # 验证无外部依赖
                  ldd build/uya-compiler/compiler
                  # 应只显示 linux-vdso.so.1
                  
                  # 测试编译器功能
                  ./build/uya-compiler/compiler --version
   ```




### 测试用例

- 创建测试程序验证所有标准库函数
- 确保与现有功能兼容
- 验证编译器和标准库都能正常工作

## 迁移策略

### 渐进式迁移

1. **第一阶段**：实现新标准库，与 `std.c` 并存
2. **第二阶段**：修改自举编译器使用新标准库
3. **第三阶段**：移除 `std.c` 和 `bridge.c` 依赖
4. **第四阶段**：清理旧代码

### 兼容性

- 保持函数签名与 C 标准库兼容（用于 FFI）
- 确保现有测试用例继续通过
- 逐步迁移，避免一次性大改动

## 文件清单

### 新建文件

- （无，指针转换内置函数是编译器功能）

### 修改文件（内置函数）

- `compiler-c/src/lexer.c` - 添加内置函数识别
- `src/lexer.uya` - 添加内置函数识别
- `compiler-c/src/ast.h` - 添加 AST 节点类型
- `compiler-c/src/parser.c` - 添加解析逻辑
- `src/parser.uya` - 添加解析逻辑
- `compiler-c/src/checker.c` - 添加类型检查
- `src/checker.uya` - 添加类型检查
- `compiler-c/src/codegen/c99/expr.c` - 添加代码生成
- `src/codegen/c99/expr.uya` - 添加代码生成

### 新建文件（标准库）

- `lib/std/syscall/linux.uya`
- `lib/std/runtime/runtime.uya`
- `lib/std/mem/mem.uya`
- `lib/std/string/string.uya`
- `lib/std/io/file.uya`
- `lib/std/io/stream.uya`
- `lib/std/fmt/fmt.uya`
- `lib/std/process/process.uya`
- `lib/std/fs/fs.uya`

### 修改文件

- `src/extern_decls.uya` - 移除 extern 声明，改为 use 语句
- `src/main.uya` - 替换 C 标准库调用
- `src/checker.uya` - 替换 C 标准库调用
- `src/parser.uya` - 替换 C 标准库调用
- `src/codegen/c99/*.uya` - 替换 C 标准库调用
- `src/compile.sh` - 移除 bridge.c，更新编译流程
- `src/arena.uya` - 替换 C 标准库调用（如果有）

### 可选删除文件

- `lib/std/c/*` - 旧的标准库（迁移完成后）
- `src/bridge.c` - bridge 文件（如果完全替代）

## 注意事项

1. **系统调用兼容性**：当前实现针对 Linux x86-64，后续可扩展其他平台
2. **性能考虑**：纯 Uya 实现可能比 C 实现慢，需要优化关键路径
3. **错误处理**：统一使用 Uya 的错误联合类型（`!T`）
4. **内存管理**：malloc/free 需要实现完整的分配器（当前 stdlib.uya 有简化实现）
5. **测试覆盖**：确保所有函数都有测试用例