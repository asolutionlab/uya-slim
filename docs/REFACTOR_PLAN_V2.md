# Uya 编译器代码重构计划 v2.0

> 目标：使用 Uya 0.47 最新语法规范重构自举编译器，提升代码质量和可维护性

## 项目概述

### 当前状态
- 自举编译时间：1.8s
- 测试覆盖：414 个测试全部通过
- 代码行数：~27,000 行（checker 10,978 + parser 7,212 + codegen ~8,000）

### 重构目标
- 函数行数 ≤ 50 行
- 嵌套深度 ≤ 3 层
- 减少重复代码
- 统一代码风格

### 使用的 Uya 0.47 新特性
- `test "name" {}` - 测试语句（替代 main 函数测试）
- `for 0..N |i| {}` - 整数范围迭代
- `"text${expr}text"` - 字符串插值
- `@print/@println` - 调试输出
- `@syscall` - 系统调用（低层操作）

---

## 阶段一：巨型函数拆分 [████░░░░░░] 40%

### 1.1 checker_infer_type 拆分（最高优先级）

**当前状态**：~1200 行单一函数，处理所有表达式类型推断

**重构方案**：按表达式类型分派到独立函数

```
src/checker/check_expr.uya
├── checker_infer_type()          # 主入口，分派器（< 50 行）
├── infer_identifier()            # 标识符推断
├── infer_literal()               # 字面量推断
├── infer_binary_expr()           # 二元表达式推断
├── infer_unary_expr()            # 一元表达式推断
├── infer_call_expr()             # 函数调用推断
├── infer_member_access()         # 成员访问推断
├── infer_array_access()          # 数组访问推断
├── infer_match_expr()            # match 表达式推断
├── infer_cast_expr()             # 类型转换推断
└── infer_struct_init()           # 结构体初始化推断
```

**重构示例（使用 Uya 0.47 特性）**：

```uya
// 主入口：使用 match 表达式分派（< 50 行）
fn checker_infer_type(checker: &TypeChecker, expr: &ASTNode) Type {
    if expr == null { return make_void_type(); }
    
    match expr.type {
        ASTNodeType.AST_IDENTIFIER => return infer_identifier(checker, expr),
        ASTNodeType.AST_NUMBER => return infer_literal(checker, expr),
        ASTNodeType.AST_BINARY_EXPR => return infer_binary_expr(checker, expr),
        ASTNodeType.AST_CALL_EXPR => return infer_call_expr(checker, expr),
        ASTNodeType.AST_MEMBER_ACCESS => return infer_member_access(checker, expr),
        ASTNodeType.AST_MATCH_EXPR => return infer_match_expr(checker, expr),
        else => return make_void_type()
    };
}

// 独立函数示例：使用字符串插值记录错误
fn infer_call_expr(checker: &TypeChecker, expr: &ASTNode) Type {
    if expr.call_expr_callee == null {
        // 使用字符串插值生成错误消息
        const msg: [i8: 128] = "调用表达式缺少被调用者（行 ${expr.line}）";
        checker_report_error(checker, expr, &msg[0] as &byte);
        return make_void_type();
    }
    // ... 推断逻辑
}
```

**预估工作量**：3-5 天

### 1.2 gen_stmt 拆分（高优先级）

**当前状态**：~1593 行单一函数，处理所有语句类型代码生成

**重构方案**：按语句类型分派

```
src/codegen/c99/stmt.uya
├── gen_stmt()                    # 主入口，分派器（< 50 行）
├── gen_var_decl()                # 变量声明生成
├── gen_if_stmt()                 # if 语句生成
├── gen_while_stmt()              # while 语句生成
├── gen_for_stmt()                # for 语句生成
├── gen_return_stmt()             # return 语句生成
├── gen_defer_stmt()              # defer 语句生成
├── gen_block()                   # 代码块生成
└── gen_expr_stmt()               # 表达式语句生成
```

**预估工作量**：3-5 天

### 1.3 gen_expr 拆分（高优先级）

**当前状态**：~2000+ 行单一函数

**重构方案**：按表达式类型分派

```
src/codegen/c99/expr.uya
├── gen_expr()                    # 主入口，分派器（< 50 行）
├── gen_identifier()              # 标识符生成
├── gen_literal()                 # 字面量生成
├── gen_binary_expr()             # 二元表达式生成
├── gen_unary_expr()              # 一元表达式生成
├── gen_call_expr()               # 函数调用生成
├── gen_member_access()           # 成员访问生成
├── gen_array_access()            # 数组访问生成
├── gen_match_expr()              # match 表达式生成
└── gen_string_interp()           # 字符串插值生成
```

