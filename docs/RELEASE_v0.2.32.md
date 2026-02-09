# Uya v0.2.32 版本说明

**发布日期**：2026-02-09

本版本主要修复了**标准库函数与 C 标准库的冲突问题**，增强了**只读指针类型**和**函数导出规则**支持，并扩展了**标准库函数实现**。同时修复了多个测试用例，确保与 C 标准库的完全兼容性。

---

## 核心亮点

### 1. 标准库函数冲突修复

**问题**：Uya 标准库中实现的函数（如 `fopen`、`fclose`、`atoi`、`strtol` 等）与 C 标准库函数同名，导致编译时出现类型冲突错误。

**解决方案**：
- 在代码生成器中识别标准库函数，避免生成重复的声明和定义
- 这些函数会被链接到 C 标准库的实现，而不是生成 Uya 标准库的实现
- 确保生成的 C 代码与 C 标准库完全兼容

**受影响的函数类别**：

**stdlib 函数**（不生成声明和定义）：
- `strtod`、`strtol`、`getenv`、`abort`、`exit`
- `atoi`、`atol`、`atof`

**stdio 函数**（不生成声明和定义）：
- `fputs`、`fputc`、`fwrite`、`fprintf`
- `fgetc`、`fread`、`fopen`、`fclose`
- `sprintf`、`snprintf`

**string 函数**（在包含 `<string.h>` 时不生成）：
- `strlen`、`strcmp`、`strncmp`、`strcpy`、`strncpy`
- `strcat`、`strncat`、`strchr`、`strrchr`、`strstr`
- `memcpy`、`memmove`、`memset`、`memcmp`、`memchr`

### 2. 只读指针类型增强

**功能**：完善 `&const T` 和 `*const T` 类型支持，提升类型安全性和与 C 标准库的兼容性。

**改进**：
- 修复代码生成器中只读指针类型的处理逻辑
- 更新标准库函数签名，使用 `&const byte` 替代 `&byte`
- 支持 `&T` 隐式转换为 `&const T`
- 完善类型相等性检查，区分可变和只读指针

**示例**：
```uya
// 只读指针类型
fn process(data: &const byte) void {
    // data 不能被修改
}

// 标准库函数签名更新
export fn strlen(s: &const byte) usize;
export fn strcmp(s1: &const byte, s2: &const byte) i32;
```

### 3. 函数导出规则完善

**功能**：支持 `export` 关键字，控制函数的可见性。

**规则**：
- `export fn`：函数在生成的 C 代码中为 `extern`（可被外部链接）
- `fn`：函数在生成的 C 代码中为 `static`（仅内部可见）
- `extern fn`：声明外部函数，不生成实现

**示例**：
```uya
// 导出函数（可被外部链接）
export fn public_api() i32 {
    return 42;
}

// 内部函数（static）
fn internal_helper() void {
    // ...
}

// 外部函数声明
extern fn printf(fmt: *byte, ...) i32;
```

### 4. 标准库扩展

**新增函数**：

**stdio 模块**：
- `fwrite`、`fputc`、`fputs`、`sprintf`、`snprintf`

**stdlib 模块**：
- `strtod`、`strtol`（字符串到数值转换）

**string 模块**：
- `strstr`（子字符串查找）

**系统调用**：
- `SYS_readlink`、`SYS_getdents64`

### 5. 构建系统改进

**新增选项**：
- `--nostdlib`：构建时不链接标准库，支持 freestanding 环境
- `make uya-nostdlib`：构建不依赖标准库的自举编译器版本

---

## 模块变更

### C 编译器（compiler-c）

| 模块 | 变更 |
|------|------|
| `codegen/c99/function.c` | 新增标准库函数检测逻辑，避免重复声明和定义；+150 行 |
| `codegen/c99/expr.c` | 增强对 `null` 和双层指针的处理，支持 `strtol`/`strtod` 的特殊参数；+50 行 |
| `codegen/c99/types.c` | 修复只读指针类型的代码生成逻辑；+30 行 |
| `codegen/c99/main.c` | 新增字符串函数调用检测，设置 `needs_string_h` 标志；+40 行 |
| `codegen/c99/stmt.c` | 修复字符串常量赋值的类型转换；+20 行 |

### 自举编译器（src）

