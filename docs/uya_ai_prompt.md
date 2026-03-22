# Uya 语言完整语法 AI 提示词

## 核心特性

Uya 是系统编程语言，零GC、默认高级安全、编译期证明（本函数内）。

**设计哲学**：坚如磐石 - 程序员提供证明，编译器在当前函数内验证证明，运行时绝对安全。常量错误→编译错误，变量证明失败→编译错误并给出修改建议。

## 关键字

> **权威来源**：完整词法与语义以 `docs/uya.md`、`docs/grammar_formal.md` 为准；下列便于 AI 速查。

```
enum struct const var fn return extern true false if else while for break continue
match defer errdefer try catch error null interface atomic union
export use type mc test as
```

**内置函数**（以 `@` 开头，无需 `use`；识别名与自举编译器 `src/lexer.uya` 一致）：
- 类型/元数据：`@size_of`、`@align_of`、`@len`、`@max`、`@min`
- 源代码位置：`@src_name`、`@src_path`、`@src_line`、`@src_col`、`@func_name`
- 可变参数：`@params`、`@va_start`、`@va_end`、`@va_arg`、`@va_copy`
- 异步：`@async_fn`（函数属性）、`@await`（挂起点）
- 裸函数：`@naked_fn`（无 prologue/epilogue）
- 宏编译期：`@mc_eval`、`@mc_type`、`@mc_ast`、`@mc_code`、`@mc_error`、`@mc_get_env`、`@mc_source`（将表达式序列化为源码字符串，宏内）
- 系统调用：`@syscall(nr, arg1, ..., arg6)`
- 指针：`@ptr_from_usize`、`@usize_from_ptr`
- 错误：`@error_id(expr)` — 从错误值取数值 ID（`u32`）
- 调试：`@print`、`@println`（支持 **`byte`/`u8`/`i8`** 的 **`&[T]`**、**`[T:N]`**、**`*byte`** 及 **`"..."`**；**`[byte:N]`** / **`&[byte]`** 按 **`%s`** 打印，缓冲区须以 **`\\0`** 结尾，与 C 一致；详见 **`docs/builtin_functions.md`**）
- 内联汇编：`@asm { ... }`、`@asm_target()`
- SIMD：`@vector(T, N)`、`@mask(N)`，以及 `@vector.splat(x)`、`@vector.load(ptr)`、`@vector.store(ptr, v)`、`@vector.select(m, a, b)`、`@vector.reduce_add(v)`、`@vector.any(m)`、`@vector.all(m)` 等（详见规范 §16 / `docs/builtin_functions.md`）

## 类型系统

| 类型 | 大小/对齐 | 说明 |
|------|----------|------|
| `i8` `i16` `i32` `i64` | 1/2/4/8 B | 有符号整数，对齐=大小 |
| `u8` `u16` `u32` `u64` | 1/2/4/8 B | 无符号整数，对齐=大小 |
| `usize` | 4/8 B | 平台相关，32位=4B，64位=8B |
| `f32` `f64` | 4/8 B | 浮点数，对齐=大小 |
| `bool` | 1 B | 布尔值，对齐1B |
| `byte` | 1 B | 无符号字节，对齐1B |
| `void` | 0 B | 仅用于函数返回类型 |
| `*byte` | 4/8 B | FFI指针类型，C字符串指针 |
| `*const byte` | 4/8 B | FFI只读指针类型（0.42新增），只读C字符串指针 |
| `&T` | 4/8 B（平台相关） | 可变指针，无lifetime符号；32位平台=4B，64位平台=8B |
| `&const T` | 4/8 B（平台相关） | 只读指针（0.42新增），无lifetime符号；32位平台=4B，64位平台=8B |
| `&void` | 4/8 B（平台相关） | 通用指针类型，可转换为任何指针类型（`&void` → `&T`）；32位平台=4B，64位平台=8B |
| `&const void` | 4/8 B（平台相关） | 通用只读指针类型（0.42新增），可转换为任何只读指针类型；32位平台=4B，64位平台=8B |
| `&atomic T` | 4/8 B（平台相关） | 原子指针；32位平台=4B，64位平台=8B |
| `atomic T` | sizeof(T) | 原子类型 |
| `[T: N]` | N·sizeof(T) | 固定数组，N为编译期常量 |
| `[[T: N]: M]` | M·N·sizeof(T) | 多维数组，行优先存储 |
| `&[T]` | 8/16 B（平台相关） | 切片引用（动态长度），指针(4/8B) + 长度(4/8B)；32位平台=8B，64位平台=16B；**0.49.41**：可由 **`&"text"[start:len]`** 得到 **`&[byte]`**（逻辑基底长度为可见字符数+1，含 **`\\0`**） |
| `&[T: N]` | 8/16 B（平台相关） | 切片引用（已知长度），指针(4/8B) + 长度(4/8B)；32位平台=8B，64位平台=16B |
| `struct S { }` | 字段顺序布局 | 对齐=最大字段对齐，C内存布局 |
| `union U { ... }` | 最大变体大小 | 对齐=最大变体对齐，编译期标签跟踪，与C union兼容 |
| `interface I { }` | 8/16 B（平台相关） | vtable指针(4/8B) + 数据指针(4/8B)；32位平台=8B，64位平台=16B |
| `enum E { }` | sizeof(底层类型) | 枚举，默认底层i32 |
| `(T1, T2, ...)` | 字段顺序布局 | 元组类型，对齐=最大字段对齐 |
| `fn(...) type` | 4/8 B（平台相关） | 函数指针类型，用于FFI回调 |
| `!T` | max(sizeof(T), sizeof(错误标记)) | 错误联合类型，T\|Error |
| `@vector(T, N)` | N·sizeof(T) | SIMD 向量类型，元素 `T`，通道 `N` |
| `@mask(N)` | N 通道 | SIMD 掩码类型，向量比较结果，不隐式转 `bool` |

**错误联合类型 `!T` 内存布局**：大小 = `max(sizeof(T), 4)` 字节（错误标记占 4 字节），对齐 = `max(alignof(T), 4)` 字节  
- 无隐式转换，类型必须完全一致

**SIMD 最小用法**：
```uya
type Vec4f32 = @vector(f32, 4);
const zeros: @vector(i32, 4) = @vector.splat(0);
const lt: @mask(4) = a < b;
if @vector.any(lt) { /* ... */ }
```

## 基本语法

### 变量声明
```uya
const name: Type = value;  // 不可变变量
var name: Type = value;    // 可变变量
```

**重要规则**：
- 必须显式类型注解，不支持类型推断
- `const` 为编译期常量，可作为数组大小
- 忽略标识符 `_`：`_ = process();` 显式忽略返回值

### 字面量

