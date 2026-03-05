# Uya 开发技能文档

本文档记录 Uya 编译器开发过程中的关键经验，帮助 AI 助手更好地进行开发。

---

## 1. Uya 语法规则

### 1.1 字符串比较函数

`str_equals(s1, s2)` 函数约定：
- **返回 1**：字符串相等
- **返回 0**：字符串不相等

```uya
// 正确用法：判断相等
if str_equals(name, "expected") != 0 {
    // name == "expected"
}

// 正确用法：判断不相等
if str_equals(name, "expected") == 0 {
    // name != "expected"
}
```

**错误示例**：
```uya
// 错误！这会导致逻辑反转
if str_equals(name, "expected") == 0 {
    // 这里实际是"不相等"的情况
}
```

### 1.2 Union 变体类型限制

根据语言规范 §4.5.12：
- Union 变体**不能**包含引用类型 `&T`
- Union 变体**不能**包含切片类型 `&[T]`
- Union 变体**可以**包含指针类型（因为指针没有生命周期约束）

```uya
// ✅ 正确：指针类型
union ValuePtr {
    int_val: i32,
    point: &Point,      // 指针可以
}

// ❌ 错误：引用类型（编译错误）
union ValueRef {
    int_val: i32,
    point: &Point,      // 这里 Point 本身是结构体类型，不是引用
    ref_val: &i32,      // ❌ 不能包含引用
}
```

### 1.3 Union match 表达式

```uya
union IntOrFloat {
    i: i32,
    f: f64
}

const v: IntOrFloat = IntOrFloat.i(42);

// match 表达式访问
match v {
    .i(x) => printf("int: %d\n", x),
    .f(x) => printf("float: %f\n", x)
}

// 结构体变体的字段访问
union Shape {
    point: Point,
    rect: Rect
}

match shape {
    .point(pt) => printf("x=%d, y=%d\n", pt.x, pt.y),  // pt.x 类型推断正确
    .rect(r) => printf("w=%d, h=%d\n", r.w, r.h),
    _ => printf("unknown\n")  // 通配符
}
```

### 1.4 类型转换语法

```uya
// 使用 as 关键字
const ptr: &byte = "hello" as *byte;
const num: i64 = value as i64;
```

### 1.5 错误处理

```uya
// 使用 ! 表示可能失败
fn may_fail() !void {
    return error("something went wrong");
}

// try 传播错误
fn caller() !void {
    try may_fail();  // 失败时立即返回
}

// catch 捕获错误
fn handle_error() void {
    may_fail() catch |err| {
        printf("error: %s\n", err);
    };
}
```

---

## 2. 编译器架构理解

### 2.1 自举编译流程

```
bin/uya.c (已提交的 C99 代码)
    ↓ gcc -std=c99
bin/uya (可执行编译器)
    ↓ 编译 src/*.uya
bin/uya.c (新生成的 C99 代码)
    ↓ 自举验证 (make b)
提交新版本
```

### 2.2 关键文件

| 文件 | 说明 |
|------|------|
| `src/*.uya` | 编译器源代码（唯一维护源） |
| `bin/uya.c` | 自举 C99 代码（种子文件） |
| `tests/programs/*.uya` | 测试文件 |

### 2.3 代码生成顺序

生成 C 代码时，类型定义必须在使用之前：
- 结构体必须在引用它的类型之前定义
- Union 嵌套结构体时，需要先生成依赖的结构体

---

## 3. 开发最佳实践

### 3.1 修改代码前

```bash
# 1. 验证当前状态
make tests-uya  # 应该 348/348 通过

# 2. 理解代码上下文
# 阅读相关源码，理解数据结构和控制流
```

### 3.2 修改代码后

```bash
# 1. 构建新版本
make uya

# 2. 验证自举
make b  # 必须通过！

# 3. 运行测试
make tests-uya  # 必须全部通过

# 4. 验证通过后备份（可选但推荐）
make backup  # 只有自举和测试都通过才会执行备份
```

### 3.3 自举失败处理

如果 `make b` 失败：
1. 检查修改是否影响代码生成顺序
2. 排序相关的输出必须稳定
3. 确保 err_union 等类型按名称排序

### 3.4 不要做的事