| 模块 | 变更 |
|------|------|
| `codegen/c99/function.uya` | 同步标准库函数处理逻辑；+180 行 |
| `codegen/c99/expr.uya` | 同步 `null` 和双层指针处理；+60 行 |
| `codegen/c99/types.uya` | 同步只读指针类型处理；+35 行 |
| `codegen/c99/main.uya` | 同步字符串函数检测；+45 行 |
| `codegen/c99/stmt.uya` | 同步类型转换逻辑；+25 行 |
| `parser.uya` | 移除重复的 `extern` 声明；-10 行 |
| `extern_decls.uya` | 新增 `strtol` 声明；+2 行 |
| `checker.uya` | 增强类型检查，支持标准库函数的 FFI 指针类型；+50 行 |

### 标准库（lib）

| 模块 | 变更 |
|------|------|
| `std/c/stdio.uya` | 新增 `fwrite`、`fputc`、`fputs`、`sprintf`、`snprintf`；更新函数签名为只读指针；+200 行 |
| `std/c/stdlib.uya` | 新增 `strtod`、`strtol`；更新函数签名为只读指针；+150 行 |
| `std/c/string.uya` | 新增 `strstr`；更新函数签名为只读指针；+50 行 |
| `std/c/syscall/syscall.uya` | 新增系统调用常量；+5 行 |

### 测试用例

**修复的测试**：
- `test_try_div.uya`：将 `div` 函数重命名为 `divide`，避免与 C 标准库冲突
- `test_main_with_errors.uya`：同步函数名修改
- `test_main_first_stmt.uya`：同步函数名修改
- `test_error_handling.uya`：同步函数名修改
- `test_err_handling.uya`：同步函数名修改
- `test_const_pointer.uya`：修复只读指针类型测试
- `test_const_pointer_simple.uya`：验证只读指针功能
- `test_export_for_c_complete.uya`：更新为使用只读指针

---

## 测试验证

- **C 版编译器（`--c99`）**：331 个测试全部通过
- **自举版编译器（`--uya --c99`）**：331 个测试全部通过
- **自举对比**：C 编译器与自举编译器生成的 C 文件完全一致

```bash
# 测试验证命令
make clean && make tests-c      # C 版：331/331 通过
make clean && make tests-uya    # 自举版：331/331 通过
make clean && make b            # 自举对比：一致 ✓
```

---

## 文件变更统计（自 v0.2.31 以来）

**统计**：504 个文件变更，约 9931 行新增，2381 行删除

**主要变更**：
- `compiler-c/src/codegen/c99/function.c` — +150 行（标准库函数检测）
- `src/codegen/c99/function.uya` — +180 行（自举版同步）
- `lib/std/c/stdio.uya` — +200 行（新增函数实现）
- `lib/std/c/stdlib.uya` — +150 行（新增函数实现）
- `compiler-c/src/codegen/c99/expr.c` — +50 行（null 和双层指针处理）
- `src/codegen/c99/expr.uya` — +60 行（自举版同步）

---

## 技术细节

### 标准库函数检测机制

编译器在生成函数声明和定义时，会检查函数名是否在标准库函数列表中：

```c
// 检测标准库函数
int is_stdlib_function(const char *func_name) {
    // 检查 stdlib 函数
    if (strcmp(func_name, "strtod") == 0 || ...) {
        return 1;
    }
    // 检查 stdio 函数
    if (strcmp(func_name, "fopen") == 0 || ...) {
        return 1;
    }
    return 0;
}

// 生成函数原型时跳过标准库函数
void gen_function_prototype(...) {
    if (is_stdlib && is_stdlib_function(orig_name)) {
        // 不生成声明，使用标准库的声明
        return;
    }
    // ... 生成声明
}

// 生成函数定义时跳过标准库函数
void gen_function(...) {
    if (is_stdlib && is_stdlib_function(orig_name)) {
        // 不生成定义，链接到标准库的实现
        return;
    }
    // ... 生成定义
}
```

### 只读指针类型处理

只读指针在类型检查阶段进行隐式转换：

```c
// 类型检查：&T 可以隐式转换为 &const T
Type *checker_convert_type(Checker *checker, Type *from, Type *to) {
    if (from->type == TYPE_POINTER && to->type == TYPE_POINTER) {
        if (!from->is_const && to->is_const) {
            // 允许 &T -> &const T
            return to;
        }
    }
    // ... 其他转换
}
```

### null 和双层指针处理

对于 `strtol` 和 `strtod` 的特殊参数处理：