**数值字面量**：
```uya
// 整数字面量（默认类型 i32）
const dec: i32 = 123;             // 十进制
const hex: i32 = 0xFF;            // 十六进制（0x 或 0X 前缀）
const oct: i32 = 0o755;           // 八进制（0o 或 0O 前缀）
const bin: i32 = 0b1010;          // 二进制（0b 或 0B 前缀）
const big: i32 = 1_000_000;       // 下划线分隔符提高可读性
const hex2: i32 = 0xDEAD_BEEF;    // 十六进制也支持下划线

// 带整型类型后缀的字面量
const s8 : i8    = 100i8;
const u8v: u8    = 255u8;
const i32v: i32  = 100000i32;
const uv : u32   = 0xFFu32;
const usz: usize = 42usize;

// 浮点字面量（默认类型 f64，仅十进制）
const pi : f64 = 3.141_592_653;   // 支持下划线分隔符
const sci: f64 = 1.0e-10;         // 支持科学计数法

// 带浮点类型后缀的字面量
const f32v: f32 = 1.5f32;
const f64v: f64 = 3.14f64;
```

**下划线规则**：
- 可出现在任意两个数字之间：`1_000`、`0xFF_00_AA`
- 不能出现在开头、结尾或连续出现：`_123`、`123_`、`1__000` 均非法
- 不能紧跟在进制前缀之后：`0x_FF` 非法，`0xFF_00` 合法

**类型后缀规则**：
- 整数后缀：`i8`、`i16`、`i32`、`i64`、`u8`、`u16`、`u32`、`u64`、`usize`
- 浮点后缀：`f32`、`f64`
- 语法：`<数字><后缀>`，包括带进制前缀/指数的形式（如 `0xFFu8`、`1.0e10f64`）
- 无后缀时：整数默认 `i32`，浮点默认 `f64`（除非上下文强制其他类型）

**布尔字面量**：`true`、`false`，类型为 `bool`

**空指针字面量**：`null`，类型为 `*byte`
- ✅ 用于与 `*byte` 类型比较：`if ptr == null { ... }`
- ✅ 可以作为 FFI 函数参数（如果函数接受 `*byte`）：`some_function(null);`
- ❌ 不支持将 `null` 赋值给 `*byte` 类型的变量（未来可能支持）

**字符字面量**：`'a'`, `'x'`, `'\n'`, `'\t'`, `'\r'` 等（0.43 新增；含 **`\\r`** → CR(13)）
- 类型为 `byte`（无符号 8 位整数），**可赋值给 `byte` 类型**
- 示例：`const c: byte = 'A';` → 值为 65

**数组字面量**：
```uya
const arr: [i32: 3] = [1, 2, 3];       // 列表式
const zeros: [i32: 100] = [0: 100];    // 重复式（value 重复 N 次）
var buf: [i32: 100] = [];              // 空数组（未初始化，仅当类型已明确时可用）
```

### 函数声明
```uya
// 内部函数（生成的 C 代码添加 static）
fn name(param1: Type1, param2: Type2) ReturnType {
    statements
    return value;
}

// 导出函数（生成的 C 代码不添加 static）
export fn public_function(param1: Type1, param2: Type2) ReturnType {
    statements
    return value;
}
// 生成的 C 函数名：模块前缀_函数名（如 std_io_public_function）

// 外部 C 函数声明
extern fn c_function(param: *byte) i32;

// 外部 C 函数声明（Uya 实现，以裸函数名导出）
extern fn my_wrapper(param: *byte) i32 {
    // Uya 实现代码
    return 0;
}
// 生成的 C 代码：int my_wrapper(char *param) { ... }
// 注意：不带 uya_ 前缀

// 导出外部 C 函数声明（无函数体）→ 链接到 C 标准库
export extern fn malloc(size: usize) *void;
// 不生成代码，链接到 C 标准库的 malloc

// 导出外部 C 函数实现（有函数体）→ Uya 实现，以裸函数名导出
export extern fn strcmp(s1: &const byte, s2: &const byte) i32 {
    // Uya 实现代码
    return 0;
}
// 生成的 C 代码：int strcmp(const char *s1, const char *s2) { ... }
// 注意：不带 uya_ 前缀

// 模块前缀规则（生成 C 代码时）
// - fn（私有）：uya_函数名（如 uya_foo）
// - export fn：模块前缀_函数名（如 std_io_fopen, main_my_func）
// - extern fn：裸函数名，无前缀（如 malloc, my_wrapper）
// 模块前缀提取：模块路径的 . 替换为 _（std.io → std_io, main → main）

// void函数
fn void_func() void {
    // 可省略return
}

// 错误联合类型
fn may_fail() !i32 {
    if condition {
        return error.ErrorName;  // 返回错误
    }
    return 42;  // 返回正常值
}

// 泛型函数
fn max<T: Ord>(a: T, b: T) T {
    if a > b { return a; }
    return b;
}

// 多约束泛型
fn clone_and_compare<T: Clone + Ord>(a: T, b: T) bool {
    const cloned = a.clone();
    return cloned > b;
}

// 只读指针参数（0.42 新增）
export fn strcmp(s1: &const byte, s2: &const byte) i32 {
    // &const T 表示只读指针，C 代码生成：const char *
}
```

**程序入口（0.46 应用入口规范化）**：
```uya
// 应用入口（生成 main_main）
export fn main() i32 { ... }
export fn main() !i32 { ... }  // 推荐

// C 入口（生成 main，供 C 调用）
export extern fn main(argc: i32, argv: &&byte) i32 { ... }

// 旧架构兼容（生成 uya_main）
fn main() i32 { ... }
```

**说明**：
- `export fn main()` 生成 `main_main()`，由 `std.runtime.entry`（`entry.uya`）提供 C `main` 并调用 `main_main()`；**`bin/uya` 等会自动加入该文件，用户源码无需 `use std.runtime.entry`**
- `export extern fn main(argc, argv)` 生成标准 C `main()` 签名
- `fn main()` 生成 `uya_main()`，向后兼容

### 联合体
```uya
// 联合体定义（Tagged Union，类型安全）
union IntOrFloat {
    i: i32,
    f: f64
}

// 创建：UnionName.variant(expr)
const v = IntOrFloat.i(42);

// 访问：必须 match 处理所有变体
match v {
    .i(x) => printf("%d\n", x),
    .f(x) => printf("%f\n", x)
}

// C 兼容联合体（extern union，无标签）
// 重要：只有 extern union 才能与 C 语言完全兼容
extern union CData {
    bytes: [u8: 8],
    as_u64: u64,
    as_f64: f64
}
// extern union 特性：
// - 内存布局与 C union 完全一致
// - 不支持 match 表达式（无运行时标签）
// - 不支持方法定义
// - 用于 C FFI 互操作
```

**联合体类型对比**：