- ❌ 不要修改 `compiler-c/` 目录（已退役）
- ❌ 不要跳过自举验证
- ❌ 不要在测试失败时提交代码
- ❌ 不要删除有意义的测试
- ❌ 不要瞎编乱造语法

---

## 4. 常见陷阱

### 4.1 str_equals 返回值

**问题**：容易混淆返回值含义

**解决**：记住 `!= 0` 表示相等

### 4.2 Union 变体不能是引用

**问题**：试图在 union 变体中使用引用类型

**解决**：使用指针或值类型

### 4.3 代码生成顺序

**问题**：union 嵌套结构体时生成顺序错误

**解决**：使用 `emit_struct_deps_for_union` 确保依赖先生成

**深入理解**（2026-02-15 修复）：

union 变体是值类型结构体时，需要**递归收集嵌套依赖**：

```uya
// 示例：Location 被 ProgramData 依赖
struct Location { line: i32, column: i32 }
struct ProgramData { location: Location, ... }
union NodeData { program: ProgramData }
```

**拓扑排序**：被依赖的结构体先输出

```
Location → ProgramData → NodeData
```

**关键函数**：`collect_value_struct_deps_from_type`
- 递归处理结构体字段的值类型依赖
- 自动过滤指针类型（指针可用前向声明）

### 4.4 自举对比差异

**问题**：修改后自举对比失败

**解决**：
- 确保类型按名称排序
- 确保字段输出顺序稳定
- 每次小改动后立即验证

---

## 5. 测试编写规范

### 5.1 测试文件结构

```uya
// tests/programs/test_feature.uya
use std.testing.*;

fn test_feature_case() !void {
    const result: i32 = my_function(input);
    try assert_eq_i32(result, expected, "description");
}

fn main() i32 {
    test_suite_begin("Feature Tests");
    run_test("feature case", test_feature_case);
    return test_suite_end();
}
```

### 5.2 测试命名

- 测试文件以 `test_` 开头
- 测试函数以 `test_` 开头
- 描述性名称，说明测试什么功能

---

## 6. 记忆要点

1. **str_equals(a, b) != 0** → 字符串相等
2. **Union 变体不能是引用** → 使用 FFI 指针 `*T` 替代
3. **FFI 指针限制** → 只能在结构体字段中使用，不能作为函数参数/返回类型
4. **match 表达式规则** → 所有分支返回类型必须一致，不能混用字面量和字段
5. **match 必须处理所有变体** → 使用 `else` 处理剩余变体
6. **Uya 不支持 `_` 忽略变量** → 必须使用实际变量名
7. **自举验证必须通过** → `make b` 是最终检验
8. **测试先行** → TDD 是最佳实践
9. **不要瞎编语法** → 参考现有代码和测试
10. **测试运行方式** → 使用 `./tests/run_programs_parallel.sh file.uya --uya`
11. **测试链接** → 需要 `tests/bridge.c` 提供 `main` 函数
12. **Arena 字符串复制** → 存储指针到 Arena 数据时，必须复制字符串内容，不能只存指针
13. **泛型方法单态化** → 需要二级类型参数查找（结构体类型参数 + 方法类型参数）
14. **整数溢出检测** → 在 C 语言中，有符号整数溢出是未定义行为，不能依赖溢出后的结果判断；必须使用安全方法（如 `left > I32_MAX - right`）
15. **I32_MIN 定义** → 使用 `-2147483647 - 1` 而非 `-2147483648`，后者会被解析为一元负运算导致溢出
16. **枚举值引用问题** → 某些情况下 Uya 编译器会错误地生成 `TokenType.TOKEN_XXX` 而不是 `TOKEN_XXX`，导致 C 编译错误。临时解决方案：使用数字常量代替枚举值
17. **只显示失败的测试** → 使用 `make tests e` 或 `./tests/run_programs_parallel.sh -e` 只显示失败的测试项，避免大量通过测试的输出干扰调试

---

## 7. 泛型方法单态化实现

### 7.1 核心问题

泛型方法 `obj.method<T>()` 的单态化需要处理两层类型参数：
1. **结构体类型参数**：如 `Container<T>` 的 `T`
2. **方法类型参数**：如 `as_type<U>(self: &Self) U` 的 `U`

### 7.2 实现要点