```c
// 检测 null as **byte 的情况
if (is_cast_to_byte_ptr_ptr && is_null) {
    // 生成 (char **)NULL 而不是 (uint8_t **)NULL
    fputs("(char **)NULL", output);
} else {
    // 正常类型转换
    fprintf(output, "(%s)", type_c);
    gen_expr(codegen, src_expr);
}
```

---

## 版本对比

### v0.2.31 → v0.2.32 变更

- **修复问题**：
  - ✅ 标准库函数与 C 标准库的冲突（18 个函数）
  - ✅ 只读指针类型的代码生成
  - ✅ 测试用例中的函数名冲突（`div` → `divide`）

- **功能增强**：
  - ✅ 函数导出规则完善
  - ✅ 标准库函数扩展（7 个新函数）
  - ✅ 构建系统改进（`--nostdlib` 选项）

- **类型系统**：
  - ✅ 只读指针类型完善
  - ✅ 标准库函数签名更新为只读指针
  - ✅ FFI 指针类型支持标准库函数

- **测试改进**：
  - ✅ 修复 8 个测试用例
  - ✅ 测试覆盖率提升：331 个测试全部通过

- **非破坏性**：向后兼容，现有代码行为不变

---

## 性能保证

### 标准库函数链接

标准库函数直接链接到 C 标准库的实现，零运行时开销：

| 函数类别 | 链接方式 | 开销 |
|---------|---------|------|
| stdlib 函数 | 链接到 libc | 零开销（系统实现） |
| stdio 函数 | 链接到 libc | 零开销（系统实现） |
| string 函数 | 链接到 libc | 零开销（系统实现） |

### 编译期优化

- 标准库函数检测在编译期完成
- 不生成重复的声明和定义
- 减少生成的 C 代码体积

---

## 实际应用示例

### 1. 使用标准库函数

```uya
use std.c.stdlib.atoi;
use std.c.string.strlen;

fn main() i32 {
    var str: [byte: 10] = [];
    str[0] = 49 as byte;  // '1'
    str[1] = 50 as byte;  // '2'
    str[2] = 51 as byte;  // '3'
    str[3] = 0 as byte;   // '\0'
    
    // 使用标准库函数（链接到 C 标准库）
    const n: i32 = atoi(&str[0] as &byte);
    const len: usize = strlen(&str[0] as &byte);
    
    return 0;
}
```

### 2. 只读指针类型

```uya
// 只读指针参数
fn print_string(s: &const byte) void {
    // s 不能被修改，确保类型安全
    // ...
}

fn main() i32 {
    var buffer: [byte: 100] = [];
    // &byte 可以隐式转换为 &const byte
    print_string(&buffer[0] as &byte);
    return 0;
}
```

### 3. 函数导出

```uya
// 导出函数（可被 C 代码调用）
export fn uya_api_function() i32 {
    return 42;
}

// 内部函数（static，仅当前文件可见）
fn internal_helper() void {
    // ...
}
```

---

## 下一步计划

根据 `todo_mini_to_full.md`：

### 短期计划（v0.2.33）
- **标准库完善**：继续扩展 C 标准库函数实现
- **错误处理增强**：完善错误联合类型的处理

### 中期计划
- **内存安全证明**：数组越界、空指针、未初始化、溢出检查
- **异步编程完善**：CPS 变换、状态机生成、运行时支持

### 长期计划
- **并发安全**：基于原子类型的并发安全保证
- **完整标准库**：字符串处理、集合、I/O、网络等

---

## 相关资源

- **语言规范**：`docs/uya.md` - 类型系统和标准库章节
- **实现规范**：`docs/compiler-c-spec/UYA_MINI_SPEC.md`
- **待办事项**：`docs/todo_mini_to_full.md`
- **测试用例**：
  - `tests/programs/test_const_pointer.uya` - 只读指针测试
  - `tests/programs/test_export_for_c_complete.uya` - 函数导出测试
  - `tests/programs/test_std_stdlib_*.uya` - 标准库测试

---

**本版本修复了标准库函数与 C 标准库的冲突问题，增强了只读指针类型和函数导出规则支持，并扩展了标准库函数实现。C 实现与自举编译器已完全同步，所有 331 个测试用例全部通过，自举对比一致。编译器与 C 标准库的兼容性得到显著提升，为后续标准库扩展奠定了坚实基础。**