| 特性 | `union` | `extern union` |
|------|---------|----------------|
| 内存布局 | `struct { _tag, u }` | `union` |
| 标签开销 | 4 字节 + 填充 | 无 |
| C 兼容性 | 需包装结构体 | **完全兼容** |
| match 支持 | ✅ | ❌ |
| 方法支持 | ✅ | ❌ |
| 引用类型变体 | ✅ 支持 | ✅ 支持 |

**变体类型支持**：
- 基础类型（`i32`、`f64`、`bool` 等）✅
- 结构体类型 ✅
- 引用类型（`&T`）✅ - Tagged Union 每次赋值完全覆盖，无悬垂引用风险
- FFI 指针（`*T`）✅
- 数组、切片 ✅

**详细文档**：`docs/union_memory_layout.md` - 内存布局、对齐规则、C 互操作指南

### 结构体
```uya
// 基本结构体
struct Point {
    x: f32,
    y: f32
}

// 声明接口
struct File : IWriter {
    fd: i32,
    fn write(self: &Self, buf: *byte, len: i32) i32 { ... }
}

// 外部方法定义（方式2）
File {
    fn read(self: &Self, buf: *byte, len: i32) !i32 { ... }
}

// 泛型结构体
struct Vec<T: Default> {
    data: &T,
    len: i32,
    cap: i32
}

// 使用泛型结构体
const vec: Vec<i32> = Vec<i32>{ data: ..., len: 0, cap: 0 };

// 泛型方法（0.47 新增）
struct Container<T> {
    value: T,
    
    // 泛型方法：将 T 转换为 U（独立类型参数）
    fn as_type<U>(self: &Self) U {
        return self.value as U;
    }
    
    // 非泛型方法
    fn get(self: &Self) T {
        return self.value;
    }
}

// 调用泛型方法
const c: Container<i32> = Container<i32>{ value: 42 };
const v: i64 = c.as_type<i64>();  // 显式指定 U = i64

// 结构体字面量
const p: Point = Point{ x: 1.0, y: 2.0 };

// 字段访问
const x: f32 = p.x;  // 直接访问
var ptr: &Point = &p;
const y: f32 = ptr.y;  // 指针自动解引用（等价于 (*ptr).y）

// 字段赋值
p.x = 10.0;  // 直接赋值
ptr.y = 20.0;  // 指针自动解引用后赋值（等价于 (*ptr).y = 20.0）
```

**重要规则**：
- 所有结构体使用C内存布局，100% C兼容
- 可以有方法、drop、实现接口，同时保持C兼容
- `self` 参数必须为 `&Self` 或 `&StructName`（指针）
- **指针自动解引用**：`ptr.field` 等价于 `(*ptr).field`（当 `ptr` 是指向结构体的指针时）
- **字段赋值**：支持 `obj.field = value` 和 `ptr.field = value`（指针自动解引用）

### 接口
```uya
interface IWriter {
    fn write(self: &Self, buf: *byte, len: i32) i32;
}

// 泛型接口
interface Iterator<T> {
    fn next(self: &Self) Option<T>;
}

// 多约束泛型接口
interface Cloneable<T: Clone + Default> {
    fn clone(self: &Self) T;
}

// 结构体实现接口
struct Console : IWriter {
    fd: i32,
    fn write(self: &Self, buf: *byte, len: i32) i32 {
        extern write(fd: i32, buf: *void, count: i32) i32;
        return write(self.fd, buf, len);
    }
}

// 使用接口
fn use_writer(w: IWriter) void {
    w.write(&buffer[0], 10);  // 动态派发
}

// 使用泛型接口
fn use_iterator<T>(iter: Iterator<T>) void {
    // 使用迭代器
}
```

**重要规则**：
- 接口值16字节（vtable指针+数据指针）
- 编译期生成vtable，零运行时注册
- 生命周期：接口值不能逃逸底层数据生命周期

### 枚举
```uya
// 基本枚举（默认底层类型i32）
enum Color {
    RED,
    GREEN,
    BLUE
}

// 显式赋值
enum HttpStatus {
    OK = 200,
    NOT_FOUND = 404,
    SERVER_ERROR = 500
}

// 指定底层类型
enum SmallEnum : u8 {
    A = 1,
    B = 2
}

// 使用
const c: Color = Color.RED;
const status: HttpStatus = HttpStatus.OK;
```

**规则**：
- 默认底层类型为`i32`
- 支持显式指定底层类型（`u8`, `u16`, `u32`, `i8`, `i16`, `i32`, `i64`）
- 枚举变体可以显式赋值
- 类型安全：枚举值只能与相同枚举类型比较
- 与C枚举完全兼容

### 元组
```uya
// 元组类型
type Point = (i32, i32);
const p: (i32, i32) = (10, 20);

// 字段访问（使用.0, .1, .2等索引）
const x: i32 = p.0;  // 访问第一个元素
const y: i32 = p.1;  // 访问第二个元素

// 解构赋值
const (x, y) = p;
const (x, _, z) = get_tuple();  // 使用_忽略中间元素
```

**规则**：
- 字段访问使用数字索引（从0开始）
- 支持解构赋值
- 对齐规则与结构体相同（对齐=最大字段对齐值）
- 编译期边界检查：访问越界立即编译错误

### 类型别名
```uya
// 基础类型别名
type UserId = i32;
type Distance = f64;

// 元组类型别名
type Point = (i32, i32);

// 函数指针类型别名
type ComparFunc = fn(*void, *void) i32;

// 错误联合类型别名
type FileResult = !i32;
```

### 数组
```uya
// 数组声明
const arr: [i32: 10] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const zeros: [i32: 10] = [0: 10];  // 重复初始化

// 未初始化数组（空数组字面量）
var buf: [f32: 64] = [];  // 必须在使用前初始化
// 注意：空数组字面量 [] 仅当变量类型已明确时可用，表示未初始化
// len(buf) 返回数组声明时的大小（64），而不是 0

// 多维数组
const matrix: [[i32: 4]: 3] = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12]
];

// 数组访问（需要边界检查证明）
if i >= 0 && i < 10 {
    const value: i32 = arr[i];
}
```

**切片语法**：
```uya
const slice: &[i32] = &arr[2:5];           // 动态长度切片
const exact: &[i32: 3] = &arr[2:3];        // 已知长度切片
const tail: &[i32] = &arr[-3:3];           // 负数索引，从倒数第3个开始

// 从数组字面量直接创建切片（0.48 新增）
const slice1: &[i32] = &[1, 2, 3];         // 从列表创建
const slice2: &[i32] = &[0: 10];           // 从重复值创建

// 字符串字面量后缀下标/切片（0.49.41）：逻辑长度为「可见字符数+1」（含末尾 \0）
const sub: &[byte] = &"hello"[0:3];       // 与等长 [byte:N] 上 &buf[0:3] 一致
```

### 控制流