#### 7.2.1 二级类型参数查找

在 `C99CodeGenerator` 中需要两组类型参数上下文：

```uya
// 结构体类型参数上下文（用于二级查找）
struct_type_params: &TypeParam,
struct_type_param_count: i32,
struct_type_args: & & ASTNode,
struct_type_arg_count: i32,

// 方法类型参数上下文
current_type_params: &TypeParam,
current_type_param_count: i32,
current_type_args: & & ASTNode,
current_type_arg_count: i32,
```

类型替换时先查找方法参数，再查找结构体参数。

#### 7.2.2 单态化实例名称

泛型方法的单态化实例名称格式：`StructName_TypeArg_MethodName_TypeArg`

例如 `Container<i32>.as_type<i64>()` → `Container_i32_as_type_i64`

#### 7.2.3 Self 类型处理

在 `c99_type_to_c_with_self` 函数中处理 `Self` 类型，将其替换为结构体的单态化名称。

#### 7.2.4 字符串复制陷阱

在 `register_mono_instance` 中，`generic_name` 必须复制到 Arena：

```uya
// ❌ 错误：直接存储指针（可能是局部数组）
checker.mono_instances[idx].generic_name = generic_name;

// ✅ 正确：复制字符串到 Arena
const name_copy: &byte = arena_alloc(checker.arena, (name_len + 1) as usize) as &byte;
// ... 复制内容 ...
checker.mono_instances[idx].generic_name = name_copy;
```

### 7.3 相关文件

- `src/checker.uya`：类型检查、单态化实例注册
- `src/codegen/c99/main.uya`：单态化函数生成入口
- `src/codegen/c99/function.uya`：`gen_mono_method_prototype`、`gen_mono_method_function`
- `src/codegen/c99/types.uya`：`c99_type_to_c`（二级类型参数查找）
- `src/codegen/c99/structs.uya`：`get_mono_struct_name`、`append_type_arg_suffix`
- `tests/programs/test_generic_method_call.uya`：测试用例

---

## 8. 内存安全证明系统

### 8.1 区间算术（Interval Arithmetic）

用于处理非线性表达式的边界检查：

```uya
// 区间结构
struct Interval {
    min: i32,        // 最小值
    max: i32,        // 最大值
    is_valid: i32,   // 是否有效
}

// 区间运算函数
fn interval_add(a: Interval, b: Interval) Interval;
fn interval_sub(a: Interval, b: Interval) Interval;
fn interval_mul(a: Interval, b: Interval) Interval;
fn interval_div(a: Interval, b: Interval) Interval;
fn interval_shl(a: Interval, b: Interval) Interval;  // 左移
fn interval_shr(a: Interval, b: Interval) Interval;  // 右移
```

**应用场景**：当索引表达式包含乘法、除法、移位运算时，使用区间分析估计表达式的值范围，判断是否在数组边界内。

### 8.2 无符号类型约束

无符号类型（`u8`, `u16`, `u32`, `u64`, `usize`, `byte`）的变量自动获得 `>= 0` 约束：

```uya
// 自动约束
var i: usize = get_value();
// i 自动满足 i >= 0

// 类型转换表达式支持
var base: i32 = 3;
arr[(base + 3) as usize] = 42;  // 可以正确处理类型转换
```

### 8.3 Token 类型名称

在 `checker.uya` 中引用 Token 类型时，使用正确的枚举名称：

- `TOKEN_PLUS`（加法 `+`）
- `TOKEN_MINUS`（减法 `-`）
- `TOKEN_ASTERISK`（乘法 `*`，不是 `TOKEN_STAR`）
- `TOKEN_SLASH`（除法 `/`）
- `TOKEN_LSHIFT`（左移 `<<`，不是 `TOKEN_SHL`）
- `TOKEN_RSHIFT`（右移 `>>`，不是 `TOKEN_SHR`）

### 8.4 边界检查流程

```
1. 常量索引 → 直接检查是否越界
2. 变量索引（线性表达式）→ 使用约束系统验证
3. 变量索引（非线性表达式）→ 使用区间分析验证
4. 无法验证 → 报告编译错误
```

### 8.5 相关文件