**预估工作量**：3-5 天

---

## 阶段二：嵌套深度优化 [██░░░░░░░░] 20%

### 2.1 提前返回模式

**问题位置**：
- `checker/check_expr.uya` 第 544-623 行：AST_MATCH_EXPR 嵌套 6 层
- `codegen/c99/stmt.uya` 第 313-530 行：AST_RETURN_STMT 嵌套 5-6 层

**重构示例**：

```uya
// 重构前（嵌套 6 层）
fn process_match(expr: &ASTNode) void {
    if expr != null {
        if expr.type == AST_MATCH_EXPR {
            if expr.match_expr_arms != null {
                var i: i32 = 0;
                while i < expr.match_expr_arm_count {
                    if arms[i] != null {
                        if arms[i].kind == MATCH_PAT_UNION {
                            // 处理代码...
                        }
                    }
                    i = i + 1;
                }
            }
        }
    }
}

// 重构后（嵌套 2 层，使用 Uya 0.47 特性）
fn process_match(expr: &ASTNode) void {
    if expr == null { return; }
    if expr.type != AST_MATCH_EXPR { return; }
    if expr.match_expr_arms == null { return; }
    
    // 使用 for 范围迭代替代 while
    for 0..expr.match_expr_arm_count |i| {
        const arm: &ASTNode = arms[i];
        if arm == null { continue; }
        
        if arm.kind == MATCH_PAT_UNION {
            process_union_arm(arm);  // 提取函数
        }
    }
}
```

**预估工作量**：2-3 天

### 2.2 提取辅助函数

将深层嵌套中的复杂逻辑提取为独立函数：

```
src/checker/check_expr.uya
├── extract_match_union_handling()     # 处理 match union 变体
├── validate_match_exhaustiveness()    # 验证 match 完备性
└── infer_match_arm_type()             # 推断 match 分支类型

src/codegen/c99/stmt.uya
├── emit_return_with_defer()           # 带 defer 的 return
├── emit_return_error_union()          # 返回错误联合类型
└── emit_return_void()                 # 返回 void
```

**预估工作量**：2 天

---

## 阶段三：重复代码提取 [██░░░░░░░░] 20%

### 3.1 Type 初始化辅助函数

**当前问题**：Type 结构体初始化代码重复 20+ 次

**重构方案**：在 `src/checker/type_utils.uya` 添加辅助函数

```uya
// 新增辅助函数（使用 Uya 0.47 简洁语法）
fn make_void_type() Type {
    return Type { kind: TypeKind.TYPE_VOID, enum_name: null, ... };
}

fn make_i32_type() Type {
    return Type { kind: TypeKind.TYPE_I32, ... };
}

fn make_pointer_type(pointee: &Type) Type {
    var t: Type = make_void_type();
    t.kind = TypeKind.TYPE_POINTER;
    t.pointer_to = pointee;
    return t;
}

fn make_struct_type(name: &byte) Type {
    var t: Type = make_void_type();
    t.kind = TypeKind.TYPE_STRUCT;
    t.struct_name = name;
    return t;
}

fn make_array_type(elem: &Type, size: i32) Type { ... }
fn make_slice_type(elem: &Type) Type { ... }
fn make_error_union_type(payload: &Type, error_id: u32) Type { ... }
```

**预估工作量**：1 天

### 3.2 代码生成辅助函数

**当前问题**：memcpy、错误联合包装等代码重复多次

```uya
// src/codegen/c99/utils.uya 新增

fn emit_array_memcpy(codegen: &C99CodeGenerator, dest: &byte, src: &byte, type_name: &byte) void {
    // 使用字符串插值
    const line: [i8: 256] = "__uya_memcpy(${dest}, ${src}, sizeof(${type_name}));\n";
    fputs(&line[0] as *byte, codegen.output as *void);
}

fn emit_error_union_wrap(codegen: &C99CodeGenerator, type_name: &byte, value: &byte) void {
    const line: [i8: 256] = "(${type_name}){ .error_id = 0, .value = ${value} }";
    fputs(&line[0] as *byte, codegen.output as *void);
}

fn emit_indent(codegen: &C99CodeGenerator) void {
    for 0..codegen.indent_level {
        fputs("    " as *byte, codegen.output as *void);
    }
}
```

**预估工作量**：1 天

### 3.3 类型检查辅助函数统一

**当前问题**：`is_integer_type()` 等函数已存在，但代码中仍有直接类型检查

