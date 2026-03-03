# Naked 函数设计计划

## 1. 背景

### 问题
在实现 `setjmp/longjmp` 时发现，GCC 会为函数自动生成 prologue/epilogue（如 `push rbp; mov rbp, rsp`），导致：
- `longjmp` 恢复 `rsp` 后，栈上变量失效
- 无法实现完整的非本地跳转

### 目标
实现 `@naked` 函数属性，让编译器生成 `__attribute__((naked))` 声明，禁止 GCC 生成 prologue/epilogue。

## 2. 技术方案

### 2.1 语法设计

```uya
// 函数声明/定义（与 @async_fn 命名风格一致）
@naked_fn fn longjmp(env: &jmp_buf, val: i32) void {
    @asm {
        "mov rbx, %0" (env.data[0] ->);
        "mov rbp, %0" (env.data[1] ->);
        // ... 恢复所有寄存器
        "jmp *%0" (env.data[7] ->);
    } clobbers = ["memory"];
}

// 与其他属性组合
export @naked_fn fn handler() void { ... }
```

**命名原因**：使用 `_fn` 后缀与现有 `@async_fn` 保持一致。

### 2.2 语义约束

| 约束 | 原因 |
|------|------|
| 函数体只能包含 `@asm` 块 | naked 函数没有栈帧，无法访问局部变量 |
| 不能有参数（或参数只能通过寄存器传递） | x86-64 调用约定中参数在栈上 |
| 不能调用其他函数 | 没有栈帧保护 |
| 不能有返回语句 | 由汇编直接控制 |

### 2.3 生成代码示例

```c
// Uya 源码
@naked_fn fn longjmp(env: &jmp_buf, val: i32) void { ... }

// 生成的 C 代码
__attribute__((naked)) void longjmp(jmp_buf* env, int32_t val) {
    __asm__ volatile (
        "mov rbx, %0\n\t"
        "mov rbp, %1\n\t"
        // ...
        : : "r"(env->data[0]), "r"(env->data[1]) : "memory"
    );
}
```

## 3. 实现步骤

### 3.1 AST 修改 (`src/ast.uya`)

```diff
    fn_decl_is_async: i32,   // 1 表示 @async_fn，0 表示普通函数
+   fn_decl_is_naked: i32,   // 1 表示 @naked_fn，0 表示普通函数
    fn_decl_extern_lib_name: &byte,
```

```diff
    node.fn_decl_is_async = 0;
+   node.fn_decl_is_naked = 0;
    node.fn_decl_extern_lib_name = null;
```

### 3.2 Parser 修改 (`src/parser/main.uya`)

```diff
    // 检查 @async_fn 函数属性
    var is_async: i32 = 0;
+   var is_naked: i32 = 0;
    
    if parser.current_token != null && parser.current_token.type == TokenType.TOKEN_AT_IDENTIFIER {
-       if parser.current_token.value != null && str_equals_lexer(parser.current_token.value, "async_fn" as &byte) != 0 {
-           is_async = 1;
-           parser_consume(parser);
-       }
+       if parser.current_token.value != null {
+           if str_equals_lexer(parser.current_token.value, "async_fn" as &byte) != 0 {
+               is_async = 1;
+               parser_consume(parser);
+           } else if str_equals_lexer(parser.current_token.value, "naked_fn" as &byte) != 0 {
+               is_naked = 1;
+               parser_consume(parser);
+           }
+       }
    }
    
    // ...
    
    if decl != null {
        if is_export != 0 { decl.fn_decl_is_export = 1; }
        if is_async != 0 { decl.fn_decl_is_async = 1; }
+       if is_naked != 0 { decl.fn_decl_is_naked = 1; }
    }
```

### 3.3 代码生成修改 (`src/codegen/c99/function.uya`)

```diff
    // 非 extern 函数：根据 is_export 决定是否添加 static
+   // @naked_fn 函数添加 __attribute__((naked))
+   if fn_decl.fn_decl_is_naked != 0 {
+       fprintf(codegen.output, "__attribute__((naked)) " as *byte);
+   }
    if is_static != 0 {
        fprintf(codegen.output, "static __attribute__((unused)) " as *byte);
    }
    fprintf(codegen.output, "%s %s(" as *byte, return_c as *byte, func_name as *byte);
```

### 3.4 测试文件 (`tests/test_naked.uya`)

```uya
// 简单的 naked 函数测试
test "naked_function_declaration" {
    // 仅验证编译通过
}

// 实际使用示例（需要验证生成的 C 代码）
@naked_fn fn naked_test() void {
    @asm {
        "ret" ();
    } clobbers = [];
}
```

## 4. 验证流程

```bash
# 1. 修改代码后构建
make uya

# 2. 验证自举
make b

# 3. 运行测试
make tests

# 4. 检查生成的 C 代码
cat bin/uya.c | grep -A5 "naked"
```

## 5. 风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| GCC 版本兼容性 | 旧版 GCC 可能不支持 | 文档说明最低 GCC 版本要求 |
| 调试困难 | naked 函数无栈帧 | 限制使用场景，提供警告 |
| 误用导致崩溃 | 用户在 naked 函数中使用局部变量 | 添加编译时检查（可选） |

## 6. 后续优化

1. **编译时检查**：验证 naked 函数体只包含 `@asm` 块
2. **参数限制**：禁止 naked 函数有栈上参数
3. **警告系统**：对危险用法发出警告

## 7. 文件清单

| 文件 | 修改内容 |
|------|----------|
| `src/ast.uya` | 添加 `fn_decl_is_naked` 字段 |
| `src/parser/main.uya` | 解析 `@naked` 属性 |
| `src/codegen/c99/function.uya` | 生成 `__attribute__((naked))` |
| `tests/test_naked.uya` | 新增测试文件 |