- `src/checker.uya`：
  - `Interval` 结构和区间运算函数
  - `extract_linear_expr`：提取线性表达式（支持类型转换）
  - `eval_expr_interval`：表达式区间求值
  - `verify_expr_bounds_interval`：区间边界验证
  - `is_unsigned_type`：判断无符号类型
- `tests/programs/test_usize_constraints.uya`：usize 约束测试
- `tests/programs/test_nonlinear_bounds.uya`：非线性表达式测试

### 8.6 const 变量在安全证明中的识别（2026-02-19 修复）

**问题**：编译器无法识别 `const limit = C99_MAX_MONO_INSTANCES` 与字面量是同一个值

**根本原因**：
1. `extract_linear_expr` 不识别 `const` 变量
2. `checker_eval_const_expr` 只检查全局 `const` 变量，不检查局部 `const` 变量

**修复**：
```uya
// extract_linear_expr: 识别 const 变量
if expr.type == ASTNodeType.AST_IDENTIFIER {
    const symbol: &Symbol = symbol_table_lookup(checker, expr.identifier_name);
    if symbol != null && symbol.is_const != 0 {
        const const_val: i32 = checker_eval_const_expr(checker, expr);
        if const_val != -1 {
            // 作为常量处理
            result.var_name = null;
            result.offset = const_val;
            result.is_valid = 1;
            return result;
        }
    }
    // 否则作为变量处理
    ...
}

// checker_eval_const_expr: 检查符号表中的局部 const 变量
const symbol: &Symbol = symbol_table_lookup(checker, expr.identifier_name);
if symbol != null && symbol.is_const != 0 && symbol.decl_node != null {
    const decl: &ASTNode = symbol.decl_node;
    if decl.type == ASTNodeType.AST_VAR_DECL && decl.var_decl_init != null {
        return checker_eval_const_expr(checker, decl.var_decl_init);
    }
}
```

**效果**：`while i < LIMIT`（其中 `const LIMIT = 10`）现在可以正确识别约束 `i < 10`

### 8.7 安全证明错误提示改进（2026-02-19 修复）

**问题**：安全证明错误只显示 "数组索引安全证明失败"，没有给出具体修复指导

**改进后的错误提示**：
```
/tmp/test.uya:(5:9): 错误: 数组索引安全证明失败
  变量: i, 数组大小: 10
  已知下界: i >= 0
  缺少上界: 需要 i < 10
  建议: 在数组访问前添加边界检查
    if i >= 0 && i < 10 { arr[i] ... }
```

**实现要点**：
- 在 `checker_report_error_ex` 中分析并显示当前约束状态
- 区分"已知约束"和"缺少约束"
- 提供具体的修复代码示例

### 8.8 数组边界与循环上限匹配（2026-02-19 修复）

**问题**：`checker.mono_instances` 数组大小是 512，但循环使用 `C99_MAX_MONO_INSTANCES = 1024`

**教训**：
- 循环上限必须使用被访问数组的实际大小
- 字面量常量比命名常量更容易被安全证明系统识别
- 两个模块中的同名常量可能有不同的值

**正确写法**：
```uya
// checker.mono_instances 大小是 512
while i < 512 {
    if i < checker.mono_instance_count {
        // 访问 checker.mono_instances[i] 是安全的
    }
    i = i + 1;
}
```

---

## 9. Syscall 层开发经验（2026-03-05）

### 9.1 syscall 函数实现规范

#### 9.1.1 函数声明方式

**核心原则**：syscall 层不链接 C 标准库，因此不使用 `extern "libc"`。

```uya
// ✅ 正确：使用 export fn
export fn sys_read(fd: i32, buf: &byte, count: usize) !isize {
    return @syscall(SYS_read, fd as i64, buf as i64, count as i64) as! isize;
}

// ❌ 错误：sys_nanosleep 和 sys_gettimeofday 错误使用了 extern "libc"
export extern "libc" fn sys_nanosleep(req: &const TimeSpec, rem: &TimeSpec) !i32 {
    return @syscall(SYS_nanosleep, req as i64, rem as i64) as! i32;
}
```

**原因**：
- `export extern "libc" fn` 用于在 libc 层实现 C 标准库函数（带函数体）
- syscall 层是 Uya 内部使用，不需要与 C 标准库兼容
- 使用 `export fn` 会自动添加模块前缀（`libc_` 或 `syscall_`），避免符号冲突

