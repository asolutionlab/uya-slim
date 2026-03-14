# Uya 语法速查手册（Quick Reference）

本文档是 Uya 语言的快速参考手册，包含精简语法定义、常用代码模式和速查表。

> **注意**：本文档是 [uya.md](./uya.md) 的补充，适合日常开发和快速查阅。  
> 对于完整的、无歧义的 BNF 语法定义，请参考 [grammar_formal.md](./grammar_formal.md)。

---

## 一、核心语法（30秒掌握）

### 基本结构

```uya
// 函数定义（返回类型可为任意类型，含切片 &[T]、错误联合 !T 或 !&[byte]）
fn add(a: i32, b: i32) i32 {
    return a + b;
}

// 结构体定义
struct Point {
    x: f32,
    y: f32
}

// 联合体定义
union IntOrFloat {
    i: i32,
    f: f64
}

// 变量声明
const x: i32 = 42;
var y: i32 = 10;
```

---

## 二、类型系统速查

| 类型 | 写法 | 示例 | 说明 |
|------|------|------|------|
| **整数** | `i8` `i16` `i32` `i64`<br>`u8` `u16` `u32` `u64` `usize` | `const x: i32 = 42;`<br>`const hex: i32 = 0xFF;`<br>`const oct: i32 = 0o755;`<br>`const bin: i32 = 0b1010;`<br>`const big: i32 = 1_000_000;`<br>`const small: i8 = 100i8;`<br>`const mask: u8 = 0xFFu8;` | 有符号/无符号整数<br>支持十六进制 (`0xFF`)、八进制 (`0o755`)、二进制 (`0b1010`)<br>支持下划线分隔符 (`1_000_000`)<br>支持类型后缀：`i8/i16/i32/i64/u8/u16/u32/u64/usize`（如 `100i8`、`0xFFu8`） |
| **浮点** | `f32` `f64` | `const pi: f64 = 3.14;`<br>`const e: f64 = 2.718_281_828;`<br>`const v32: f32 = 1.5f32;` | 单/双精度浮点数<br>支持下划线分隔符<br>支持类型后缀：`f32`/`f64`（如 `1.5f32`、`3.14f64`） |
| **布尔** | `bool` | `const flag: bool = true;` | 布尔值 |
| **数组** | `[T: N]` | `const arr: [i32: 5] = [1,2,3,4,5];`<br>`var buf: [i32: 100] = [];` | 固定长度数组，`[]` 表示未初始化 |
| **切片** | `&[T]` `&[T: N]` | `const slice: &[i32] = &arr[2:5];` | 动态/已知长度切片 |
| **指针** | `&T` `&const T` `*T` `*const T` | `const ptr: &i32 = &x;`<br>`const read_only: &const byte = "hello";` | Uya指针/只读指针/FFI指针（0.42新增&const T） |
| **结构体** | `StructName`<br>`StructName<T>` | `const p: Point = Point{x: 1.0, y: 2.0};`<br>`const vec: Vec<i32> = ...;` | 结构体类型，支持泛型参数 |
| **联合体** | `UnionName` | `const v: IntOrFloat = IntOrFloat.i(42);` | 标签联合体，编译期证明安全 |
| **接口** | `InterfaceName`<br>`InterfaceName<T>` | `const writer: IWriter = ...;`<br>`const iter: Iterator<String> = ...;` | 接口类型，支持泛型参数 |
| **元组** | `(T1, T2, ...)` | `const t: (i32, f64) = (10, 3.14);` | 元组类型 |
| **错误联合** | `!T` | `fn may_fail() !i32 { ... }`<br>`fn encode() !&[byte] { ... }` | 可能返回错误；可与切片组合为返回值 `!&[byte]` |
| **原子类型** | `atomic T` | `value: atomic i32` | 原子类型 |
| **函数指针** | `fn(...) type` | `type Func = fn(i32, i32) i32;` | 函数指针类型 |

---

## 三、控制流速查

### if-else

```uya
if x > 0 {
    // ...
} else {
    // ...
}
```

### while 循环

```uya
var i: i32 = 0;
while i < 10 {
    // ...
    i = i + 1;
}
```

### for 循环

