# Uya 内置函数使用文档

> 版本：v0.1.0（2026-02-06）  
> 语言规范：0.42  
> 所有内置函数均以 `@` 开头，编译期展开，零运行时开销，无需导入或声明

---

## 目录

- [1. 类型反射函数](#1-类型反射函数)
  - [@size_of](#size_of)
  - [@align_of](#align_of)
  - [@len](#len)
- [2. 整数极值函数](#2-整数极值函数)
  - [@max](#max)
  - [@min](#min)
- [3. 源代码位置函数](#3-源代码位置函数)
  - [@src_name](#src_name)
  - [@src_path](#src_path)
  - [@src_line](#src_line)
  - [@src_col](#src_col)
  - [@func_name](#func_name)
- [4. 可变参数函数](#4-可变参数函数)
  - [@params](#params)
- [5. 宏编译时函数](#5-宏编译时函数)
  - [@mc_eval](#mc_eval)
  - [@mc_type](#mc_type)
  - [@mc_ast](#mc_ast)
  - [@mc_code](#mc_code)
  - [@mc_error](#mc_error)
  - [@mc_get_env](#mc_get_env)
- [6. 异步编程函数](#6-异步编程函数)
  - [@async_fn](#async_fn)
  - [@await](#await)

---

## 1. 类型反射函数

### @size_of

**函数签名**：
```uya
fn @size_of(Type) i32
fn @size_of(expr) i32
```

**功能描述**：
返回类型的字节大小（编译期常量）。支持传入类型名或表达式。

**参数**：
- `Type`：任意类型名（基础类型、数组、结构体、切片等）
- `expr`：任意表达式（从表达式推断类型）

**返回值**：
- `i32` 类型，表示类型的字节大小
- 编译期常量，零运行时开销

**使用示例**：
```uya
// 基础类型
const size_i32: i32 = @size_of(i32);        // 4
const size_i64: i32 = @size_of(i64);        // 8
const size_f32: i32 = @size_of(f32);        // 4
const size_bool: i32 = @size_of(bool);      // 1

// 数组类型
const size_arr: i32 = @size_of([i32: 10]);  // 40 (10 * 4)

// 结构体类型
struct Point {
    x: i32,
    y: i32
}
const size_point: i32 = @size_of(Point);    // 8 (4 + 4)

// 切片类型
const size_slice: i32 = @size_of(&[i32]);   // 8/16（32位/64位平台）

// 表达式
var x: i32 = 10;
const size_x: i32 = @size_of(x);            // 4

// 指针类型
const size_ptr: i32 = @size_of(&i32);       // 4/8（32位/64位平台）
```

**注意事项**：
- 对齐规则与 C99 一致
- 结构体大小包含填充字节
- 切片类型大小 = 指针大小 + 长度字段大小（平台相关）

---

### @align_of

**函数签名**：
```uya
fn @align_of(Type) i32
fn @align_of(expr) i32
```

**功能描述**：
返回类型的对齐字节数（编译期常量）。

**参数**：
- `Type`：任意类型名
- `expr`：任意表达式（从表达式推断类型）

**返回值**：
- `i32` 类型，表示类型的对齐字节数
- 编译期常量，零运行时开销

**使用示例**：
```uya
// 基础类型
const align_i8: i32 = @align_of(i8);        // 1
const align_i16: i32 = @align_of(i16);      // 2
const align_i32: i32 = @align_of(i32);      // 4
const align_i64: i32 = @align_of(i64);      // 8
const align_f64: i32 = @align_of(f64);      // 8

// 结构体类型
struct Mixed {
    a: i8,      // 对齐 1
    b: i32,     // 对齐 4
    c: i16      // 对齐 2
}
const align_mixed: i32 = @align_of(Mixed);  // 4（取最大对齐）

// 数组类型（与元素类型对齐相同）
const align_arr: i32 = @align_of([i32: 10]); // 4

// 指针类型
const align_ptr: i32 = @align_of(&i32);     // 4/8（平台相关）
```

**注意事项**：
- 对齐规则与 C99 一致
- 结构体对齐 = max(所有字段对齐)
- 数组对齐 = 元素类型对齐

---

### @len

**函数签名**：
```uya
fn @len(array: [T: N]) i32
fn @len(slice: &[T]) i32
fn @len(slice: &[T: N]) i32
```

**功能描述**：
返回数组或切片的元素个数。对于数组是编译期常量，对于切片是运行时值。

**参数**：
- `array`：固定大小数组
- `slice`：切片引用

**返回值**：
- `i32` 类型
- 对于数组：编译期常量 `N`
- 对于切片：运行时值（访问切片的 `.len` 字段）

**使用示例**：
```uya
// 固定数组（编译期常量）
var arr: [i32: 10] = [];
const len1: i32 = @len(arr);                // 10

// 空数组字面量（从声明获取大小）
var buffer: [i32: 100] = [];
const len2: i32 = @len(buffer);             // 100（不是 0！）

// 多维数组
var matrix: [[i32: 5]: 3] = [];
const rows: i32 = @len(matrix);             // 3
const cols: i32 = @len(matrix[0]);          // 5

// 切片（运行时值）
fn process(data: &[i32]) void {
    const count: i32 = @len(data);          // 运行时访问 data.len
    // ...
}

// 已知长度的切片
fn process_fixed(data: &[i32: 10]) void {
    const count: i32 = @len(data);          // 10（编译期常量）
}
```

**注意事项**：
- **空数组字面量**：`var x: [T: N] = [];` 时，`@len(x)` 返回 `N`，不是 0
- 对于切片，等价于访问 `.len` 字段
- 对于数组，在编译期求值，零运行时开销

---

## 2. 整数极值函数

### @max

**函数签名**：
```uya
@max  // 类型从上下文推断
```

**功能描述**：
返回整数类型的最大值（编译期常量）。类型从赋值上下文自动推断。

**参数**：
- 无参数，类型通过上下文推断

**返回值**：
- 推断出的整数类型
- 编译期常量，零运行时开销

**使用示例**：
```uya
// 有符号整数
const max_i8: i8 = @max;        // 127
const max_i16: i16 = @max;      // 32767
const max_i32: i32 = @max;      // 2147483647
const max_i64: i64 = @max;      // 9223372036854775807

// 无符号整数
const max_u8: u8 = @max;        // 255
const max_u16: u16 = @max;      // 65535
const max_u32: u32 = @max;      // 4294967295
const max_u64: u64 = @max;      // 18446744073709551615

// 在表达式中使用
fn clamp(value: i32, min_val: i32, max_val: i32) i32 {
    if value < min_val {
        return min_val;
    }
    if value > max_val {
        return max_val;
    }
    return value;
}

// 边界检查
fn safe_add(a: i32, b: i32) !i32 {
    if b > 0 && a > (@max - b) {
        return error.Overflow;
    }
    return a + b;
}
```

**注意事项**：
- 必须有明确的类型上下文（变量声明、函数参数等）
- 仅支持整数类型（i8, i16, i32, i64, u8, u16, u32, u64）
- 如果类型无法推断，会产生编译错误

---

### @min

**函数签名**：
```uya
@min  // 类型从上下文推断
```

**功能描述**：
返回整数类型的最小值（编译期常量）。类型从赋值上下文自动推断。

**参数**：
- 无参数，类型通过上下文推断

**返回值**：
- 推断出的整数类型
- 编译期常量，零运行时开销

**使用示例**：
```uya
// 有符号整数
const min_i8: i8 = @min;        // -128
const min_i16: i16 = @min;      // -32768
const min_i32: i32 = @min;      // -2147483648
const min_i64: i64 = @min;      // -9223372036854775808

// 无符号整数
const min_u8: u8 = @min;        // 0
const min_u16: u16 = @min;      // 0
const min_u32: u32 = @min;      // 0
const min_u64: u64 = @min;      // 0

// 在表达式中使用
fn abs(value: i32) i32 {
    if value == @min {
        // 特殊处理：i32 最小值的绝对值无法表示为 i32
        return @max;
    }
    if value < 0 {
        return -value;
    }
    return value;
}
```

**注意事项**：
- 必须有明确的类型上下文
- 仅支持整数类型
- 无符号类型的 `@min` 总是 0

---

## 3. 源代码位置函数

### @src_name

**函数签名**：
```uya
fn @src_name() &[i8]
```

**功能描述**：
返回当前源文件的文件名（不包含路径），编译期展开为字符串常量。

**参数**：
- 无参数

**返回值**：
- `&[i8]` 类型（字节切片）
- 编译期字符串常量，零运行时开销

**使用示例**：
```uya
extern printf(fmt: *byte, ...) i32;

fn debug_info() void {
    const filename: &[i8] = @src_name;
    printf("File: %s\n" as *byte, filename);
}

fn main() i32 {
    debug_info();  // 输出：File: main.uya
    return 0;
}
```

**注意事项**：
- 仅包含文件名，不包含路径
- 编译期展开为字符串常量
- 字符串常量自动收集并生成到输出文件中

---

### @src_path

**函数签名**：
```uya
fn @src_path() &[i8]
```

**功能描述**：
返回当前源文件的完整路径，编译期展开为字符串常量。

**参数**：
- 无参数

**返回值**：
- `&[i8]` 类型（字节切片）
- 编译期字符串常量，零运行时开销

**使用示例**：
```uya
extern printf(fmt: *byte, ...) i32;

fn log_location() void {
    const path: &[i8] = @src_path;
    const line: i32 = @src_line;
    printf("Location: %s:%d\n" as *byte, path, line);
}

fn main() i32 {
    log_location();  // 输出：Location: /path/to/main.uya:10
    return 0;
}
```

**注意事项**：
- 包含完整的文件路径（编译时的路径）
- 路径格式取决于编译环境（Unix: `/`, Windows: `\`）

---

### @src_line

**函数签名**：
```uya
fn @src_line() i32
```

**功能描述**：
返回当前代码所在的行号，编译期展开为整数常量。

**参数**：
- 无参数

**返回值**：
- `i32` 类型
- 编译期整数常量，零运行时开销

**使用示例**：
```uya
extern printf(fmt: *byte, ...) i32;

fn assert_impl(condition: bool, msg: *byte, line: i32) void {
    if !condition {
        printf("Assertion failed at line %d: %s\n" as *byte, line, msg);
        // 触发断言失败处理
    }
}

// 自定义断言宏（伪代码，实际需要宏系统）
fn main() i32 {
    const x: i32 = 10;
    
    // 手动传递行号
    if !(x > 0) {
        assert_impl(false, "x must be positive" as *byte, @src_line);
    }
    
    printf("Current line: %d\n" as *byte, @src_line);  // 输出当前行号
    return 0;
}
```

**注意事项**：
- 行号从 1 开始
- 每次调用 `@src_line` 都会展开为调用处的行号

---

### @src_col

**函数签名**：
```uya
fn @src_col() i32
```

**功能描述**：
返回当前代码所在的列号，编译期展开为整数常量。

**参数**：
- 无参数

**返回值**：
- `i32` 类型
- 编译期整数常量，零运行时开销

**使用示例**：
```uya
extern printf(fmt: *byte, ...) i32;

fn main() i32 {
    const line: i32 = @src_line;
    const col: i32 = @src_col;
    
    printf("Position: line %d, column %d\n" as *byte, line, col);
    return 0;
}
```

**注意事项**：
- 列号从 1 开始
- 指向 `@src_col` 标记的起始位置

---

### @func_name

**函数签名**：
```uya
fn @func_name() &[i8]
```

**功能描述**：
返回当前函数的名称，编译期展开为字符串常量。仅能在函数体内使用。

**参数**：
- 无参数

**返回值**：
- `&[i8]` 类型（字节切片）
- 编译期字符串常量，零运行时开销

**使用示例**：
```uya
extern printf(fmt: *byte, ...) i32;

fn trace_enter() void {
    const func: &[i8] = @func_name;
    const line: i32 = @src_line;
    printf("Entering %s at line %d\n" as *byte, func, line);
}

fn process_data(data: &[i32]) void {
    const func: &[i8] = @func_name;
    printf("Function: %s\n" as *byte, func);  // 输出：Function: process_data
    // ...
}

fn main() i32 {
    const func: &[i8] = @func_name;
    printf("Main function: %s\n" as *byte, func);  // 输出：Main function: main
    
    trace_enter();     // 输出：Entering trace_enter at line ...
    process_data(null);
    return 0;
}
```

**注意事项**：
- **仅能在函数体内使用**，在函数外使用会产生编译错误
- 返回的是函数的原始名称（不包含修饰符）
- 对于 `main` 函数，返回 `"main"`

**错误示例**：
```uya
// 编译错误：@func_name 只能在函数体内使用
const global_func: &[i8] = @func_name;  // ❌ 错误！

fn valid_usage() void {
    const local_func: &[i8] = @func_name;  // ✓ 正确
}
```

---

## 4. 可变参数函数

### @params

**函数签名**：
```uya
@params  // 在可变参数函数内部使用
```

**功能描述**：
在可变参数函数内部访问可变参数列表。这是一个特殊的内置标识符，表示 `va_list` 类型的参数。

**使用场景**：
- 用于实现类似 `printf` 的可变参数函数
- 与 FFI 的 `va_start`、`va_arg`、`va_end` 配合使用

**使用示例**：
```uya
// 外部 C 函数声明
extern va_start(ap: &void, last_param: &void) void;
extern va_arg(ap: &void, type_size: i32) i32;
extern va_end(ap: &void) void;
extern printf(fmt: *byte, ...) i32;

// Uya 可变参数函数
fn my_printf(fmt: *byte, ...) void {
    // @params 代表可变参数列表
    var ap: &void = @params;
    
    // 使用 C 的 va_* 函数处理
    printf(fmt, ap);
}

fn sum_ints(count: i32, ...) i32 {
    var result: i32 = 0;
    var ap: &void = @params;
    
    var i: i32 = 0;
    while i < count {
        const value: i32 = va_arg(ap, @size_of(i32));
        result = result + value;
        i = i + 1;
    }
    
    return result;
}

fn main() i32 {
    my_printf("Hello, %s!\n" as *byte, "World" as *byte);
    
    const total: i32 = sum_ints(3, 10, 20, 30);
    printf("Total: %d\n" as *byte, total);  // 输出：Total: 60
    
    return 0;
}
```

**注意事项**：
- 仅在声明为 `...` 的可变参数函数内有效
- 需要配合 C 的 `va_*` 函数使用
- 类型安全需要手动保证（与 C 可变参数相同）

---

## 5. 宏编译时函数

> **状态**：语法解析已实现，CPS 变换和求值引擎待实现  
> **参考**：规范 §25 宏系统

### @mc_eval

**函数签名**：
```uya
fn @mc_eval(expr) T  // 编译时求值
```

**功能描述**：
在编译时对表达式求值，返回求值结果。仅能在宏定义 (`mc`) 内部使用。

**参数**：
- `expr`：任意编译期可求值的表达式

**返回值**：
- 表达式的求值结果
- 类型由表达式决定

**使用示例**：
```uya
// 编译时计算斐波那契数
mc fib(n: i32) i32 {
    if n <= 1 {
        return n;
    }
    const a: i32 = @mc_eval(fib(n - 1));
    const b: i32 = @mc_eval(fib(n - 2));
    return a + b;
}

fn main() i32 {
    const fib10: i32 = fib(10);  // 编译时计算，结果 55
    return fib10;
}
```

**注意事项**：
- 仅在宏定义内使用
- 表达式必须在编译期可求值
- 递归求值受编译器递归深度限制

---

### @mc_type

**函数签名**：
```uya
fn @mc_type(expr) TypeInfo
```

**功能描述**：
在编译时获取表达式的类型信息，返回 `TypeInfo` 结构体。

**返回值**：
```uya
struct TypeInfo {
    kind: TypeKind,      // 类型种类（i32, struct, etc.）
    name: *byte,         // 类型名称
    size: i32,           // 类型大小
    align: i32,          // 类型对齐
    // ... 其他字段
}
```

**使用示例**：
```uya
mc print_type_info(expr) void {
    const info: TypeInfo = @mc_type(expr);
    @mc_eval(printf("Type: %s, Size: %d, Align: %d\n" as *byte, 
                     info.name, info.size, info.align));
}

fn main() i32 {
    var x: i32 = 10;
    print_type_info(x);  // 输出：Type: i32, Size: 4, Align: 4
    return 0;
}
```

---

### @mc_ast

**函数签名**：
```uya
fn @mc_ast(code) ASTNode
```

**功能描述**：
将代码片段转换为抽象语法树（AST）。

**使用示例**：
```uya
mc generate_getter(field_name) code {
    const ast: ASTNode = @mc_ast({
        fn get_field() i32 {
            return self.field_name;
        }
    });
    return @mc_code(ast);
}
```

---

### @mc_code

**函数签名**：
```uya
fn @mc_code(ast: ASTNode) code
```

**功能描述**：
将抽象语法树转换为代码。

---

### @mc_error

**函数签名**：
```uya
fn @mc_error(msg: *byte) void
```

**功能描述**：
在编译时报告错误。

**使用示例**：
```uya
mc check_positive(n: i32) void {
    if n <= 0 {
        @mc_error("Value must be positive");
    }
}
```

---

### @mc_get_env

**函数签名**：
```uya
fn @mc_get_env(key: *byte) *byte
```

**功能描述**：
在编译时获取环境变量。

**使用示例**：
```uya
mc get_build_env() *byte {
    return @mc_get_env("BUILD_ENV");
}
```

---

## 6. 异步编程函数

> **状态**：语法解析已实现，CPS 变换和状态机生成待实现  
> **参考**：规范 §18 异步编程

### @async_fn

**函数签名**：
```uya
@async_fn fn function_name(...) !Future<T>
```

**功能描述**：
标记函数为异步函数，触发编译器进行 CPS 变换，生成显式状态机。

**使用示例**：
```uya
@async_fn fn fetch_data(url: *byte) !Future<i32> {
    const conn: Connection = try @await connect(url);
    const data: i32 = try @await read_data(conn);
    return data;
}
```

**注意事项**：
- 必须返回 `!Future<T>` 类型
- 函数体内可以使用 `@await`
- 编译器会自动生成状态机代码

---

### @await

**函数签名**：
```uya
try @await future_expr
```

**功能描述**：
唯一的显式挂起点，等待异步操作完成。仅能在 `@async_fn` 函数内使用。

**使用示例**：
```uya
@async_fn fn process() !Future<void> {
    // 等待异步 I/O
    const data: &[byte] = try @await read_file("config.txt");
    
    // 等待异步计算
    const result: i32 = try @await compute_heavy_task(data);
    
    // 等待异步写入
    try @await write_file("output.txt", result);
}
```

**注意事项**：
- 必须配合 `try` 使用（处理错误）
- 仅在 `@async_fn` 函数内有效
- 每个 `@await` 是一个挂起点，状态机会在此处保存/恢复

---

## 7. 内置函数分类总结

| 分类 | 函数 | 编译期 | 运行时 | 状态 |
|------|------|--------|--------|------|
| **类型反射** | `@size_of` | ✓ | - | ✅ 已实现 |
| | `@align_of` | ✓ | - | ✅ 已实现 |
| | `@len` (数组) | ✓ | - | ✅ 已实现 |
| | `@len` (切片) | - | ✓ | ✅ 已实现 |
| **整数极值** | `@max` | ✓ | - | ✅ 已实现 |
| | `@min` | ✓ | - | ✅ 已实现 |
| **源码位置** | `@src_name` | ✓ | - | ✅ 已实现 |
| | `@src_path` | ✓ | - | ✅ 已实现 |
| | `@src_line` | ✓ | - | ✅ 已实现 |
| | `@src_col` | ✓ | - | ✅ 已实现 |
| | `@func_name` | ✓ | - | ✅ 已实现 |
| **可变参数** | `@params` | - | ✓ | ✅ 已实现 |
| **宏系统** | `@mc_eval` | ✓ | - | 🚧 语法解析完成 |
| | `@mc_type` | ✓ | - | 🚧 语法解析完成 |
| | `@mc_ast` | ✓ | - | 🚧 语法解析完成 |
| | `@mc_code` | ✓ | - | 🚧 语法解析完成 |
| | `@mc_error` | ✓ | - | 🚧 语法解析完成 |
| | `@mc_get_env` | ✓ | - | 🚧 语法解析完成 |
| **异步编程** | `@async_fn` | ✓ | ✓ | 🚧 语法解析完成 |
| | `@await` | ✓ | ✓ | 🚧 语法解析完成 |

---

## 8. 命名惯例

Uya 内置函数遵循以下命名惯例：

1. **单一概念**：使用短形式
   - `@len`, `@max`, `@min`

2. **复合概念**：使用 snake_case（下划线分隔）
   - `@size_of`, `@align_of`, `@async_fn`
   - `@src_name`, `@src_path`, `@src_line`, `@src_col`, `@func_name`
   - `@mc_eval`, `@mc_type`, `@mc_ast`, `@mc_code`, `@mc_error`, `@mc_get_env`

3. **前缀约定**：
   - `@mc_*`：宏编译时函数（Macro Compile-time）
   - `@src_*`：源代码位置相关（Source）

---

## 9. 性能保证

所有内置函数遵循 Uya 的零成本抽象原则：

| 类别 | 性能保证 |
|------|----------|
| **编译期展开** | `@size_of`, `@align_of`, `@len(数组)`, `@max`, `@min`, `@src_*`, `@func_name` |
| **零运行时开销** | 上述函数在编译时完全求值，生成常量 |
| **运行时访问** | `@len(切片)` → 访问切片的 `.len` 字段（一次内存访问） |
| **可变参数** | `@params` → 零抽象开销，直接映射到 C `va_list` |

---

## 10. 常见使用模式

### 10.1 调试和日志

```uya
extern printf(fmt: *byte, ...) i32;

fn log(level: *byte, msg: *byte) void {
    printf("[%s] %s:%d in %s(): %s\n" as *byte,
           level,
           @src_name,
           @src_line,
           @func_name,
           msg);
}

fn main() i32 {
    log("INFO" as *byte, "Application started" as *byte);
    // 输出：[INFO] main.uya:15 in main(): Application started
    return 0;
}
```

### 10.2 断言实现

```uya
extern printf(fmt: *byte, ...) i32;
extern exit(code: i32) void;

fn assert(condition: bool, msg: *byte, file: *byte, line: i32, func: *byte) void {
    if !condition {
        printf("Assertion failed: %s\n" as *byte, msg);
        printf("  at %s:%d in %s()\n" as *byte, file, line, func);
        exit(1);
    }
}

fn main() i32 {
    const x: i32 = 10;
    
    if !(x > 0) {
        assert(false, 
               "x must be positive" as *byte,
               @src_name,
               @src_line,
               @func_name);
    }
    
    return 0;
}
```

### 10.3 泛型容器大小计算

```uya
struct Buffer<T> {
    data: [T: 1024],
    count: i32
}

fn buffer_info<T>() void {
    const elem_size: i32 = @size_of(T);
    const total_size: i32 = @size_of(Buffer<T>);
    const capacity: i32 = @len(Buffer<T>.data);
    
    printf("Element size: %d\n" as *byte, elem_size);
    printf("Buffer size: %d\n" as *byte, total_size);
    printf("Capacity: %d\n" as *byte, capacity);
}
```

---

## 11. 版本历史

| 版本 | 日期 | 变更 |
|------|------|------|
| v0.1.0 | 2026-02-06 | 新增源代码位置函数：`@src_name`, `@src_path`, `@src_line`, `@src_col`, `@func_name` |
| v0.1.0 | 2026-02-04 | 初始版本：`@size_of`, `@align_of`, `@len`, `@max`, `@min`, `@params`, 宏系统函数（语法），异步函数（语法） |

---

## 12. 参考文档

- [Uya 语言规范](uya.md) - 完整语言规范
- [语法速查](grammar_quick.md) - 语法速查手册
- [Uya Mini 规范](compiler-c-spec/UYA_MINI_SPEC.md) - 当前实现的子集规范
- [发行说明](RELEASE_v0.1.0.md) - v0.1.0 版本说明

---

**本文档由 Uya 编译器团队维护，最后更新：2026-02-06**

