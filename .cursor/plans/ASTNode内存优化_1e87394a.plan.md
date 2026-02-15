---
name: ASTNode 内存优化
overview: ASTNode 当前使用 flat struct（约 1432 字节），而 C 版本使用 union（约 72 字节），大小比约 20x。本计划使用 Uya 原生 union 类型重构 ASTNode，将内存占用降低到接近 C 版本水平。
todos: []
isProject: false
---

# ASTNode 内存优化计划

## 问题分析

### 当前状态

| 指标 | C 编译器 | 自举编译器 | 倍数 |
|------|----------|------------|------|
| ASTNode 大小 | ~72 字节 | ~1432 字节 | **~20x** |
| 核心原因 | 使用 `union` 复用内存 | flat struct 包含所有字段 |

### 根因分析

**C 版本（union）**：
```c
typedef struct ASTNode {
    int type;
    int line;
    int column;
    const char *filename;
    union {
        struct { /* binary expr */ } binary;
        struct { /* function call */ } call;
        struct { /* if stmt */ } if_stmt;
        // ... 每种节点类型
    } data;
} ASTNode;
```

**当前 Uya 版本（flat struct）**：
```uya
// ast.uya 注释错误：Uya 实际上有 union！
struct ASTNode {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    // 所有节点类型的字段平铺 → 约 150 个字段！
}
```

### 内存影响估算

| 阶段 | 节点数（估算） | C 版本内存 | 当前 Uya 内存 |
|------|---------------|------------|---------------|
| 单文件解析 | ~50,000 | ~3.5 MB | ~70 MB |
| 32 文件自举 | ~1,600,000 | ~110 MB | ~2.2 GB |

---

## 优化策略：使用 Uya 原生 union

**关键发现**：Uya 语言规范 §4.5 支持编译期类型安全的联合体（union）：

```uya
union IntOrFloat {
    i: i32,
    f: f64
}
```

这是 **tagged union**，与 C union 内存布局兼容，可以完美解决 ASTNode 问题！

### 设计方案

```uya
// 声明节点联合体（声明类节点）
union ASTDeclData {
    program: ASTProgramDecl,
    enum_decl: ASTEnumDecl,
    error_decl: ASTErrorDecl,
    interface_decl: ASTInterfaceDecl,
    struct_decl: ASTStructDecl,
    union_decl: ASTUnionDeclDecl,
    method_block: ASTMethodBlock,
    fn_decl: ASTFnDecl,
    macro_decl: ASTMacroDecl,
    type_alias: ASTTypeAlias,
    var_decl: ASTVarDecl,
    extern_var_decl: ASTExternVarDecl,
    destructure_decl: ASTDestructureDecl,
    use_stmt: ASTUseStmt,
}

// 表达式节点联合体
union ASTExprData {
    binary: ASTBinaryExpr,
    unary: ASTUnaryExpr,
    call: ASTCallExpr,
    member_access: ASTMemberAccess,
    array_access: ASTArrayAccess,
    slice: ASTSliceExpr,
    struct_init: ASTStructInit,
    array_literal: ASTArrayLiteral,
    tuple_literal: ASTTupleLiteral,
    cast: ASTCastExpr,
    identifier: ASTIdentifier,
    number: ASTNumber,
    float_literal: ASTFloatLiteral,
    bool_literal: ASTBoolLiteral,
    string_literal: ASTStringLiteral,
    string_interp: ASTStringInterp,
    try_expr: ASTTryExpr,
    catch_expr: ASTCatchExpr,
    error_value: ASTErrorValue,
    match_expr: ASTMatchExpr,
    await_expr: ASTAwaitExpr,
    // ... 其他表达式
}

// 语句节点联合体
union ASTStmtData {
    if_stmt: ASTIfStmt,
    while_stmt: ASTWhileStmt,
    for_stmt: ASTForStmt,
    break_stmt: ASTBreakStmt,
    continue_stmt: ASTContinueStmt,
    return_stmt: ASTReturnStmt,
    defer_stmt: ASTDeferStmt,
    errdefer_stmt: ASTErrdeferStmt,
    test_stmt: ASTTestStmt,
    assign: ASTAssign,
    block: ASTBlock,
    expr_stmt: ASTExprStmt,
}

// 类型节点联合体
union ASTTypeData {
    named: ASTTypeNamed,
    pointer: ASTTypePointer,
    array: ASTTypeArray,
    slice: ASTTypeSlice,
    tuple: ASTTypeTuple,
    error_union: ASTTypeErrorUnion,
    atomic: ASTTypeAtomic,
}

// 内置函数联合体
union ASTBuiltinData {
    sizeof_expr: ASTSizeofExpr,
    len_expr: ASTLenExpr,
    alignof_expr: ASTAlignofExpr,
    syscall: ASTSyscall,
    va_start: ASTVaStart,
    va_end: ASTVaEnd,
    va_arg: ASTVaArg,
    mc_eval: ASTMcEval,
    mc_code: ASTMcCode,
    mc_ast: ASTMcAst,
    mc_error: ASTMcError,
    mc_interp: ASTMcInterp,
    mc_type: ASTMcType,
    src_info: ASTSrcInfo,
    ptr_conv: ASTPtrConv,
}

// 顶层节点联合体
union ASTNodeData {
    decl: ASTDeclData,
    expr: ASTExprData,
    stmt: ASTStmtData,
    type_node: ASTTypeData,
    builtin: ASTBuiltinData,
}

// 最终 ASTNode 结构
struct ASTNode {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    data: ASTNodeData,  // union，大小 = 最大变体大小
}
```