#### 9.1.2 双重文件维护

syscall 函数需要在两个文件中保持完全一致：

```uya
// lib/libc/syscall.uya（旧位置，待迁移）
export const SYS_getpid: i64 = 39;
export fn sys_getpid() !i64 {
    return @syscall(SYS_getpid);
}

// lib/syscall/linux.uya（新位置，标准库重构 Phase 1）
export const SYS_getpid: i64 = 39;
export fn sys_getpid() !i64 {
    return @syscall(SYS_getpid);
}
```

**注意事项**：
- 系统调用号常量必须在两个文件中都定义
- 函数签名（参数类型、返回类型）必须完全一致
- 函数体实现也必须一致

**迁移计划**（待完成）：
- 明确 `lib/libc/syscall.uya` 的废弃时间
- 逐步将所有 use 语句从 `libc.syscall` 迁移到 `syscall`
- 最后删除 `lib/libc/syscall.uya`

### 9.2 测试编写规范

#### 9.2.1 expect 函数限制

**问题**：`expect` 函数不支持消息参数

```uya
// ❌ 错误：expect 不支持第二个消息参数
try expect(result == 0, "sys_nanosleep should succeed");

// ✅ 正确：只使用布尔表达式
try expect(result == 0);
```

#### 9.2.2 struct 定义位置限制

**问题**：Uya 不支持在函数内部定义 struct

```uya
// ❌ 错误：struct 不能在函数内部定义
test "test_ioctl" {
    struct winsize {
        ws_row: u16,
        ws_col: u16,
    }
    var ws: winsize = ...;
}

// ✅ 正确：struct 必须在文件级别定义
struct winsize {
    ws_row: u16,
    ws_col: u16,
}

test "test_ioctl" {
    var ws: winsize = ...;
}
```

#### 9.2.3 测试文件命名规范

- 测试文件以 `test_syscall_` 开头，后跟功能模块名
- 示例：
  - `test_syscall_time.uya` - 时间相关测试
  - `test_syscall_user.uya` - 用户/组测试
  - `test_syscall_ioctl.uya` - 设备控制测试
  - `test_syscall_thread.uya` - 线程测试

### 9.3 常见问题与解决方案

#### 9.3.1 编译缓存问题

**症状**：修改头文件后，编译器仍然使用旧版本

```bash
# 解决方法：删除编译缓存
rm src/build/uya.c
make check
```

**原因**：`src/build/uya.c` 可能缓存了旧的定义

#### 9.3.2 缺失系统调用号

**症状**：编译错误 "undefined reference to SYS_xxx"

```uya
// 需要在 lib/syscall/linux.uya 中添加常量
export const SYS_nanosleep: i64 = 35;
export const SYS_gettimeofday: i64 = 96;
export const SYS_fcntl: i64 = 72;
export const SYS_getuid: i64 = 102;
// ... 其他系统调用号
```

**Linux x86-64 系统调用号参考**：
- SYS_gettid: 186
- SYS_getuid: 102
- SYS_getgid: 104
- SYS_setuid: 105
- SYS_setgid: 106
- SYS_geteuid: 107
- SYS_getegid: 108
- SYS_fcntl: 72

### 9.4 已实现的 syscall 函数清单（截至 2026-03-05）

#### 9.4.1 基础文件操作
- ✅ `sys_read(fd, buf, count)` - 读取文件
- ✅ `sys_write(fd, buf, count)` - 写入文件
- ✅ `sys_open(pathname, flags, mode)` - 打开文件
- ✅ `sys_close(fd)` - 关闭文件
- ✅ `sys_lseek(fd, offset, whence)` - 文件定位

#### 9.4.2 内存管理
- ✅ `sys_mmap(addr, length, prot, flags, fd, offset)` - 内存映射
- ✅ `sys_munmap(addr, length)` - 解除映射
- ✅ `sys_brk(addr)` - 更改数据段地址