```uya
// 当前代码（不推荐）
if arg_type.kind == TypeKind.TYPE_I8 || arg_type.kind == TypeKind.TYPE_I16 ||
   arg_type.kind == TypeKind.TYPE_I32 || arg_type.kind == TypeKind.TYPE_I64 { ... }

// 推荐用法
if is_integer_type(arg_type) != 0 { ... }
```

**重构方案**：搜索并替换所有直接类型检查链

**预估工作量**：0.5 天

---

## 阶段四：Union 数据结构重构 [░░░░░░░░░░] 0%

> **重要更正**：经深度代码分析和实际测试，Uya union **完全支持引用类型变体**（`&T`）。
> 详细分析见 `docs/REFACTOR_PLAN_V2_REVIEW.md`。

### 4.1 Type 结构体 Union 化

**当前问题**：`Type` 结构体使用扁平化设计，所有字段始终存在但只有一个子集有效

```uya
// 当前设计（src/checker/types.uya:68-88）
struct Type {
    kind: TypeKind,
    // 以下字段根据 kind 只有部分有效
    enum_name: &byte,           // TYPE_ENUM 时有效
    interface_name: &byte,      // TYPE_INTERFACE 时有效
    struct_name: &byte,         // TYPE_STRUCT 时有效
    union_name: &byte,          // TYPE_UNION 时有效
    pointer_to: &Type,          // TYPE_POINTER 时有效
    element_type: &Type,        // TYPE_ARRAY 时有效
    array_size: i32,            // TYPE_ARRAY 时有效
    slice_element_type: &Type,  // TYPE_SLICE 时有效
    slice_len: i32,             // TYPE_SLICE 时有效
    tuple_element_types: &Type, // TYPE_TUPLE 时有效
    error_union_payload_type: &Type, // TYPE_ERROR_UNION 时有效
    // ... 更多字段
}
```

**问题分析**：
- 内存浪费：每个 Type 实例占用所有字段的空间
- 代码冗余：139+ 处 `kind == TypeKind.XXX` 条件判断
- 类型安全：编译器无法检查字段访问是否合法

**重构方案**：使用 union 封装变体数据

```uya
// 重构后设计
struct Type {
    kind: TypeKind,
    data: TypeData,  // union 类型
}

// 类型数据联合体
union TypeData {
    void_unit: void,           // TYPE_VOID, TYPE_I8-I64, TYPE_BOOL 等基础类型
    named: &byte,              // TYPE_ENUM, TYPE_STRUCT, TYPE_UNION, TYPE_INTERFACE 的名称
    pointer: PointerData,      // TYPE_POINTER
    array: ArrayData,          // TYPE_ARRAY
    slice: SliceData,          // TYPE_SLICE
    tuple: TupleData,          // TYPE_TUPLE
    error_union: ErrorUnionData, // TYPE_ERROR_UNION
    generic_param: &byte,      // TYPE_GENERIC_PARAM
}

struct PointerData {
    pointee: &Type,
    is_ffi: i32,
}

struct ArrayData {
    element: &Type,
    size: i32,
}

struct SliceData {
    element: &Type,
    len: i32,
}

struct TupleData {
    elements: &Type,
    count: i32,
}

struct ErrorUnionData {
    payload: &Type,
    error_id: u32,
}
```

**代码简化示例**：

```uya
// 重构前：复杂的条件判断
fn type_to_string(t: Type) &byte {
    if t.kind == TypeKind.TYPE_ENUM {
        return t.enum_name;
    } else if t.kind == TypeKind.TYPE_STRUCT {
        return t.struct_name;
    } else if t.kind == TypeKind.TYPE_UNION {
        return t.union_name;
    }
    // ...
}

// 重构后：使用 match 处理 union
fn type_to_string(t: Type) &byte {
    match t.data {
        .named(name) => return name,
        .pointer(p) => return format("*{}", type_to_string(p.pointee)),
        .array(a) => return format("[{}; {}]", type_to_string(a.element), a.size),
        .void_unit(_) => return "void",
        else => return "unknown"
    }
}
```

**预估工作量**：5 天

### 4.2 ASTNode 结构体 Union 化

**当前问题**：`ASTNode` 结构体有 100+ 个扁平化字段

```uya
// 当前设计（src/ast.uya:138-450）
struct ASTNode {
    type: ASTNodeType,
    // 100+ 个字段，根据 type 只有部分有效
    program_decls: & & ASTNode,
    program_decl_count: i32,
    enum_decl_name: &byte,
    // ... 数百个字段
}
```

**重构方案**：按节点类型分组为 union