```uya
// 值迭代（只读）
for arr |v| {
    // 使用 v
}

// 引用迭代（可修改）
for arr |&ptr| {
    // 可以修改 *ptr
}

// 整数范围迭代
for 0..10 |i| {
    // i 从 0 到 9
}

// 只循环次数（不绑定变量）
for 0..10 {
    // 只执行10次
}
```

### match 匹配

```uya
match value {
    1 => handle_one(),
    error.Err => handle_err(),
    else => default()
};

// 联合体模式匹配（必须处理所有变体）
match union_value {
    .i(x) => printf("整数: %d\n", x),
    .f(x) => printf("浮点: %f\n", x)
}
```

---

## 四、错误处理速查

### 定义错误

```uya
// 预定义错误（可选）
error MyError;

// 运行时错误（无需预定义）
// 直接使用 error.ErrorName
```

**error_id 稳定性**：`error_id = hash(error_name)`，相同错误名在任意编译中映射到相同 `error_id`；hash 冲突时编译器报错并提示冲突名称。

### 返回错误

```uya
fn may_fail() !i32 {
    if condition {
        return error.MyError;
    }
    return 42;
}
```

### 传播错误

```uya
const x = try may_fail();  // 自动传播错误
```

### 捕获错误

```uya
const x = may_fail() catch |err| {
    // 处理错误
    return 0;
};
```

---

## 五、常用模式模板

### 函数定义模板

```uya
// 内部函数（生成的 C 代码添加 static）
fn name(param: Type) ReturnType {
    // 函数体
    return value;
}

// 导出函数（生成的 C 代码不添加 static，带 uya_ 前缀）
export fn public_function(param: Type) ReturnType {
    // 函数体
    return value;
}

// 外部 C 函数声明
extern fn c_function(param: *byte) i32;

// 外部 C 函数实现（Uya 实现，以裸函数名导出，不带 uya_ 前缀）
extern fn my_wrapper(param: *byte) i32 {
    // Uya 实现代码
    return 0;
}

// 导出外部 C 函数声明（无函数体）→ 链接到 C 标准库
export extern fn malloc(size: usize) *void;

// 导出外部 C 函数实现（有函数体）→ Uya 实现，以裸函数名导出
export extern fn strcmp(s1: &const byte, s2: &const byte) i32 {
    // Uya 实现代码
    return 0;
}

// extern "libc" 语法（0.43 新增）：显式声明 C 标准库函数
// byte 直接对应 C 的 char，与 C 字符串兼容
extern "libc" fn strlen(s: &byte) usize;
extern "libc" fn atoi(s: &byte) i32;
extern "libc" fn printf(fmt: &byte, ...) i32;

// extern 变量支持（0.43 新增）：导入/导出 C 全局变量
// 导入 C 标准库全局变量
extern const errno: i32;           // 只读：extern const int errno;
extern var optind: i32;            // 可变：extern int optind;
extern const stdout: *void;        // C: extern FILE *stdout;

// 导出 Uya 变量给 C
export const VERSION: &byte = "1.0.0";  // C: const char *VERSION = "1.0.0";
export var debug_mode: i32 = 0;         // C: int debug_mode = 0;

// 链接到 C 库定义的变量（不生成代码）
export extern const ENOENT: i32;

// 可能失败的函数
fn name(param: Type) !ReturnType {
    if error_condition {
        return error.ErrorName;
    }
    return value;
}

// 泛型函数
fn max<T: Ord>(a: T, b: T) T {
    if a > b { return a; }
    return b;
}
```

### 结构体定义模板

```uya
// 基本结构体
struct Name {
    field1: Type1,
    field2: Type2
}

// 结构体带方法（内部定义）
struct Name {
    field: Type,
    
    fn method(self: &Self) ReturnType {
        // 方法体
    }
}

// 结构体方法（外部定义）
struct Name {
    field: Type
}

Name {
    fn method(self: &Self) ReturnType {
        // 方法体
    }
}

// 泛型结构体
struct Vec<T: Default> {
    data: &T,
    len: i32,
    cap: i32
}

// 泛型方法（0.47 新增）
struct Container<T> {
    value: T,
    
    // 泛型方法：独立类型参数 U
    fn as_type<U>(self: &Self) U {
        return self.value as U;
    }
}

// 调用泛型方法
const c: Container<i32> = Container<i32>{ value: 42 };
const v: i64 = c.as_type<i64>();  // 显式指定类型参数
```

### 联合体定义模板