#### 9.4.3 进程/线程相关
- ✅ `sys_exit(status)` - 退出进程
- ✅ `sys_getpid()` - 获取进程 ID
- ✅ `sys_getppid()` - 获取父进程 ID
- ✅ `sys_kill(pid, sig)` - 发送信号
- ✅ `sys_waitpid(pid, status, options)` - 等待子进程
- ✅ `sys_fork()` - 创建进程
- ✅ `sys_execve(path, argv, envp)` - 执行程序
- ✅ `sys_clone(flags, child_stack, ptid, ctid, tls)` - 克隆进程/线程
- ✅ `sys_gettid()` - 获取线程 ID

#### 9.4.4 时间相关
- ✅ `sys_nanosleep(req, rem)` - 纳秒级睡眠
- ✅ `sys_gettimeofday(tv, tz)` - 获取当前时间

#### 9.4.5 设备/控制
- ✅ `sys_ioctl(fd, request, arg)` - 设备控制
- ✅ `sys_fcntl(fd, cmd, arg)` - 文件控制

#### 9.4.6 文件/目录操作
- ✅ `sys_stat(pathname, statbuf)` - 获取文件状态
- ✅ `sys_fstat(fd, statbuf)` - 获取文件状态（通过描述符）
- ✅ `sys_lstat(pathname, statbuf)` - 获取符号链接状态
- ✅ `sys_access(pathname, mode)` - 检查文件权限
- ✅ `sys_unlink(pathname)` - 删除文件
- ✅ `sys_mkdir(pathname, mode)` - 创建目录
- ✅ `sys_rmdir(pathname)` - 删除目录
- ✅ `sys_chdir(pathname)` - 切换目录
- ✅ `sys_getcwd(buf, size)` - 获取当前目录
- ✅ `sys_readlink(pathname, buf, bufsiz)` - 读取符号链接
- ✅ `sys_rename(oldpath, newpath)` - 重命名文件
- ✅ `sys_dup(fd)` - 复制文件描述符
- ✅ `sys_dup2(oldfd, newfd)` - 复制文件描述符到指定值

#### 9.4.7 用户/组相关
- ✅ `sys_getuid()` - 获取真实用户 ID
- ✅ `sys_getgid()` - 获取真实组 ID
- ✅ `sys_setuid(uid)` - 设置真实用户 ID
- ✅ `sys_setgid(gid)` - 设置真实组 ID
- ✅ `sys_geteuid()` - 获取有效用户 ID
- ✅ `sys_getegid()` - 获取有效组 ID

#### 9.4.8 线程同步
- ✅ `sys_futex(uaddr, op, val, timeout)` - 快速用户空间互斥
- ✅ `sched_setaffinity(pid, cpusetsize, mask)` - 设置 CPU 亲和性
- ✅ `sched_getaffinity(pid, cpusetsize, mask)` - 获取 CPU 亲和性

#### 9.4.9 资源限制
- ✅ `sys_getrlimit(resource, rlim)` - 获取资源限制
- ✅ `sys_setrlimit(resource, rlim)` - 设置资源限制

### 9.5 开发检查清单

实现新的 syscall 函数时，按以下步骤操作：

```bash
# 1. 在 lib/syscall/linux.uya 中添加系统调用号常量
export const SYS_NEWCALL: i64 = 123;

# 2. 在 lib/syscall/linux.uya 中实现函数
export fn sys_newcall(...) !ReturnType {
    return @syscall(SYS_NEWCALL, ...) as! ReturnType;
}

# 3. 在 lib/libc/syscall.uya 中添加相同的常量和函数
export const SYS_NEWCALL: i64 = 123;
export fn sys_newcall(...) !ReturnType {
    return @syscall(SYS_NEWCALL, ...) as! ReturnType;
}

# 4. 创建测试文件 tests/test_syscall_xxx.uya
# 测试基本功能、边界条件、错误处理

# 5. 运行测试验证
make tests  # 确保所有测试通过

# 6. 如果有编译缓存问题
rm src/build/uya.c
make check  # 完整验证（自举 + 测试）
```

### 9.6 关键记忆要点

1. **syscall 层不使用 extern "libc"** - 使用 `export fn` 而非 `export extern "libc" fn`
2. **双重文件维护** - `lib/libc/syscall.uya` 和 `lib/syscall/linux.uya` 必须保持一致
3. **expect 不支持消息参数** - 只传递布尔表达式
4. **struct 不能在函数内定义** - 必须在文件级别定义
5. **编译缓存问题** - 修改常量后可能需要删除 `src/build/uya.c`
6. **系统调用号必须完整** - 缺少常量会导致链接错误
7. **测试先行原则** - 实现 syscall 前先写测试