### 内存对比

| 方面 | 当前 flat struct | 使用 union 后 | 减少 |
|------|------------------|---------------|------|
| ASTNode 大小 | ~1432 字节 | ~72 字节 | **95%** |
| 单文件内存 | ~70 MB | ~3.5 MB | **95%** |
| 自举内存 | ~2.2 GB | ~110 MB | **95%** |
| arena_buffer | 256 MB | ~32 MB | **87%** |

### 预期效果

- **内存减少 95%**：与 C 版本持平
- **arena_buffer**：可从 256 MB 降到 32 MB
- **总内存**：320 MB → ~64 MB（与 C 版本一致）
- **编译速度**：更快（缓存友好）

---

## 实现计划

### 阶段 1：设计 union 结构（1-2 天）

1. **定义节点分类**
   - 声明节点（Decl）：program, enum, error, interface, struct, union, fn, var, etc.
   - 表达式节点（Expr）：binary, unary, call, identifier, literal, etc.
   - 语句节点（Stmt）：if, while, for, return, defer, etc.
   - 类型节点（Type）：named, pointer, array, slice, etc.
   - 内置函数（Builtin）：sizeof, len, syscall, va_*, mc_*, etc.

2. **设计 union 层次结构**
   ```uya
   union ASTNodeData {
       decl: ASTDeclData,
       expr: ASTExprData,
       stmt: ASTStmtData,
       type_node: ASTTypeData,
       builtin: ASTBuiltinData,
   }
   ```

3. **验证 union 语法**
   - 确保 Uya 编译器支持 union 嵌套
   - 测试 match 表达式访问

### 阶段 2：定义结构体和 union（2-3 天）

1. **创建每个变体结构体**
   ```uya
   // 表达式变体
   struct ASTBinaryExpr {
       left: &ASTNode,
       op: i32,
       right: &ASTNode,
   }
   struct ASTCallExpr {
       callee: &ASTNode,
       args: &&ASTNode,
       arg_count: i32,
       // ...
   }
   // ... 其他变体
   ```

2. **创建 union 声明**
   ```uya
   union ASTExprData {
       binary: ASTBinaryExpr,
       call: ASTCallExpr,
       // ... 所有表达式变体
   }
   ```