**if语句**：
```uya
if condition {
    statements
} else {
    statements
}

// else if
if c1 {
} else if c2 {
} else {
}
```

**while循环**：
```uya
while condition {
    statements
    break;      // 跳出循环
    continue;   // 继续下一次迭代
}
```

**for循环**：
```uya
// 可迭代对象（值迭代，只读）
for obj |v| {
    // v是元素值
}

// 可迭代对象（引用迭代，可修改）
for obj |&v| {
    *v = *v * 2;  // 修改元素
}

// 索引迭代
for obj |i| {
    // i是索引，类型usize
}

// 整数范围
for 0..10 |i| {  // [0, 10)，左闭右开
    // i从0到9
}

for 5.. |i| {    // 从5开始的无限范围
    // 由迭代器结束条件终止
}

// 丢弃元素
for obj { }      // 只执行循环体
for 0..10 { }    // 只执行10次
```

**match表达式**：
```uya
// 作为表达式
const result: i32 = match value {
    1 => 10,
    2 => 20,
    else => 0
};

// 作为语句
match status {
    200 => process_success(),
    error.FileNotFound => handle_error(),
    else => handle_default()
};

// 省略分号（0.48 新增）：所有分支都是 block 时可省略分号
match status {
    200 => { process_success(); },
    404 => { handle_error(); },
    else => { handle_default(); }
}
// 当 match 的所有分支都是 block（用 {} 包裹），且后面跟着 } 或语句开始关键字时，可省略分号

// 结构体解构
match point {
    Point{ x: 0, y: 0 } => handle_origin(),
    Point{ x, y } => process(x, y)
};

// 枚举匹配
match color {
    Color.RED => handle_red(),
    Color.GREEN => handle_green(),
    Color.BLUE => handle_blue()
};

// 错误类型匹配
match result {
    error.DivisionByZero => handle_div_zero(),
    error.Overflow => handle_overflow(),
    value => use_value(value)
};
```

### 错误处理

**错误类型**：
```uya
// 预定义错误（可选）
error DivisionByZero;
error FileNotFound;

// 运行时错误（无需预定义）
return error.RuntimeError;

// 使用
if err == error.DivisionByZero { ... }
```

**error_id 稳定性**：`error_id = hash(error_name)`，相同错误名在任意编译中映射到相同 `error_id`；hash 冲突时编译器报错并提示冲突名称。

**try关键字**：
```uya
// 错误传播
const result: i32 = try divide(10, 2);  // 自动传播错误

// 溢出检查
const sum: i32 = try a + b;   // 溢出时返回error.Overflow
const diff: i32 = try a - b;  // 溢出检查
const prod: i32 = try a * b;  // 溢出检查
```

**catch语法**：
```uya
// 捕获错误并返回值
const result: i32 = divide(10, 0) catch |err| {
    if err == error.DivisionByZero {
        return 0;  // 返回默认值
    }
    return -1;
};

// 捕获所有错误（不绑定变量）
const result: i32 = divide(10, 0) catch {
    return 0;  // 默认值
};

// catch中使用return提前返回函数
const result: i32 = divide(10, 0) catch {
    return error;  // 直接返回函数，退出函数
};
```

### defer和errdefer

```uya
fn example() !void {
    defer {
        cleanup();  // 作用域结束时执行（正常或错误返回）
    }
    
    errdefer {
        rollback();  // 仅在错误返回时执行
    }
    
    // 执行顺序：正常返回时 defer → drop
    // 错误返回时 errdefer → defer → drop
}
```

**块内禁止**：`return`、`break`、`continue` 等控制流语句。允许：表达式、赋值、函数调用、语句块。替代：用变量记录状态，在 defer/errdefer 外处理控制流。

### test 语句（测试语法）

```uya
// 单个测试用例
test "basic_addition" {
    const result: i32 = add(1, 2);
    try assert_eq_i32(result, 3, "1 + 2 should equal 3");
}

// 多个测试用例（每个 test 是独立的测试函数）
test "addition_with_negative" {
    const result: i32 = add(-1, 1);
    try assert_eq_i32(result, 0, "-1 + 1 should equal 0");
}

// 测试文件组织：tests/test_feature.uya
// 运行：make tests（自动发现并运行所有 test 语句）
```

**规则**：
- `test "描述性名称" { body }` 定义测试用例
- 测试体返回 `!void`，支持 `try` 表达式
- 测试失败时打印错误信息并继续执行其他测试
- 测试文件不使用 `main` 函数，使用 `test "name" {}` 风格

### 运算符

**优先级表**（从高到低）：
1. `()` `.` `[]` `[start:len]` - 调用、字段、下标、切片（含字符串字面量后缀 **`"…"[i]`** / **`"…"[start:len]`**，**0.49.41**）
2. `-` `!` `~` - 一元运算符
3. `*` `/` `%` `*|` `*%` - 乘除模、饱和乘法、包装乘法
4. `+` `-` `+|` `-|` `+%` `-%` - 加减、饱和运算、包装运算
5. `<<` `>>` - 移位
6. `<` `>` `<=` `>=` - 比较
7. `==` `!=` - 相等性
8. `&` - 按位与
9. `^` - 按位异或
10. `|` - 按位或
11. `&&` - 逻辑与
12. `||` - 逻辑或
13. `as` `as!` - 安全转换 / 强转（强转结果为 `!T`，常配合 `try`）
14. `=`、`+=`、`-=`、`*=`、`/=`、`%=`、`&=`、`|=`、`^=`、`<<=`、`>>=` - 赋值与复合赋值（必须使用完整形式，见 `docs/uya.md` 第 10 章）

**特殊运算符**：
- **饱和运算符**：`+|` `-|` `*|` - 溢出时返回极值
- **包装运算符**：`+%` `-%` `*%` - 溢出时包装（模运算）
- **try运算符**：`try expr` - 错误传播或溢出检查

**重要规则**：
- 无隐式转换，类型必须完全一致（少数安全放宽见规范，如部分指针协变）
- 简单赋值 `=` 与复合赋值仅作用于可变左值（通常为 `var`；`atomic T` 上的读/写/复合赋值由编译器生成原子操作）
- 不支持自增/自减运算符 `++`、`--`
- 不支持三元运算符 `?:`，使用 if-else

### 类型转换

```uya
// 安全转换（as）- 仅无精度损失
const f: f64 = i as f64;        // ✅ i32→f64无损失
const i: i32 = f as i32;        // ❌ 编译错误，可能损失精度

// 强转（as!）- 返回错误联合类型
const i: i32 = try f as! i32;   // ✅ 可能损失精度，返回!i32

// 指针类型转换（FFI调用）
extern write(fd: i32, buf: *byte, count: i32) i32;
extern strlen(s: *const byte) usize;
var buffer: [byte: 100] = [];
const result: i32 = write(1, &buffer[0] as *byte, 100);  // ✅ &T as *T

// 只读指针转换（0.42 新增）
const str: &const byte = "hello";
const len = strlen(str as *const byte);  // ✅ &const T as *const T
```