```uya
struct ASTNode {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    data: ASTNodeData,  // union 类型
}

union ASTNodeData {
    program: ProgramData,
    enum_decl: EnumDeclData,
    struct_decl: StructDeclData,
    fn_decl: FnDeclData,
    var_decl: VarDeclData,
    binary_expr: BinaryExprData,
    call_expr: CallExprData,
    // ... 其他节点类型
}

struct ProgramData {
    decls: & & ASTNode,
    count: i32,
}

struct EnumDeclData {
    name: &byte,
    variants: &EnumVariant,
    variant_count: i32,
    is_export: i32,
}

struct BinaryExprData {
    left: &ASTNode,
    op: i32,
    right: &ASTNode,
}
```

**代码简化示例**：

```uya
// 重构前：大量的 if-else 链
fn checker_infer_type(checker: &TypeChecker, expr: &ASTNode) Type {
    if expr.type == ASTNodeType.AST_NUMBER {
        result.kind = TypeKind.TYPE_I32;
    } else if expr.type == ASTNodeType.AST_FLOAT {
        result.kind = TypeKind.TYPE_F64;
    } else if expr.type == ASTNodeType.AST_BINARY_EXPR {
        // 处理二元表达式...
    }
    // ... 数百行
}

// 重构后：使用 match 表达式
fn checker_infer_type(checker: &TypeChecker, expr: &ASTNode) Type {
    match expr.data {
        .binary_expr(b) => infer_binary(checker, b),
        .call_expr(c) => infer_call(checker, c),
        .member_access(m) => infer_member(checker, m),
        .number(_) => make_i32_type(),
        .float(_) => make_f64_type(),
        else => make_void_type()
    }
}
```

**预估工作量**：7 天

### 4.3 使用 match 替代条件链

**重构目标**：将所有基于 `kind`/`type` 的条件链替换为 match 表达式

**重构前**（564+ 处）：
```uya
if node.type == ASTNodeType.AST_PROGRAM {
    // 处理 program
} else if node.type == ASTNodeType.AST_ENUM_DECL {
    // 处理 enum
} else if node.type == ASTNodeType.AST_STRUCT_DECL {
    // 处理 struct
}
```

**重构后**：
```uya
match node.data {
    .program(p) => handle_program(p),
    .enum_decl(e) => handle_enum(e),
    .struct_decl(s) => handle_struct(s),
    else => handle_other()
}
```

**收益**：
- 编译期完备性检查
- 消除运行时标签判断开销
- 代码更简洁、更安全

**预估工作量**：3 天

---

## 阶段五：测试现代化 [░░░░░░░░░░] 0%

### 5.1 使用 test 语句重构测试

**当前问题**：测试使用 main 函数风格，不利于增量运行

**重构方案**：将 `tests/` 下的测试改为 `test "name" {}` 风格

```uya
// 重构前：tests/test_basic.uya
use std.testing.assert_eq_i32;

fn test_addition() !void {
    try assert_eq_i32(add(1, 2), 3, "1 + 2 should equal 3");
}

export fn main() i32 {
    test_addition();
    return 0;
}

// 重构后：tests/test_basic.uya
use std.testing.assert_eq_i32;

test "test_addition" {
    try assert_eq_i32(add(1, 2), 3, "1 + 2 should equal 3");
}

test "test_subtraction" {
    try assert_eq_i32(sub(5, 3), 2, "5 - 3 should equal 2");
}

// 无需 main 函数，测试运行器自动发现并执行
```

**预估工作量**：2 天

### 5.2 添加增量测试验证

为每个重构的函数添加独立测试：

```uya
// tests/test_type_utils.uya

test "make_void_type" {
    const t: Type = make_void_type();
    try assert_eq_i32(t.kind as i32, TypeKind.TYPE_VOID as i32, "should be void type");
}

test "make_i32_type" {
    const t: Type = make_i32_type();
    try assert_eq_i32(t.kind as i32, TypeKind.TYPE_I32 as i32, "should be i32 type");
}

test "make_pointer_type" {
    const elem: Type = make_i32_type();
    const ptr: Type = make_pointer_type(&elem);
    try assert_eq_i32(ptr.kind as i32, TypeKind.TYPE_POINTER as i32, "should be pointer type");
}
```

**预估工作量**：1 天

---

## 阶段六：代码质量改进 [░░░░░░░░░░] 0%

### 6.1 统一错误处理模式

**当前问题**：部分函数返回空类型，部分返回错误码

**建议规范**：
- 类型推断函数：返回 `Type`，错误时返回 `make_void_type()`
- 检查函数：返回 `i32`（0=失败，1=成功）
- 生成函数：返回 `void`，通过 `codegen.error_count` 跟踪错误

### 6.2 常量集中定义

**当前问题**：魔法数字分散在代码中