---

## 10. osal 层开发经验（2026-03-05）

### 10.1 osal 层已完成

**完成日期**：2026-03-05  
**测试覆盖**：所有功能均有对应测试，496 个测试全部通过

### 10.2 已实现的功能

#### 10.2.1 文件操作
- `os_open(path, flags, mode)` - 打开文件
- `os_close(f)` - 关闭文件
- `os_read(f, buf, count)` - 读取文件
- `os_write(f, buf, count)` - 写入文件
- `os_seek(f, offset, whence)` - 文件定位
- `os_stat(path, statbuf)` - 获取文件状态
- `os_fstat(fd, statbuf)` - 通过描述符获取文件状态
- `os_lstat(path, statbuf)` - 获取符号链接状态

#### 10.2.2 内存管理
- `os_mmap(addr, size, prot, flags, fd, offset)` - 内存映射
- `os_munmap(addr, size)` - 解除映射

#### 10.2.3 进程/线程
- `os_spawn(path, args, env)` - 创建进程
- `os_exec(path, args, env)` - 执行程序
- `os_execve(path, argv, envp)` - 执行程序（完整版）
- `os_exit(code)` - 退出进程
- `os_getpid()` - 获取进程 ID
- `os_getppid()` - 获取父进程 ID
- `os_gettid()` - 获取线程 ID
- `os_kill(pid, sig)` - 发送信号
- `os_waitpid(pid, status, options)` - 等待子进程
- `os_fork()` - 创建进程

#### 10.2.4 时间操作
- `os_sleep(seconds, nanoseconds)` - 纳秒级睡眠
- `os_gettimeofday(tv, tz)` - 获取当前时间
- `os_clock_gettime(clock_id)` - 获取时钟时间

#### 10.2.5 目录操作
- `os_mkdir(path, mode)` - 创建目录
- `os_rmdir(path)` - 删除目录
- `os_chdir(path)` - 切换目录
- `os_getcwd(buf, size)` - 获取当前目录
- `os_access(path, mode)` - 检查文件权限
- `os_unlink(path)` - 删除文件
- `os_rename(oldpath, newpath)` - 重命名文件
- `os_readlink(path, buf, bufsiz)` - 读取符号链接
- `os_getdents64(fd, dirp, count)` - 读取目录项

#### 10.2.6 其他功能
- `os_dup(fd)` - 复制文件描述符
- `os_dup2(oldfd, newfd)` - 复制文件描述符到指定值
- `os_fcntl(fd, cmd, arg)` - 文件控制
- `os_ioctl(fd, request, arg)` - 设备控制
- `os_getuid()` - 获取真实用户 ID
- `os_getgid()` - 获取真实组 ID
- `os_geteuid()` - 获取有效用户 ID
- `os_getegid()` - 获取有效组 ID
- `os_setuid(uid)` - 设置真实用户 ID
- `os_setgid(gid)` - 设置真实组 ID
- `os_getrlimit(resource, rlim)` - 获取资源限制
- `os_setrlimit(resource, rlim)` - 设置资源限制

### 10.3 错误处理

osal 层定义了统一的错误类型，使用 `!T` 风格：

```uya
error NotFound;
error PermissionDenied;
error AlreadyExists;
error InvalidInput;
error IoError;
error OutOfMemory;
error NotSupported;
error TimedOut;
error Interrupted;
```

### 10.4 测试覆盖

测试文件：`tests/test_osal.uya`

覆盖的测试用例：
- 进程 ID 获取：`os_getpid`、`os_getppid`、`os_gettid`
- 用户/组信息：`os_getuid`、`os_getgid`、`os_geteuid`、`os_getegid`
- 目录操作：`os_mkdir_rmdir`、`os_mkdir_rmdir2`、`os_access`
- 文件描述符：`os_dup`、`os_dup2`
- 时间：`os_gettimeofday`、`os_getrlimit`
- 文件 I/O：`os_open_write_read_close`、`os_seek`
- 睡眠：`os_sleep`

### 10.5 关键要点