```uya
// 基本联合体
union Name {
    variant1: Type1,
    variant2: Type2
}

// 创建：UnionName.variant(expr)
const v = IntOrFloat.i(42);
const f = IntOrFloat.f(3.14);

// 访问：必须 match 或已知标签直接访问
match v {
    .i(x) => printf("%d\n", x),
    .f(x) => printf("%f\n", x)
}
```

### 接口定义和实现模板

```uya
// 接口定义
interface IWriter {
    fn write(self: &Self, buf: *byte, len: i32) i32;
}

// 接口实现
struct MyStruct : IWriter {
    field: Type,
    
    fn write(self: &Self, buf: *byte, len: i32) i32 {
        // 实现
        return len;
    }
}

// 泛型接口
interface Iterator<T> {
    fn next(self: &Self) union Option<T>;
}
```

### 枚举定义模板

```uya
enum Color {
    Red,
    Green,
    Blue
}

// 带显式值
enum HttpStatus : u16 {
    Ok = 200,
    NotFound = 404,
    Error = 500
}
```

---

## 六、运算符优先级

> 完整说明：详见 [uya.md](./uya.md#运算符)

---

## 七、模块系统速查

### 导出

```uya
export fn public_function() i32 { ... }
export struct PublicStruct { ... }
export interface PublicInterface { ... }
export const PUBLIC_CONST: i32 = 42;
export error PublicError;
export mc public_macro() expr { ... }  // 导出宏
```

### 导入

```uya
// 导入整个模块
use std.io;

// 导入特定项
use std.io.read_file;

// 导入并重命名
use std.io as io_module;

// 导入宏
use math_macros.square;
```

**同目录文件合并规则**：
- 同一目录下的所有 `.uya` 文件都属于同一个模块
- 模块路径由目录路径决定，不包含文件名
- 例如：`std/io/file.uya` 和 `std/io/stream.uya` 都属于 `std.io` 模块
- 使用：`use std.io.fopen;` 或 `use std.io.fgetc;`（不需要 `std.io.file.fopen`）

---

## 八、FFI（外部函数接口）速查

### 声明外部 C 函数

```uya
extern printf(fmt: *byte, ...) i32;
```

### 可变参数与 @params（uya.md §5.4）

```uya
// Uya 可变参数函数
fn log_error(fmt: *byte, ...) void {
    printf("ERROR: ");
    printf(fmt, ...);  // 使用 ... 转发可变参数
}

fn sum(...) i32 {
    const args = @params;  // 所有参数作为元组
    var total: i32 = 0;
    for args |val| { total += val; }
    return total;
}
```

- 声明：`...` 为参数列表最后一项
- 转发：`printf(fmt, ...)` 将可变参数转发
- `@params`：函数体内访问所有参数作为元组
- `@va_start` / `@va_end` / `@va_arg` / `@va_copy`：可变参数栈访问
  - 声明：`@va_start(&ap, last)`、`@va_end(&ap)`、`@va_arg(ap, Type)`、`@va_copy(&dest, src)`
  - 初始化：`var ap: va_list = va_list{}; @va_start(&ap, last_param);`
  - 遍历：`@va_arg(ap, i32)`、`@va_arg(ap, &byte)`、`@va_arg(ap, i64)` 等
  - 复制：`@va_copy(&ap2, ap1)` 用于多次遍历

### 导出函数给 C

```uya
extern fn my_callback(x: i32, y: i32) i32 {
    return x + y;
}
```

### 函数指针类型

```uya
type ComparFunc = fn(*void, *void) i32;
const cmp: ComparFunc = &my_compare;
```

### Uya 指针传递给 FFI 函数

```uya
extern write(fd: i32, buf: *byte, count: i32) i32;

fn main() i32 {
    var buffer: [byte: 100] = [];
    // Uya 普通指针通过 as 显式转换为 FFI 指针类型
    const result: i32 = write(1, &buffer[0] as *byte, 100);
    return result;
}
```

**说明**：
- ✅ `&T as *T`：Uya 普通指针可以显式转换为 FFI 指针类型（安全转换，无精度损失）
- 仅在 FFI 函数调用时使用，符合"显式控制"设计哲学
- 编译期检查，无运行时开销

---

## 九、切片语法速查

```uya
var arr: [i32: 10] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9];

// 基本切片
const slice1: &[i32] = &arr[2:5];      // [2, 3, 4]

// 负数索引切片
const slice2: &[i32] = &arr[-3:3];     // [7, 8, 9]（等价于 &arr[7:3]）

// 已知长度切片
const exact: &[i32: 3] = &arr[2:3];    // [2, 3, 4]

// for循环迭代切片
for slice1 |v| {
    // 使用 v
}
```

---

## 十、字符串插值速查

```uya
const name = "Uya";
const value: i32 = 42;

// 简单插值
const msg1 = "Hello, ${name}!";

// 格式化插值
const msg2 = "Value: ${value:d}";      // 十进制整数
const msg3 = "Pi: ${pi:.2f}";          // 浮点数，2位小数
const msg4 = "Hex: ${value:x}";        // 十六进制
```

---

## 十一、原子操作速查

```uya
struct Counter {
    value: atomic i32
}

fn increment(counter: *Counter) void {
    counter.value += 1;      // 自动原子 fetch_add
    const v: i32 = counter.value;  // 自动原子 load
    counter.value = 10;      // 自动原子 store
}
```

---

## 十二、defer 和 errdefer 速查

```uya
fn example() !void {
    defer {
        // 无论成功或失败都执行
        cleanup();
    }
    
    errdefer {
        // 只在错误返回时执行
        rollback();
    }
    
    // 函数逻辑...
}
```

**块内禁止控制流语句**（defer/errdefer 相同）：
- ✅ 允许：表达式、赋值、函数调用、语句块
- ❌ 禁止：`return`、`break`、`continue` 等控制流语句
- ✅ 替代：使用变量记录状态，在 defer/errdefer 外处理控制流

---

## 十三、内联汇编速查

### 基本语法格式

```uya
@asm {
    // 单条指令
    "instruction template" (inputs, -> outputs)
        clobbers = [reg1, reg2, "memory"];
    
    // 多条指令
    "mov rax, 1" (-> _);
    "syscall" (rax, rdi, -> result);
}
```

**语法元素**：
- `instruction template`：汇编指令模板，使用 `{name}` 占位符
- `inputs`：输入表达式列表
- `outputs`：输出表达式列表（`->` 之后）
- `clobbers`：被修改的寄存器列表

### 常用指令示例

```uya
// 基本算术
fn add_asm(a: i32, b: i32) i32 {
    var result: i32;
    @asm {
        "add {a}, {b}" (a, b, -> result);
    }
    return result;
}

// 系统调用（x86-64 Linux）
fn syscall_write(fd: i32, buf: &const byte, count: i32) !i32 {
    var result: i64;
    @asm {
        "mov rax, 1" (-> _);
        "mov rdi, {fd}" (fd, -> _);
        "mov rsi, {buf}" (buf, -> _);
        "mov rdx, {count}" (count, -> _);
        "syscall" (-> result);
    } clobbers = ["rcx", "r11", "memory"];
    
    if result < 0 { return error.SyscallFailed; }
    return result as! i32;
}

// 原子操作
fn atomic_fetch_add(ptr: &atomic i32, value: i32) i32 {
    var old: i32;
    @asm {
        "lock xadd {ptr}, {value}" (@asm_mem(ptr), value, -> old);
    }
    return old;
}

// CPUID 指令
fn cpuid(leaf: u32) (u32, u32, u32, u32) {
    var eax: u32, ebx: u32, ecx: u32, edx: u32;
    @asm {
        "mov eax, {leaf}" (leaf, -> eax);
        "cpuid" (eax, -> eax, ebx, ecx, edx);
    }
    return (eax, ebx, ecx, edx);
}
```

### 类型支持列表

#### 寄存器类型

| 类型 | 说明 | 平台 |
|------|------|------|
| `@asm_reg` | 编译器自动分配的通用寄存器 | 跨平台 |
| `@asm_reg_x64` | x86-64 专用寄存器 | x86-64 |
| `@asm_reg_x86` | x86 专用寄存器 | x86 |
| `@asm_reg_arm64` | ARM64 专用寄存器 | ARM64 |

#### 内存操作类型

```uya
type @asm_mem<T> = opaque;  // 类型安全的内存操作
```

**使用示例**：
```uya
fn read_u32(ptr: &u32) u32 {
    var value: u32;
    @asm {
        "mov {value}, [{ptr}]" (@asm_mem(ptr), -> value);
    }
    return value;
}
```

### 平台差异说明

#### x86-64 平台

```uya
// 系统调用号
const SYS_write: i64 = 1;
const SYS_read: i64 = 0;

// 系统调用约定
// rax = 系统调用号
// rdi, rsi, rdx, r10, r8, r9 = 参数
// rax = 返回值

@asm {
    "mov rax, {nr}" (syscall_nr, -> _);
    "mov rdi, {arg1}" (arg1, -> _);
    "syscall" (-> result);
} clobbers = ["rcx", "r11", "memory"];
```

#### ARM64 平台

```uya
// 系统调用号
const SYS_write: i64 = 64;
const SYS_read: i64 = 63;

// 系统调用约定
// x8 = 系统调用号
// x0-x5 = 参数
// x0 = 返回值

@asm {
    "mov x8, {nr}" (syscall_nr, -> _);
    "mov x0, {arg1}" (arg1, -> _);
    "svc #0" (-> result);
} clobbers = ["x16", "x17", "memory"];
```

### 平台检测

```uya
enum @asm_target {
    x86_64_linux,
    x86_64_macos,
    x86_64_windows,
    arm64_linux,
    arm64_macos,
    arm64_windows,
}

// 获取当前平台
const target: @asm_target = @asm_target();

// 条件编译
if @asm_target() == .x86_64_linux {
    // x86-64 Linux 代码
} else if @asm_target() == .arm64_linux {
    // ARM64 Linux 代码
}
```

### 安全约束

1. **类型检查**：输入/输出类型必须匹配
2. **寄存器验证**：寄存器约束不能与调用约定冲突
3. **内存安全**：内存操作必须有明确类型
4. **并发安全**：原子操作必须使用 `atomic T` 类型
5. **clobber 声明**：必须声明所有被修改的寄存器

### 错误示例

```uya
// ❌ 错误：类型不匹配
@asm {
    "mov {dst}, {src}" (src: f64, -> dst: i32);
}

// ❌ 错误：未声明 clobber
@asm {
    "mov rax, 1" (-> _);  // rax 被修改但未声明
}

// ✅ 正确：显式声明 clobber
@asm {
    "mov rax, 1" (-> _);
} clobbers = ["rax"];

// ❌ 错误：非原子类型的原子操作
@asm {
    "lock xadd {ptr}, {value}" (@asm_mem(ptr), value, -> old);
    // ptr 必须是 &atomic i32 类型
}
```

### 最佳实践

1. **优先使用编译器优化**：能用 Uya 原生语法的，不要用 @asm
2. **显式声明 clobbers**：声明所有被修改的寄存器
3. **使用类型安全内存操作**：使用 `@asm_mem` 包装指针
4. **平台抽象**：使用 `@asm_target()` 进行条件编译
5. **优先使用原子类型**：使用 `atomic T` 类型

**详细文档**：
- [内联汇编设计文档](asm_design.md)
- [内联汇编 API 参考](asm_api_reference.md)
- [内联汇编最佳实践](asm_best_practices.md)

---

## 十四、宏系统速查

### 宏定义

```uya
// 基本宏定义
mc macro_name(param1: expr, param2: type) return_tag {
    // 宏体
}

// 导出宏（供其他模块使用）
export mc add(a: expr, b: expr) expr {
    ${a} + ${b};
}
```

**参数类型**：`expr`（表达式）、`stmt`（语句）、`type`（类型）、`pattern`（模式）

**返回标签**：`expr`（表达式）、`stmt`（语句）、`struct`（结构体成员）、`type`（类型标识符）

### 编译时内置函数

| 函数 | 说明 | 示例 |
|------|------|------|
| `@mc_eval(expr)` | 编译时求值 | `@mc_eval(2 + 3)` → `5` |
| `@mc_type(T)` | 类型反射 | `@mc_type(i32)` → `TypeInfo` |
| `@mc_ast(code)` | 代码转 AST | `@mc_ast(x + y)` |
| `@mc_code(ast)` | AST 转代码 | `@mc_code(ast_node)` |
| `@mc_error(msg)` | 编译时错误 | `@mc_error("类型不匹配")` |
| `@mc_get_env(name)` | 读取环境变量 | `@mc_get_env("DEBUG")` |

**TypeInfo**：`@mc_type(expr)` 返回的结构体，至少含 `name`、`size`、`align`、`kind`、`is_*` 等；扩展实现可含 **`fields`**（结构体字段列表，元素为 FieldInfo），供宏内泛型序列化（如 `impl_json(StructName)`）使用。详见 [uya.md](uya.md) §25.4.2、[grammar_formal.md](grammar_formal.md)。

### 宏调用与跨模块使用

```uya
// 宏调用（与函数调用语法一致）
const result: i32 = add(10, 20);

// 导入其他模块的宏
use math_macros.square;
const sq: i32 = square(5);  // 25
```

### 语法糖

```uya
// 简化写法（自动包装为 @mc_code(@mc_ast(...))）
mc double(x: expr) expr {
    ${x} * 2;
}

// 等价于显式写法
mc double_explicit(x: expr) expr {
    @mc_code(@mc_ast(${x} * 2));
}
```
---

## 十五、常见问题与解答

### Q: 如何声明数组？
A: `const arr: [i32: 5] = [1,2,3,4,5];`

### Q: 如何定义可能失败的函数？
A: 使用 `!` 返回类型：`fn may_fail() !i32`

### Q: 如何导入模块？
A: `use std.io;` 或 `use std.io.read_file;`

### Q: 如何获取指针？
A: `const ptr: &i32 = &variable;`（Uya指针）、`const void_ptr: &void = &buffer as &void;`（通用指针）或 `const fptr: *void = ...;`（FFI指针）

### Q: 如何访问结构体字段？
A: `obj.field`（直接访问）或 `ptr.field`（指针自动解引用，等价于 `(*ptr).field`）

### Q: 如何给结构体字段赋值？
A: `obj.field = value;`（直接赋值）或 `ptr.field = value;`（指针自动解引用后赋值）

### Q: 如何定义结构体方法？
A: 在结构体内部定义，或使用外部方法块 `StructName { fn method(self: &Self) ... }`

### Q: 如何实现接口？
A: 在结构体定义时声明：`struct MyStruct : InterfaceName { ... }`

### Q: 切片和数组的区别？
A: 数组是固定长度的值类型 `[T: N]`，切片是动态长度的引用类型 `&[T]`

### Q: 如何捕获错误？
A: 使用 `catch` 后缀运算符：`value catch |err| { ... }`

### Q: `try` 关键字的作用？
A: `try` 用于错误传播和整数溢出检查，是一元运算符

### Q: 如何定义枚举？
A: `enum Color { Red, Green, Blue }` 或 `enum Status : u16 { Ok = 200 }`

### Q: 泛型语法是什么？
A: 使用尖括号 `<T>`，约束紧邻参数 `<T: Ord>`，多约束连接 `<T: Ord + Clone + Default>`
   - 函数：`fn max<T: Ord>(a: T, b: T) T { ... }`
   - 结构体：`struct Vec<T: Default> { ... }`
   - 接口：`interface Iterator<T> { ... }`
   - 使用：`Vec<i32>`, `Iterator<String>`

---

## 十六、完整示例

```uya
// 接口定义
interface IWriter {
    fn write(self: &Self, buf: *byte, len: i32) i32;
}

// 结构体实现接口
struct File : IWriter {
    fd: i32,
    
    fn write(self: &Self, buf: *byte, len: i32) i32 {
        // 实现写入逻辑
        return len;
    }
    
    fn drop(self: &Self) void {
        // 清理资源
    }
}

// 错误定义
error FileNotFound;

// 函数定义
fn open_file(path: *byte) !File {
    // 可能失败的操作
    if not_found {
        return error.FileNotFound;
    }
    return File{ fd: 1 };
}

// 使用
fn main() i32 {
    const file = try open_file("test.txt");
    defer file.drop();
    
    const data = "Hello";
    file.write(data, 5);
    
    return 0;
}
```

---

## 十七、下一步学习

- **完整语法**：查看 [grammar_formal.md](./grammar_formal.md)（完整BNF定义）
- **语言规范**：查看 [uya.md](./uya.md)（完整语义说明）
- **示例代码**：查看 `/examples` 目录
- **编译器实现**：查看 `/compiler` 目录

---

## 参考

- [uya.md](./uya.md) - 完整语言规范
- [grammar_formal.md](./grammar_formal.md) - 正式BNF语法规范
- [comparison.md](./comparison.md) - 与其他语言的对比