**指针转换规则**（0.42 更新）：
- ✅ `&T` ↔ `*T`：同类型指针可通过 `as` 互相转换
- ✅ `&const T` ↔ `*const T`：同类型只读指针可通过 `as` 互相转换（0.42 新增）
- ✅ `&T` → `&const T`：可变指针隐式转换为只读指针（放宽约束，安全，无需 `as`）
- ✅ `&T` → `*const T`：可变指针转换为 FFI 只读指针（放宽约束，安全，需要 `as`）
- ✅ `&void ↔ &T`：通用指针与具体指针类型之间的转换
  - `&void as &T`：通用指针转换为具体指针类型（类型擦除恢复）
  - `&T as &void`：具体指针转换为通用指针类型（类型擦除）
  - 示例：`var ptr: &void = &buffer as &void; var byte_ptr: &byte = ptr as &byte;`
- ✅ `&const void ↔ &const T`：通用只读指针与具体只读指针类型之间的转换（0.42 新增）
  - `&const void as &const T`：通用只读指针转换为具体只读指针类型
  - `&const T as &const void`：具体只读指针转换为通用只读指针类型

### 模块系统

```uya
// 导出
export fn helper() i32 { return 42; }
export struct Point { x: f32, y: f32 }

// 导入
use std.io;                    // 导入整个模块
use std.io.read_file;          // 导入特定项
use std.io as io;              // 使用别名
// 不支持通配符：use std.io.*; ❌

// 使用
std.io.read_file(...);         // 模块前缀
read_file(...);                // 直接使用（导入特定项后）
io.read_file(...);             // 别名前缀
```

**模块规则**：
- 每个目录自动成为一个模块
- 项目根目录（包含main的目录）是`main`模块
- 路径映射：`std/io/` → `std.io`
- **同目录文件合并**：同一目录下的所有 `.uya` 文件都属于同一个模块，模块路径由目录路径决定，不包含文件名（如 `std/io/file.uya` 和 `std/io/stream.uya` 都属于 `std.io` 模块）
- 子目录可引用 `main` 模块，但编译器检测循环依赖并报错
- 所有结构体使用C内存布局，可直接互操作

### 可变参数

- **声明**：沿用 C 的 `...` 语法：`fn printf(fmt: *byte, ...) i32;`
- **@params**：内置变量，函数体内包含所有参数（固定+可变）的元组视图，可用 `.0`/`.1`、遍历、解构

### 异步编程

- 函数属性 `@async_fn` 标记异步函数，必须返回 `!Future<T>`
- `@await` 在 `@async_fn` 函数内等待异步操作，配合 `try` 处理错误

### FFI（外部C函数）

```uya
// 声明外部C函数
extern printf(fmt: *byte, ...) i32;
extern malloc(size: usize) *void;

// 调用
printf("Hello\n");
const ptr: *void = malloc(100);

// 导出函数给C
extern fn compare(a: *void, b: *void) i32 {
    // Uya代码
    return 0;
}

// 链接到 libc（0.43 新增）
extern "libc" fn strlen(s: *const byte) usize;
// 不生成代码，直接链接到 C 标准库的 strlen
// byte 映射规则：在 extern "libc" 中，byte 映射为 C 的 char 类型

// 用 Uya 实现 C 标准库函数（0.43 新增）
export extern "libc" fn my_strlen(s: *const byte) usize {
    if s == null { return 0; }
    var len: usize = 0;
    while s[len] != 0 { len = len + 1; }
    return len;
}
// 生成的 C 代码：size_t my_strlen(const char *s) { ... }
// 注意：裸函数名，无模块前缀
```

**extern 变量支持**（0.43 新增）：
```uya
// 导入 C 全局变量
extern const errno: i32;           // 只读：extern const int errno;
extern var optind: i32;            // 可变：extern int optind;
extern const stdout: *void;        // C: extern FILE *stdout;

// 导出 Uya 变量给 C
export const VERSION: &byte = "1.0.0";  // C: const char *VERSION = "1.0.0";
export var debug_mode: i32 = 0;         // C: int debug_mode = 0;

// 链接到 C 库定义的变量
export extern const ENOENT: i32;        // 不生成定义，链接到 C 库
```

**extern 变量语法规则**：

| 语法 | 用途 | C 代码生成 |
|------|------|-----------|
| `extern const name: type;` | 导入只读 C 变量 | `extern const type name;` |
| `extern var name: type;` | 导入可变 C 变量 | `extern type name;` |
| `export const name: type = val;` | 导出只读常量 | `const type name = val;` |
| `export var name: type = val;` | 导出可变变量 | `type name = val;` |
| `export extern const name: type;` | 链接到 C 库定义 | 不生成，链接到 C 库 |

**FFI指针类型 `*T`**：
- 仅用于FFI函数声明/调用
- 支持所有C兼容类型：`*i8` `*i16` `*i32` `*i64` `*u8` `*u16` `*u32` `*u64` `*f32` `*f64` `*bool` `*byte` `*void` `*CStruct`
- 支持下标访问 `ptr[i]`，但必须提供长度约束证明
- 除用字符串字面量初始化 `*byte`（如 `const s: *byte = "hello";`）外，不能用于普通变量声明

**Uya指针传递给FFI函数**：
- ✅ `&T as *T`：Uya普通指针可以通过 `as` 显式转换为FFI指针类型（安全转换，无精度损失）
- 仅在FFI函数调用时使用，符合"显式控制"设计哲学
- 示例：`extern write(fd: i32, buf: *byte, count: i32) i32;` 调用时使用 `write(1, &buffer[0] as *byte, 100);`
- 编译期检查，无运行时开销

**函数指针类型**：
```uya
// 函数指针类型
type ComparFunc = fn(*void, *void) i32;

// 声明需要函数指针的C函数
extern qsort(base: *void, nmemb: usize, size: usize, compar: ComparFunc) void;

// 导出函数给C（可以作为函数指针传递）
extern fn compare(a: *void, b: *void) i32 {
    // Uya代码
    return 0;
}

// 使用
qsort(&arr[0], 10, 4, &compare);  // 传递函数指针
```

### 原子操作

```uya
struct Counter {
    value: atomic i32
}

fn increment(counter: *Counter) void {
    counter.value += 1;        // 自动原子fetch_add
    const v: i32 = counter.value;  // 自动原子load
    counter.value = 10;        // 自动原子store
}
```

**规则**：
- `atomic T` 类型的所有读写操作自动生成原子指令
- 零运行时锁，直接硬件原子指令
- 默认使用sequentially consistent内存序

### 内存安全规则