3. **重构 ASTNode**
   ```uya
   struct ASTNode {
       type: ASTNodeType,
       line: i32,
       column: i32,
       filename: &byte,
       data: ASTNodeData,
   }
   ```

### 阶段 3：迁移 Parser（3-4 天）

1. **修改 ast_new_node**
   - 创建节点后初始化 data 联合体
   - 根据节点类型设置正确的变体

2. **修改每个 parse_* 函数**
   ```uya
   // 原来
   node.binary_expr_left = left;
   node.binary_expr_op = op;
   node.binary_expr_right = right;
   
   // 改为
   node.data.expr.binary.left = left;
   node.data.expr.binary.op = op;
   node.data.expr.binary.right = right;
   ```

3. **验证**
   - 编译通过
   - 测试通过

### 阶段 4：迁移 Checker 和 Codegen（4-5 天）

1. **修改所有节点访问**
   ```uya
   // 原来
   if node.type == AST_BINARY_EXPR {
       left = node.binary_expr_left;
   }
   
   // 改为
   if node.type == AST_BINARY_EXPR {
       left = node.data.expr.binary.left;
   }
   ```

2. **或使用 match 表达式（更优雅）**
   ```uya
   match node.data {
       .expr(e) => {
           match e {
               .binary(b) => {
                   left = b.left;
               },
               .call(c) => {
                   // ...
               },
               // ...
           }
       },
       .decl(d) => { /* ... */ },
       // ...
   }
   ```

3. **验证自举对比**
   - `make b` 通过
   - `make tests-uya` 通过

### 阶段 5：内存验证与调优（1-2 天）

1. **缩减 arena_buffer**
   - 从 256 MB 逐步降到 32 MB
   - 验证自举通过

2. **性能测试**
   - 编译时间
   - 内存峰值

---

## 关键文件

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `src/ast.uya` | 大 | 定义 union 和所有变体结构体 |
| `src/parser.uya` | 大 | 修改所有 parse_* 函数 |
| `src/checker.uya` | 大 | 修改所有节点访问 |
| `src/codegen/*.uya` | 大 | 修改所有节点访问 |
| `src/main.uya` | 小 | 缩减 ARENA_BUFFER_SIZE |

---

## 风险与缓解

### 风险 1：union 嵌套支持

**问题**：Uya 编译器是否支持 union 嵌套？

**缓解**：
- 先验证 union 嵌套语法
- 如不支持，可将所有变体平铺到单一 union

### 风险 2：match 表达式复杂度

**问题**：使用 match 访问节点可能导致代码冗长

**缓解**：
- 创建辅助函数简化常见访问
- 如 `get_binary_left(node)` 等

### 风险 3：自举对比失败

**问题**：节点字段顺序变化可能影响 C 输出

**缓解**：
- 保持字段名称不变
- 输出 C 时按字段名排序
- 每批迁移后验证 `make b`

---

## 预期收益

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| ASTNode 大小 | 1432 字节 | ~72 字节 | **95%** |
| arena_buffer | 256 MB | ~32 MB | **87%** |
| temp_arena_buffer | 64 MB | ~32 MB | **50%** |
| **总内存** | **320 MB** | **~64 MB** | **80%** |
| 编译速度 | 基准 | 更快 | 缓存友好 |

---

## 时间估算

| 阶段 | 时间 |
|------|------|
| 阶段 1：设计 union 结构 | 1-2 天 |
| 阶段 2：定义结构体和 union | 2-3 天 |
| 阶段 3：迁移 Parser | 3-4 天 |
| 阶段 4：迁移 Checker/Codegen | 4-5 天 |
| 阶段 5：内存验证与调优 | 1-2 天 |
| **总计** | **11-16 天** |

---

## 下一步

1. 验证 Uya 编译器对 union 嵌套的支持
2. 创建简单的原型测试
3. 开始阶段 1 设计