**建议方案**：在 `src/constants.uya` 集中定义

```uya
// src/constants.uya
pub const MAX_MONO_INSTANCES: i32 = 512;
pub const MAX_DEFER_DEPTH: i32 = 64;
pub const MAX_TYPE_PARAMS: i32 = 16;
pub const TEMP_BUF_SIZE: i32 = 4096;
pub const MAX_SCOPE_DEPTH: i32 = 64;
pub const SYMBOL_TABLE_SIZE: i32 = 32768;
```

### 6.3 移除未使用变量

根据分析报告清理：
- `checker/check_expr.uya` 第 1259 行：`match_union_decl`
- `codegen/c99/stmt.uya` 第 504 行：`ret_c` 部分分支

---

## 实施计划

### 第一周：阶段一 + 阶段三.1

| 天数 | 任务 |
|------|------|
| Day 1 | 添加 Type 辅助函数，替换重复代码 |
| Day 2-3 | 拆分 `checker_infer_type` |
| Day 4-5 | 拆分 `gen_stmt` |

### 第二周：阶段一.3 + 阶段二

| 天数 | 任务 |
|------|------|
| Day 1-2 | 拆分 `gen_expr` |
| Day 3-4 | 降低嵌套深度（提前返回，for 范围迭代） |
| Day 5 | 提取辅助函数 |

### 第三周：阶段三 + 阶段四.1

| 天数 | 任务 |
|------|------|
| Day 1-2 | 提取代码生成辅助函数 |
| Day 3 | 统一类型检查函数调用 |
| Day 4-5 | Type 结构体 Union 化 |

### 第四周：阶段四.2

| 天数 | 任务 |
|------|------|
| Day 1-3 | ASTNode 结构体 Union 化 |
| Day 4-5 | 用 match 替换条件链 |

### 第五周：阶段五 + 阶段六

| 天数 | 任务 |
|------|------|
| Day 1-2 | 重构测试为 test 语句风格 |
| Day 3 | 添加增量测试验证 |
| Day 4 | 统一错误处理模式，常量集中定义 |
| Day 5 | 清理未使用变量 |

### 第六周：验收

| 天数 | 任务 |
|------|------|
| Day 1-2 | 全面测试验证 |
| Day 3-4 | 文档更新 |
| Day 5 | 提交验收 |

---

## 验收标准

### 代码规范
- [ ] 所有函数 ≤ 50 行
- [ ] 所有嵌套深度 ≤ 3 层
- [ ] 重复代码减少 50%+
- [ ] 测试使用 `test "name" {}` 风格

### Union 使用
- [ ] Type 结构体使用 union 封装变体数据
- [ ] ASTNode 结构体使用 union 封装变体数据
- [ ] 条件链替换为 match 表达式（减少 50%+）
- [ ] match 完备性检查通过

### 功能验证
- [ ] `make check` 通过（自举 + 测试）
- [ ] 自举编译时间 ≤ 2s
- [ ] 无新增编译警告
| Day 5 | 添加增量测试验证 |

### 第五周：阶段六 + 验收

| 天数 | 任务 |
|------|------|
| Day 1-2 | 统一错误处理模式 |
| Day 3 | 常量集中定义，清理未使用变量 |
| Day 4 | 全面测试验证 |
| Day 5 | 文档更新，提交验收 |

---

## 验收标准

### 代码规范
- [ ] 所有函数 ≤ 50 行
- [ ] 所有嵌套深度 ≤ 3 层
- [ ] 重复代码减少 50%+
- [ ] 测试使用 `test "name" {}` 风格

### Match 表达式优化
- [ ] Type 条件链替换为 match 表达式（139+ 处）
- [ ] ASTNode 条件链替换为 match 表达式（564+ 处）
- [ ] match 完备性检查通过

### 功能验证
- [ ] `make check` 通过（自举 + 测试）
- [ ] 自举编译时间 ≤ 2s
- [ ] 无新增编译警告

### 文档更新
- [ ] 更新 `.codebuddy/skills/uya-development.md`
- [ ] 更新 `CHANGELOG.md`

---

## 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| 自举验证失败 | 中 | 高 | 每次小改动后立即验证 |
| 引入新 bug | 中 | 高 | 保持测试覆盖，增量提交 |
| 工作量超预期 | 低 | 中 | 优先处理高优先级任务 |

---

## 参考资料

- `.codebuddy/skills/uya-development.md` - Uya 开发技能文档
- `docs/uya_ai_prompt.md` - Uya 语言完整语法（v0.47）
- `.codebuddy/rules/uya-dev-flow.mdc` - Uya 开发流程规则