**编译期证明机制**：
- **常量错误**：编译期常量直接检查，溢出/越界立即编译错误
- **变量证明失败**：编译器无法证明安全时，报编译错误并给出修改建议

**必须证明安全的场景**：
1. **数组越界**：常量索引越界→编译错误；变量索引→证明`i >= 0 && i < len`，失败→编译错误并给出建议
2. **空指针解引用**：证明`ptr != null`或前序有检查，失败→编译错误并给出建议
3. **使用未初始化**：证明「首次使用前已赋值」，失败→编译错误并给出建议
4. **整数溢出**：常量溢出→编译错误；变量→显式检查或编译器证明，失败→编译错误并给出建议
5. **除零错误**：常量除零→编译错误；变量→证明`y != 0`，失败→编译错误并给出建议

**证明范围**：仅限当前函数内，跨函数调用需显式处理返回值

**证明场景分类**：
- **需要显式 `if` 判断**：变量数组索引、指针解引用、变量除法、变量运算溢出
- **不需要显式 `if` 判断**：常量数组索引（编译期直接验证）、循环变量范围推导（`for 0..@len(arr) |i|`）、饱和运算符（`+|`）、包装运算符（`+%`）、`try` 关键字

**编译器优化规则**：
- 证明条件为真 → 消除 `if`，直接执行 then 块
- 证明条件为假 → 消除 then 块（死代码）
- 无法证明 → 保留 `if` 运行时检查

### RAII和drop

```uya
// 用户自定义 drop，只能在结构体内部或方法块中定义
File {
    fn drop(self: File) void {
        extern close(fd: i32) i32;
        close(self.fd);
    }
}

// 自动调用：离开作用域时按字段逆序调用 drop
```

**规则**：
- 离开作用域时自动调用drop
- 递归drop：先drop字段，再drop外层结构体
- 数组元素按索引逆序drop

### 移动语义

**规则**：
- 结构体赋值时转移所有权（移动），基本类型使用值语义（复制）
- 移动后变量不能再次使用
- 存在活跃指针时禁止移动
- 移动不会调用源对象的drop，只有目标对象离开作用域时才调用drop

### 字符串

**字符串字面量**：
```uya
// 普通字符串字面量（类型 *byte；语义上自动带 \0 结尾）
extern printf(fmt: *byte, ...) i32;
printf("Hello\n");  // ✅ FFI 参数
// 支持转义：\n \t \r \\ \" \0；不支持 \xHH、\uXXXX（未来支持）

// 原始字符串字面量（无转义）
printf(`C:\Users\name`);
```

**字符串字面量的赋值与使用**（普通/原始均适用，自动带 `\0` 结尾）：
- ✅ 可赋值给 `[byte: N]`（当 可见字符数+1 ≤ N 时，按字节拷贝并以 `\0` 结尾）：`var buf: [byte: 8] = "hi";`
- ✅ 可赋值给 `&byte` 或 `*byte`：`const s: *byte = "hello";`
- ✅ 可作为 FFI 函数参数、与 `null` 比较
- ✅ **0.49.41**：可作**主表达式**接后缀，与数组字面量/标识符一致：**`"text"[i]`**（下标）、**`"text"[start:len]`**（切片操作数）；**`&"text"[start:len]`** 类型为 **`&[byte]`**。常量边界检查以 **`strlen(字面量)+1`** 为逻辑长度。

**字符串插值**：
```uya
const x: u32 = 255;
const pi: f64 = 3.14159;

// 基本形式
const msg1: [i8: 64] = "x=${x}\n";

// 格式化形式（与C printf一致）
const msg2: [i8: 64] = "hex=${x:#06x}, pi=${pi:.2f}\n";
const msg3: [i8: 64] = "pi=${pi:.2e}\n";  // 科学计数法
```

**字符串插值规则**：
- 结果类型为`[i8: N]`（定长栈数组）
- 编译期计算缓冲区大小
- 格式说明符与 C printf 保持一致（libc 已实现 C99 格式：%a/%A、%zu/%zd、flags/width/precision 等）
- 零运行时解析开销，零堆分配

### 内置函数（以 @ 开头）

见上文"关键字"章节的内置函数列表。所有内置函数以 `@` 开头，无需导入，自动可用，编译期展开。

**@asm 内联汇编（0.72 新增）**：

`@asm` 是编译期内置函数，用于直接编写内联汇编代码，替代 C99 的内联汇编语法。它是构建高性能底层库、操作系统内核、编译器基础设施的关键工具。

**设计目标**：
- **类型安全**：编译期验证汇编代码的类型约束，防止未定义行为
- **跨平台支持**：抽象不同平台的汇编指令和调用约定，统一语法
- **零成本抽象**：编译期展开，零运行时开销
- **内存安全**：确保汇编操作不破坏 Uya 的内存安全保证

**基本语法**：
```uya
@asm {
    "instruction template" (input1, input2, ..., -> output1, output2, ...)
        clobbers = [reg1, reg2, ..., "memory"];
}
```

**语法元素**：

| 元素 | 说明 | 示例 |
|------|------|------|
| `instruction template` | 汇编指令模板 | `"add {a}, {b}"` |
| `{name}` | 占位符，引用输入/输出 | `{a}`, `{b}` |
| `input_exprs` | 输入表达式列表 | `a, b, c` |
| `output_exprs` | 输出表达式列表 | `-> result` |
| `clobbers` | 被修改的寄存器列表 | `clobbers = ["rax", "rcx"]` |
| `"memory"` | 声明修改内存 | `clobbers = ["memory"]` |

**输出变量声明规则**：
```uya
// ✅ 正确：输出变量在块外显式声明
var result: i32;
@asm {
    "add {a}, {b}" (a, b, -> result);
}

// ❌ 错误：不能在 -> 处隐式声明
@asm {
    "add {a}, {b}" (a, b -> var result: i32);  // 编译错误
}
```

**简单示例：两数相加**：
```uya
fn add_with_asm(a: i32, b: i32) i32 {
    var result: i32;
    @asm {
        "add {a}, {b}" (a, b, -> result);
    }
    return result;
}
```

**系统调用示例**：
```uya
fn syscall_write(fd: i32, buf: &const byte, count: i32) !i32 {
    const SYS_write: i64 = 1;
    var result: i64;  // 显式声明输出变量

    @asm {
        "mov rax, {nr}" (SYS_write, -> rax);
        "mov rdi, {fd}" (fd, -> rdi);
        "mov rsi, {buf}" (buf, -> rsi);
        "mov rdx, {count}" (count, -> rdx);
        "syscall" (rax, rdi, rsi, rdx, -> result);
    } clobbers = ["rcx", "r11", "memory"];
    
    if result < 0 { return error.SyscallFailed; }
    return result as! i32;  // 使用 as! 处理可能溢出的转换
}
```