1. **统一错误类型** - osal 层定义了一组统一的错误类型，所有函数使用 `!T` 风格返回
2. **完全依赖 syscall** - osal 层只依赖 syscall 层，不依赖 libc 或 std
3. **测试先行** - 所有功能都有对应的测试用例
4. **API 设计一致** - 所有函数遵循统一的命名约定和错误处理方式
5. **跨平台预留** - osal 层为跨平台扩展预留了接口，当前仅支持 Linux

### 10.6 相关文件

- `lib/osal/osal.uya` - osal 层实现
- `tests/test_osal.uya` - osal 层测试
- `docs/todo_std_refactor.md` - 标准库重构计划（Phase 3）
- `docs/libc_progress.md` - libc 开发进度

---

## 11. Phase 4 重构遇到的编译器问题（2026-03-05）

### 11.1 问题描述

**目标**：Phase 4（libc 层）重构要求 `lib/libc/string.uya` 和 `lib/libc/mem.uya` 调用 `lib/mem/mem.uya` 的函数。

**问题**：当在 `lib/libc/` 目录的文件中添加 `use mem` 语句时，编译器自举会失败（退出码 141 或链接错误）。

### 11.2 问题根因分析

**模块命名冲突**：
1. `lib/mem/mem.uya` 导出内部函数名：`mem_copy`, `mem_set`, `mem_compare`, `strlen`, `strcmp` 等
   - 这些函数生成 C 代码时会加上 `mem_` 前缀：`mem_memset`, `mem_strlen` 等
2. `lib/libc/mem.uya` 需要导出 libc 兼容函数：`export extern "libc" fn memcpy`, `memset`, `memcmp`, `strlen` 等
   - 这些函数应该生成**裸名**（没有模块前缀）：`memcpy`, `memset`, `memcmp`, `strlen` 等
3. **冲突**：当 `lib/libc/mem.uya` `use mem` 时，两个模块的函数都会被生成到 C 代码
   - 导致重复定义错误：`error: redefinition of 'memcmp'`

### 11.3 验证结果

**成功的场景**：
- ✅ 普通测试文件（如 `tests/test_libc_use_mem.uya`）可以成功 `use mem` 并使用 mem 层函数
- ✅ 编译、链接、运行都正常

**失败的场景**：
- ❌ `lib/libc/` 目录下的文件（如 `lib/libc/mem.uya`）使用 `use mem` 会导致编译器自举时崩溃或链接失败

### 11.4 结论

**当前状态**：
- Phase 1（syscall 层）：✅ 已完成
- Phase 2（mem 层）：✅ 已完成  
- Phase 3（osal 层）：✅ 已完成
- Phase 4（libc 层）：⚠️ 需要先修复编译器才能进行跨层导入
- Phase 5（std 层）：⏳ 待开始

### 11.5 建议方案

**短期方案**（继续 Phase 5）：
1. Phase 4（libc 层重构）暂时搁置，等待编译器修复
2. Phase 5（std 层）可以直接使用 osal 和 mem 层，不需要依赖 libc 层
3. std 层的开发可以继续进行，不会受到影响

**长期方案**（修复编译器）：
1. 分析编译器在处理 `lib/libc/` 目录跨层导入时的特殊逻辑
2. 修复模块命名冲突，避免重复定义
3. 可能需要调整模块前缀生成规则，支持同一目录下不同层级的模块隔离

### 11.6 关键要点

1. **跨层导入的目录限制** - 编译器对 `lib/libc/` 目录有特殊处理，该目录下的文件无法正常 `use` 其他目录的模块
2. **函数名冲突** - 内部函数名（带前缀）和 libc 兼容名（裸名）不能在同一个编译单元中同时生成
3. **测试与实现的差异** - 普通测试文件没有特殊处理，可以正常跨层导入，但 `lib/libc/` 目录下的文件不行
4. **分层架构的挑战** - libc 层作为 C 兼容层，需要在调用 mem 层时处理命名和 ABI 兼容性问题

### 11.7 相关文件

- `lib/mem/mem.uya` - mem 层实现
- `lib/libc/mem.uya` - libc 层内存函数（待重构）
- `lib/libc/string.uya` - libc 层字符串函数（待重构）
- `tests/test_libc_use_mem.uya` - 测试 mem 层函数调用（已验证成功）