**多条指令示例**：
```uya
fn complex_calc(a: i32, b: i32, c: i32) i32 {
    var temp: i32;
    var result: i32;
    
    @asm {
        "mov {temp}, {a}" (a, -> temp);
        "add {temp}, {b}" (temp, b, -> temp);
        "add {temp}, {c}" (temp, c, -> result);
    }
    
    return result;
}
```

**@asm 类型系统**：

**支持的类型**：
- **整数类型**：`i8`, `i16`, `i32`, `i64`, `u8`, `u16`, `u32`, `u64`, `usize`
- **指针类型**：`&T`（可变指针）、`&const T`（只读指针）、`&atomic T`（原子指针）

**不支持的类型**：
- `f32`, `f64`（浮点数，未来支持）
- `void`（空类型）
- 结构体类型
- 数组类型
- 切片类型
- FFI 指针 `*T`（必须转换为 Uya 指针）

**寄存器类型**：
```uya
// 通用寄存器（编译器自动分配）
type @asm_reg = opaque;

// 平台特定通用寄存器
type @asm_reg_x64 = opaque;    // x86-64 通用整数寄存器
type @asm_reg_x86 = opaque;    // x86 通用整数寄存器
type @asm_reg_arm64 = opaque;  // ARM64 通用整数寄存器
type @asm_reg_riscv = opaque;  // RISC-V 通用整数寄存器

// SIMD / 向量寄存器（依目标平台）
type @asm_reg_x64_xmm = opaque;
type @asm_reg_x64_ymm = opaque;
type @asm_reg_x64_zmm = opaque;
type @asm_reg_arm64_v = opaque;
type @asm_reg_riscv_v = opaque;
type @asm_reg_riscv_f = opaque;
type @asm_reg_riscv_d = opaque;

// 使用示例
fn auto_reg(a: i32, b: i32) i32 {
    var temp: @asm_reg;  // 编译器自动分配寄存器
    var result: i32;
    
    @asm {
        "mov {temp}, {a}" (a, -> temp);
        "add {temp}, {b}" (temp, b, -> result);
    }
    
    return result;
}
```

**内存操作类型**：
```uya
// 内存操作包装
@asm_mem<T>(ptr: &T) -> asm_mem;

// 使用示例
fn read_u32(ptr: &u32) u32 {
    var value: u32;
    @asm {
        "mov {value}, [{ptr}]" (@asm_mem(ptr), -> value);
    }
    return value;
}

fn write_u32(ptr: &u32, value: u32) void {
    @asm {
        "mov [{ptr}], {value}" (value, @asm_mem(ptr), -> _);
    }
}
```

**原子操作示例**：
```uya
fn atomic_fetch_add(ptr: &atomic i32, value: i32) i32 {
    var old: i32;
    @asm {
        "lock xadd {ptr}, {value}" (@asm_mem(ptr), value, -> old);
    }
    return old;
}

fn atomic_compare_exchange(ptr: &atomic i32, expected: i32, desired: i32) bool {
    var prev: i32;
    @asm {
        "lock cmpxchg [{ptr}], {desired}" (
            @asm_mem(ptr), desired, -> prev
        );
    }
    return prev == expected;
}
```

**平台支持与检测**：
```uya
// 平台类型枚举
enum @asm_target {
    x86_64_linux,
    x86_64_macos,
    x86_64_windows,
    arm64_linux,
    arm64_macos,
    arm64_windows,
    riscv64_linux,
}

// 获取当前平台
const target: @asm_target = @asm_target();

// 条件编译示例
fn platform_specific_add(a: i32, b: i32) i32 {
    var result: i32;
    
    if @asm_target() == .x86_64_linux {
        @asm {
            "add {a}, {b}" (a, b, -> result);
        }
    } else if @asm_target() == .arm64_linux {
        @asm {
            "add {a}, {b}, {result}" (a, b, -> result);
        }
    } else {
        // 使用 Uya 原生加法
        result = a + b;
    }
    
    return result;
}
```

**x86-64 平台系统调用**：
```uya
fn x86_64_syscall_write(fd: i32, buf: &const byte, count: i32) !i32 {
    const SYS_write: i64 = 1;
    var result: i64;

    @asm {
        "mov rax, {nr}" (SYS_write, -> rax);
        "mov rdi, {fd}" (fd, -> rdi);
        "mov rsi, {buf}" (buf, -> rsi);
        "mov rdx, {count}" (count, -> rdx);
        "syscall" (rax, rdi, rsi, rdx, -> result);
    } clobbers = ["rcx", "r11", "memory"];

    if result < 0 { return error.SyscallFailed; }
    return result as! i32;
}
```

**ARM64 平台系统调用**：
```uya
fn arm64_syscall_write(fd: i32, buf: &const byte, count: i32) !i32 {
    const SYS_write: i64 = 64;
    var result: i64;

    @asm {
        "mov x8, {nr}" (SYS_write, -> x8);
        "mov x0, {fd}" (fd, -> x0);
        "mov x1, {buf}" (buf, -> x1);
        "mov x2, {count}" (count, -> x2);
        "svc #0" (x8, x0, x1, x2, -> result);
    } clobbers = ["x16", "x17", "memory"];

    if result < 0 { return error.SyscallFailed; }
    return result as! i32;
}
```

**@asm 规则**：
- **类型安全**：编译期类型检查，防止类型不匹配
- **输出变量声明**：必须在 @asm 块外显式声明
- **输入限制**：最多 16 个输入表达式
- **输出限制**：最多 16 个输出表达式
- **clobbers 声明**：必须显式声明所有被修改的寄存器
- **内存修改**：修改内存的指令必须声明 `"memory"` clobber
- **FFI 指针**：不能直接使用，必须转换为 Uya 指针类型
- **原子操作**：必须使用 `atomic T` 类型
- **平台支持**：依后端与目标而定；寄存器类型完整集合以 `src/checker/type_utils.uya`、`src/codegen/c99/types.uya` 为准

**内存安全机制**：
1. **指针类型转换**：FFI 指针不能直接使用，必须转换为 Uya 指针
2. **内存操作声明**：修改内存的指令必须声明 `"memory"` clobber
3. **边界检查**：数组访问需要边界检查证明
4. **并发安全**：原子操作必须使用 `atomic T` 类型

**最佳实践**：
1. **优先使用编译器优化**：普通操作不要用 @asm
2. **显式声明 clobbers**：确保编译器优化正确
3. **使用类型安全的内存操作**：使用 `@asm_mem()` 包装
4. **使用平台抽象**：用 `@asm_target()` 检测平台
5. **优先使用原子类型**：并发操作使用 `atomic T`

**常见错误与修正**：
```uya
// ❌ 错误：输出变量未声明
@asm {
    "add {a}, {b}" (a, b, -> result);  // result 未声明
}

// ✅ 正确
var result: i32;
@asm {
    "add {a}, {b}" (a, b, -> result);
}

// ❌ 错误：忘记 clobbers 声明
@asm {
    "syscall" (rax, rdi, -> result);  // 可能导致优化错误
}

// ✅ 正确
@asm {
    "syscall" (rax, rdi, -> result);
} clobbers = ["rcx", "r11", "memory"];

// ❌ 错误：类型不支持
var f: f64 = 3.14;
@asm {
    "nop" (f);  // f64 不支持
}

// ✅ 正确
var i: i32 = 3;
@asm {
    "nop" (i);
}

// ❌ 错误：FFI 指针直接使用
extern malloc(size: usize) *void;
var ptr: *void = malloc(100);
@asm {
    "nop" (ptr);  // FFI 指针不能直接使用
}

// ✅ 正确
var buffer: [byte: 100] = [];
var ptr: &byte = &buffer[0];
@asm {
    "nop" (ptr);
}
```

**新增内置函数详解**：

```uya
// @syscall - 系统调用（Linux x86-64）
const result: !i64 = @syscall(60, 0);  // exit(0)，返回错误联合类型

// @ptr_from_usize - 从 usize 转换为指针
const ptr: &void = @ptr_from_usize(addr);

// @usize_from_ptr - 从指针转换为 usize
const addr: usize = @usize_from_ptr(ptr);

// @va_start / @va_end / @va_arg / @va_copy - 可变参数处理（FFI）
fn my_printf(fmt: *byte, ...) i32 {
    var ap: va_list = va_list{};
    @va_start(&ap, fmt);
    const arg1: i32 = @va_arg(ap, i32);
    @va_end(&ap);
    return 0;
}
// @va_copy(&dest, src) 见规范 §5.4 与 tests/test_va_list_builtin.uya

// @print/@println - 调试输出（编译期展开为 printf）
// 支持：整数/浮点/bool、字面量 "..."、i8/u8/byte 的 &[T]/[T:N]、*byte 等；[byte:N]、&[byte] 变量走 %s（须 \0 结尾）
@println(x);  // 打印并换行
@print(y);    // 打印不换行

// @vector/@mask - SIMD 向量与掩码
type Vec4i32 = @vector(i32, 4);
const zeros: @vector(i32, 4) = @vector.splat(0);
const lt: @mask(4) = a < b;
if @vector.any(lt) { /* ... */ }
```

## 完整示例

```uya
extern printf(fmt: *byte, ...) i32;

// 错误定义
error DivisionByZero;

// 枚举定义
enum Color {
    RED,
    GREEN,
    BLUE
}

// 类型别名
type Point = (i32, i32);

// 结构体定义
struct Vec3 {
    x: f32,
    y: f32,
    z: f32
}

// 接口定义
interface IWriter {
    fn write(self: &Self, buf: *byte, len: i32) i32;
}

// 结构体实现接口
struct Console : IWriter {
    fd: i32,
    fn write(self: &Self, buf: *byte, len: i32) i32 {
        extern write(fd: i32, buf: *void, count: i32) i32;
        return write(self.fd, buf, len);
    }
}

// 函数定义
fn divide(a: i32, b: i32) !i32 {
    if b == 0 {
        return error.DivisionByZero;
    }
    return a / b;
}

fn main() !i32 {
    // 变量声明
    const x: i32 = 10;
    var y: i32 = 5;
    
    // 错误处理
    const result: i32 = try divide(x, y);
    
    // 枚举使用
    const color: Color = Color.RED;
    
    // 元组使用
    const point: Point = (10, 20);
    const x_coord: i32 = point.0;
    
    // 数组和切片
    var arr: [i32: 10] = [0: 10];
    const slice: &[i32] = &arr[2:5];
    
    // for循环
    for slice |value| {
        printf("%d\n", value);
    }
    
    // match表达式
    match color {
        Color.RED => printf("Red\n"),
        Color.GREEN => printf("Green\n"),
        Color.BLUE => printf("Blue\n")
    };
    
    // 字符串插值
    const msg: [i8: 64] = "result=${result}\n";
    printf(&msg[0]);
    
    return 0;
}
```

## 宏系统

### 宏定义语法

```uya
mc macro_name(param1: expr, param2: type) expr {
    const value = @mc_eval(param1)
    const type_info = @mc_type(param2)
    @mc_code(@mc_ast( /* 生成的代码 */ ))
}
```

**参数类型**：`expr`、`stmt`、`type`、`pattern`  
**返回标签**：`expr`、`stmt`、`struct`、`type`

### 编译时内置函数（宏内使用）

见上文"关键字"章节的内置函数列表。

### 宏调用

```uya
const result = macro_name(arg1, arg2);  // 与函数调用语法一致
```

宏在编译时展开，调用被替换为宏生成的代码。

### 跨模块宏导出与导入

```uya
// macro_lib/macro_lib.uya - 导出宏
export mc add(a: expr, b: expr) expr {
    ${a} + ${b};
}

// main.uya - 导入并使用宏
use macro_lib.add;
const sum: i32 = add(10, 20);  // 30
```

### 示例

```uya
mc assert(cond) stmt {
    const val = @mc_eval(cond)
    if !val { @mc_error("断言失败") }
    @mc_code(@mc_ast({}))
}
```

---

## 文档定位与版本

- **本文件**：`docs/uya.md` 的 AI 用压缩摘要，便于代码生成与问答。
- **权威规范**：语义、BNF、与编译器一致性以 **`docs/uya.md`**、**`docs/grammar_formal.md`**、**`docs/builtin_functions.md`** 为准；冲突时以规范与测试为准。
- **对应规范版本**：与 `docs/uya.md` 头部一致（当前 **0.49.41**）。
- **更新日期**：2026-03-22

### 自举编译器实现索引（摘要）

以下便于对照仓库内实现，**不替代规范正文**：

| 主题 | 代码位置（约） |
|------|----------------|
| 内置 `@` 识别 | `src/lexer.uya`（未知内置报错与已识别内置名一致；细节以规范为准） |
| 越界/证明遍历 | `src/checker/proof.uya`（`bounds_check_pass` 等） |
| 优化级别 | `src/main.uya`（`-O0`…`-O3`、`--opt=<0-3>`） |
| 常量折叠、DCE、证明相关优化 | `src/checker/optimizer.uya`（能力随版本演进） |
| C99 代码生成 | `src/codegen/c99/*.uya` |

```bash
./bin/uya --opt=2 source.uya -o output.c   # 优化级别 2
./bin/uya -O2 source.uya -o output.c       # 简写
```

| 级别 | 含义（与 `main.uya` 帮助一致） |
|------|--------------------------------|
| `-O0` | 禁用优化（调试） |
| `-O1` | 常量折叠 + 死代码消除（默认） |
| `-O2` | 含证明相关优化 |
| `-O3` | 更激进优化（内联等，持续完善） |

---

