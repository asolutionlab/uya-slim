# @asm 内置函数实施计划

**版本**：v1.0.0
**创建日期**：2026-02-22
**预计完成时间**：2026-03-15（3周）
**优先级**：P0（核心功能）

---

## 1. 实施阶段

### 阶段 1：基础架构（第1周，3-5天）

**目标**：建立 @asm 的基础语法和类型系统

**任务清单**：

#### Day 1-2：语法和 AST
- [ ] Lexer 支持 `@asm` 关键字
- [ ] AST 添加 `AST_ASM` 节点
- [ ] Parser 实现基础语法解析

#### Day 3-4：类型检查
- [ ] Checker 实现基础类型检查
- [ ] 寄存器类型系统
- [ ] 内存操作类型系统

#### Day 5：基础代码生成
- [ ] Codegen 实现简单指令生成
- [ ] 寄存器分配基础实现

**交付物**：
- 可以编译简单的 `@asm` 块
- 生成对应的 C99 内联汇编
- 基础测试用例通过

---

### 阶段 2：核心功能（第2周，5-7天）

**目标**：完善类型安全、内存安全和并发安全机制

**任务清单**：

#### Day 6-7：类型安全增强
- [ ] 完善输入/输出类型检查
- [ ] 寄存器约束验证
- [ ] 占位符类型推断

#### Day 8-9：内存安全验证
- [ ] 指针类型安全检查
- [ ] 内存操作类型验证
- [ ] 越界访问检测（编译期可证明时）

#### Day 10-11：并发安全验证
- [ ] 原子操作类型检查
- [ ] 数据竞争检测
- [ ] 内存屏障指令验证

#### Day 12：平台抽象
- [ ] 平台检测实现
- [ ] 条件编译支持
- [ ] 平台特定寄存器类型

**交付物**：
- 完整的类型安全验证
- 内存安全机制
- 并发安全机制
- 平台抽象基础

---

### 阶段 3：优化和测试（第3周，5-7天）

**目标**：性能优化、跨平台支持、完整测试

**任务清单**：

#### Day 13-14：代码生成优化
- [ ] 编译期常量折叠
- [ ] 指令融合
- [ ] 冗余消除
- [ ] 寄存器重用优化

#### Day 15-16：跨平台支持
- [ ] ARM64 平台支持
- [ ] RISC-V 平台支持（可选）
- [ ] 平台特定优化

#### Day 17-18：完整测试
- [ ] 单元测试完善
- [ ] 集成测试
- [ ] 性能基准测试
- [ ] 跨平台测试

#### Day 19：文档和示例
- [ ] API 文档完善
- [ ] 使用示例
- [ ] 最佳实践指南

**交付物**：
- 优化的代码生成
- 完整的测试套件
- 完善的文档
- 跨平台支持

---

## 2. 详细实现步骤

### 2.1 Lexer 实现（src/lexer.c）

**文件位置**：`compiler-c/src/lexer.c`

**修改点 1**：添加 `@asm` 关键字识别

```c
// 在 is_builtin_function 函数中添加
bool is_builtin_function(const char *name) {
    // ... 现有代码 ...
    if (strcmp(name, "asm") == 0) return true;
    // ... 其他内置函数 ...
}
```

**修改点 2**：添加字符串字面量转义序列支持

```c
// 支持在指令字符串中使用 \n, \t, \\, \" 等转义
static void process_asm_string_escape(char *str) {
    // 实现转义序列处理
}
```

**测试**：
```bash
cd compiler-c
make test_lexer_asm
```

---

### 2.2 AST 实现（src/ast.h, src/ast.c）

**文件位置**：`compiler-c/src/ast.h`, `compiler-c/src/ast.c`

**修改点 1**：添加 AST_ASM 节点类型

```c
// 在 ast.h 中添加
typedef enum {
    // ... 现有节点类型 ...
    AST_ASM,  // 新增：@asm 内置函数
} ASTNodeType;

// 添加 @asm 节点数据结构
typedef struct ASTAsmStmt {
    const char *instruction;  // 指令字符串
    ASTNode **inputs;         // 输入表达式数组
    ASTNode **outputs;        // 输出表达式数组
    int input_count;          // 输入个数
    int output_count;         // 输出个数
} ASTAsmStmt;

// 在 ASTNode 联合中添加
typedef struct ASTNode {
    ASTNodeType type;
    TokenLocation loc;
    union {
        // ... 现有字段 ...
        struct {
            ASTAsmStmt *stmts;    // 语句数组
            int stmt_count;       // 语句个数
            ASTNode **clobbers;   // clobber 寄存器数组
            int clobber_count;    // clobber 个数
            bool clobbers_memory; // 是否修改内存
        } asm;
    } data;
} ASTNode;
```

**修改点 2**：添加 @asm 节点构造函数

```c
// 在 ast.c 中添加
ASTNode *create_asm_node(Arena *arena, TokenLocation loc,
                        ASTAsmStmt *stmts, int stmt_count,
                        ASTNode **clobbers, int clobber_count,
                        bool clobbers_memory) {
    ASTNode *node = arena_alloc(arena, sizeof(ASTNode));
    node->type = AST_ASM;
    node->loc = loc;
    node->data.asm.stmts = stmts;
    node->data.asm.stmt_count = stmt_count;
    node->data.asm.clobbers = clobbers;
    node->data.asm.clobber_count = clobber_count;
    node->data.asm.clobbers_memory = clobbers_memory;
    return node;
}
```

**测试**：
```bash
cd compiler-c
make test_ast_asm
```

---

### 2.3 Parser 实现（src/parser.c）

**文件位置**：`compiler-c/src/parser.c`

**修改点 1**：在 primary_expr 中识别 @asm

```c
static ASTNode *primary_expr(Parser *parser) {
    // ... 现有代码 ...
    
    if (parser->token.type == TOKEN_AT_IDENTIFIER) {
        const char *name = parser->token.value.string;
        
        if (strcmp(name, "asm") == 0) {
            return parse_asm_block(parser);
        }
        
        // ... 其他 @ 内置函数 ...
    }
    
    // ... 其他情况 ...
}
```

**修改点 2**：实现 parse_asm_block 函数

```c
static ASTNode *parse_asm_block(Parser *parser) {
    TokenLocation loc = parser->token.loc;
    
    // 消费 @asm
    expect_token(parser, TOKEN_AT_IDENTIFIER);
    
    // 消费 {
    expect_token(parser, TOKEN_LBRACE);
    
    // 解析语句列表
    Arena *arena = parser->arena;
    int stmt_capacity = 8;
    ASTAsmStmt *stmts = arena_alloc(arena, stmt_capacity * sizeof(ASTAsmStmt));
    int stmt_count = 0;
    
    while (parser->token.type != TOKEN_RBRACE) {
        // 解析指令字符串
        if (parser->token.type != TOKEN_STRING) {
            parser_error(parser, "Expected assembly instruction string");
            return NULL;
        }
        
        const char *instruction = parser->token.value.string;
        consume_token(parser);
        
        // 解析 (inputs, outputs)
        expect_token(parser, TOKEN_LPAREN);
        
        // 解析输入表达式
        ASTNode **inputs = NULL;
        int input_count = 0;
        while (parser->token.type != TOKEN_ARROW && parser->token.type != TOKEN_RPAREN) {
            ASTNode *expr = parse_expr(parser, 0);
            if (!expr) return NULL;
            
            // 添加到 inputs 数组
            if (input_count == 0) {
                inputs = arena_alloc(arena, 8 * sizeof(ASTNode*));
            } else if (input_count % 8 == 0) {
                // 扩容（简化版）
            }
            inputs[input_count++] = expr;
            
            if (parser->token.type == TOKEN_COMMA) {
                consume_token(parser);
            }
        }
        
        // 解析输出表达式
        ASTNode **outputs = NULL;
        int output_count = 0;
        if (parser->token.type == TOKEN_ARROW) {
            consume_token(parser);  // ->
            
            while (parser->token.type != TOKEN_RPAREN) {
                ASTNode *expr = parse_expr(parser, 0);
                if (!expr) return NULL;
                
                // 添加到 outputs 数组
                if (output_count == 0) {
                    outputs = arena_alloc(arena, 8 * sizeof(ASTNode*));
                } else if (output_count % 8 == 0) {
                    // 扩容
                }
                outputs[output_count++] = expr;
                
                if (parser->token.type == TOKEN_COMMA) {
                    consume_token(parser);
                }
            }
        }
        
        expect_token(parser, TOKEN_RPAREN);
        
        // 解析可选的 clobbers
        bool clobbers_memory = false;
        ASTNode **clobbers = NULL;
        int clobber_count = 0;
        
        if (parser->token.type == TOKEN_IDENTIFIER && 
            strcmp(parser->token.value.string, "clobbers") == 0) {
            consume_token(parser);
            expect_token(parser, TOKEN_ASSIGN);
            expect_token(parser, TOKEN_LBRACKET);
            
            while (parser->token.type != TOKEN_RBRACKET) {
                if (parser->token.type == TOKEN_STRING) {
                    if (strcmp(parser->token.value.string, "memory") == 0) {
                        clobbers_memory = true;
                    } else {
                        // 寄存器 clobber
                        ASTNode *reg = parse_expr(parser, 0);
                        if (!reg) return NULL;
                        
                        if (clobber_count == 0) {
                            clobbers = arena_alloc(arena, 8 * sizeof(ASTNode*));
                        }
                        clobbers[clobber_count++] = reg;
                    }
                    consume_token(parser);
                }
                
                if (parser->token.type == TOKEN_COMMA) {
                    consume_token(parser);
                }
            }
            
            expect_token(parser, TOKEN_RBRACKET);
        }
        
        // 添加到语句列表
        if (stmt_count >= stmt_capacity) {
            stmt_capacity *= 2;
            stmts = arena_realloc(arena, stmts, stmt_capacity * sizeof(ASTAsmStmt));
        }
        
        stmts[stmt_count].instruction = instruction;
        stmts[stmt_count].inputs = inputs;
        stmts[stmt_count].outputs = outputs;
        stmts[stmt_count].input_count = input_count;
        stmts[stmt_count].output_count = output_count;
        stmt_count++;
    }
    
    expect_token(parser, TOKEN_RBRACE);
    
    return create_asm_node(parser->arena, loc, stmts, stmt_count,
                          clobbers, clobber_count, clobbers_memory);
}
```

**测试**：
```bash
cd compiler-c
make test_parser_asm
```

---

### 2.4 Checker 实现（src/checker.c）

**文件位置**：`compiler-c/src/checker.c`

**修改点 1**：添加 @asm 类型检查函数

```c
static void check_asm_block(Checker *checker, ASTNode *node) {
    // 遍历所有语句
    for (int i = 0; i < node->data.asm.stmt_count; i++) {
        ASTAsmStmt *stmt = &node->data.asm.stmts[i];
        
        // 检查输入表达式
        for (int j = 0; j < stmt->input_count; j++) {
            ASTNode *input = stmt->inputs[j];
            check_expr(checker, input);
            
            // 验证输入类型
            Type *input_type = get_expr_type(input);
            if (!is_valid_asm_input_type(input_type)) {
                report_error(checker, input->loc,
                           "Invalid input type for assembly instruction: %s",
                           type_to_string(input_type));
            }
        }
        
        // 检查输出表达式
        for (int j = 0; j < stmt->output_count; j++) {
            ASTNode *output = stmt->outputs[j];
            
            // 检查输出是否是左值（可赋值）
            if (!is_lvalue(output)) {
                report_error(checker, output->loc,
                           "Output expression must be an lvalue");
                continue;
            }
            
            check_expr(checker, output);
            
            // 验证输出类型
            Type *output_type = get_expr_type(output);
            if (!is_valid_asm_output_type(output_type)) {
                report_error(checker, output->loc,
                           "Invalid output type for assembly instruction: %s",
                           type_to_string(output_type));
            }
        }
    }
    
    // 检查 clobbers
    for (int i = 0; i < node->data.asm.clobber_count; i++) {
        ASTNode *clobber = node->data.asm.clobbers[i];
        check_expr(checker, clobber);
        
        // 验证 clobber 是有效的寄存器类型
        Type *clobber_type = get_expr_type(clobber);
        if (!is_register_type(clobber_type)) {
            report_error(checker, clobber->loc,
                       "Clobber must be a register type");
        }
    }
}
```

**修改点 2**：添加类型验证辅助函数

```c
// 检查是否是有效的 @asm 输入类型
static bool is_valid_asm_input_type(Type *type) {
    // 整数类型
    if (is_integer_type(type)) return true;
    
    // 指针类型
    if (is_pointer_type(type)) return true;
    
    // 寄存器类型
    if (is_register_type(type)) return true;
    
    // 内存操作类型
    if (is_asm_mem_type(type)) return true;
    
    return false;
}

// 检查是否是有效的 @asm 输出类型
static bool is_valid_asm_output_type(Type *type) {
    // 整数类型
    if (is_integer_type(type)) return true;
    
    // 寄存器类型
    if (is_register_type(type)) return true;
    
    return false;
}

// 检查是否是寄存器类型
static bool is_register_type(Type *type) {
    // @asm_reg
    if (type->kind == TYPE_ASM_REG) return true;
    
    // 平台特定寄存器类型
    if (type->kind == TYPE_ASM_REG_X64) return true;
    if (type->kind == TYPE_ASM_REG_X86) return true;
    if (type->kind == TYPE_ASM_REG_ARM64) return true;
    
    return false;
}

// 检查是否是内存操作类型
static bool is_asm_mem_type(Type *type) {
    return type->kind == TYPE_ASM_MEM;
}
```

**修改点 3**：在 check_expr 中添加 @asm 处理

```c
static void check_expr(Checker *checker, ASTNode *node) {
    // ... 现有代码 ...
    
    switch (node->type) {
        // ... 其他情况 ...
        case AST_ASM:
            check_asm_block(checker, node);
            break;
    }
    
    // ... 其他代码 ...
}
```

**测试**：
```bash
cd compiler-c
make test_checker_asm
```

---

### 2.5 Codegen 实现（src/codegen/c99/）

#### 2.5.1 expr.c

**文件位置**：`compiler-c/src/codegen/c99/expr.c`

**修改点 1**：添加 @asm 代码生成函数

```c
void gen_asm_block(CodeGenC99 *gen, ASTNode *node) {
    // 生成临时变量声明
    for (int i = 0; i < node->data.asm.stmt_count; i++) {
        ASTAsmStmt *stmt = &node->data.asm.stmts[i];
        
        // 生成输入临时变量
        for (int j = 0; j < stmt->input_count; j++) {
            ASTNode *input = stmt->inputs[j];
            char *temp_name = gen_asm_temp_var(gen, "input", i, j);
            
            fprintf(gen->output, "register ");
            gen_type(gen, get_expr_type(input));
            fprintf(gen->output, " %s = ", temp_name);
            gen_expr(gen, input);
            fprintf(gen->output, ";\n");
        }
        
        // 生成输出临时变量
        for (int j = 0; j < stmt->output_count; j++) {
            ASTNode *output = stmt->outputs[j];
            char *temp_name = gen_asm_temp_var(gen, "output", i, j);
            
            fprintf(gen->output, "register ");
            gen_type(gen, get_expr_type(output));
            fprintf(gen->output, " %s", temp_name);
            fprintf(gen->output, ";\n");
        }
    }
    
    // 生成内联汇编
    for (int i = 0; i < node->data.asm.stmt_count; i++) {
        ASTAsmStmt *stmt = &node->data.asm.stmts[i];
        
        gen_asm_stmt(gen, stmt, i);
    }
    
    // 将结果复制到输出变量
    for (int i = 0; i < node->data.asm.stmt_count; i++) {
        ASTAsmStmt *stmt = &node->data.asm.stmts[i];
        
        for (int j = 0; j < stmt->output_count; j++) {
            char *temp_name = gen_asm_temp_var(gen, "output", i, j);
            ASTNode *output = stmt->outputs[j];
            
            gen_expr(gen, output);  // 生成左值
            fprintf(gen->output, " = %s;\n", temp_name);
        }
    }
}
```

**修改点 2**：实现 gen_asm_stmt 函数

```c
void gen_asm_stmt(CodeGenC99 *gen, ASTAsmStmt *stmt, int stmt_index) {
    // 构建内联汇编字符串
    fprintf(gen->output, "__asm__ volatile (\n");
    
    // 指令模板
    fprintf(gen->output, "    \"%s\"\n", stmt->instruction);
    
    // 输出操作数
    fprintf(gen->output, "    : ");
    bool first = true;
    for (int j = 0; j < stmt->output_count; j++) {
        if (!first) fprintf(gen->output, ", ");
        char *temp_name = gen_asm_temp_var(gen, "output", stmt_index, j);
        fprintf(gen->output, "\"=r\" (%s)", temp_name);
        first = false;
    }
    fprintf(gen->output, "\n");
    
    // 输入操作数
    fprintf(gen->output, "    : ");
    first = true;
    for (int j = 0; j < stmt->input_count; j++) {
        if (!first) fprintf(gen->output, ", ");
        char *temp_name = gen_asm_temp_var(gen, "input", stmt_index, j);
        fprintf(gen->output, "\"r\" (%s)", temp_name);
        first = false;
    }
    fprintf(gen->output, "\n");
    
    // Clobbers
    fprintf(gen->output, "    : \"memory\"");
    // TODO: 添加寄存器 clobbers
    fprintf(gen->output, "\n);\n");
}
```

**修改点 3**：在 gen_expr 中添加 @asm 处理

```c
void gen_expr(CodeGenC99 *gen, ASTNode *node) {
    // ... 现有代码 ...
    
    switch (node->type) {
        // ... 其他情况 ...
        case AST_ASM:
            gen_asm_block(gen, node);
            break;
    }
    
    // ... 其他代码 ...
}
```

**测试**：
```bash
cd compiler-c
make test_codegen_asm
```

#### 2.5.2 utils.c（新功能）

**文件位置**：`compiler-c/src/codegen/c99/utils.c`

**修改点 1**：添加临时变量生成函数

```c
// 生成 @asm 临时变量名
char *gen_asm_temp_var(CodeGenC99 *gen, const char *prefix, int stmt_index, int var_index) {
    static char buffer[256];
    snprintf(buffer, sizeof(buffer), "_uya_asm_%s_%d_%d", prefix, stmt_index, var_index);
    return buffer;
}
```

#### 2.5.3 platform.c（新文件）

**文件位置**：`compiler-c/src/codegen/c99/platform.c`

**修改点 1**：平台检测

```c
// 获取目标平台
const char *get_target_platform(void) {
#if defined(__x86_64__)
#if defined(__linux__)
    return "x86_64_linux";
#elif defined(__APPLE__)
    return "x86_64_macos";
#elif defined(_WIN32)
    return "x86_64_windows";
#endif
#elif defined(__aarch64__)
#if defined(__linux__)
    return "arm64_linux";
#elif defined(__APPLE__)
    return "arm64_macos";
#elif defined(_WIN32)
    return "arm64_windows";
#endif
#elif defined(__riscv)
    return "riscv64";
#else
    return "unknown";
#endif
}
```

**修改点 2**：寄存器约束映射

```c
// 获取寄存器的 C99 约束字符串
const char *get_register_constraint(const char *reg_name) {
    // x86-64 特定寄存器
    if (strcmp(reg_name, "rax") == 0 || strcmp(reg_name, "eax") == 0) return "a";
    if (strcmp(reg_name, "rbx") == 0 || strcmp(reg_name, "ebx") == 0) return "b";
    if (strcmp(reg_name, "rcx") == 0 || strcmp(reg_name, "ecx") == 0) return "c";
    if (strcmp(reg_name, "rdx") == 0 || strcmp(reg_name, "edx") == 0) return "d";
    if (strcmp(reg_name, "rsi") == 0 || strcmp(reg_name, "esi") == 0) return "S";
    if (strcmp(reg_name, "rdi") == 0 || strcmp(reg_name, "edi") == 0) return "D";
    
    // ARM64 特定寄存器
    if (strcmp(reg_name, "x0") == 0) return "r";
    // ... 其他 ARM64 寄存器
    
    // 通用寄存器
    return "r";
}
```

---

## 3. 测试用例实现

### 3.1 基础功能测试

**文件位置**：`tests/programs/test_asm_basic.uya`

```uya
test "asm basic addition" {
    fn add_asm(a: i32, b: i32) i32 {
        var result: i32;
        
        @asm {
            "add {a}, {b}" (a, b, -> result);
        }
        
        return result;
    }
    
    const x: i32 = 10;
    const y: i32 = 20;
    const z: i32 = add_asm(x, y);
    
    if z != 30 {
        return error.TestFailed;
    }
    
    return true;
}

test "asm multiplication" {
    fn mul_asm(a: i32, b: i32) i32 {
        var result: i32;
        
        @asm {
            "imul {a}, {b}" (a, b, -> result);
        }
        
        return result;
    }
    
    const x: i32 = 5;
    const y: i32 = 6;
    const z: i32 = mul_asm(x, y);
    
    if z != 30 {
        return error.TestFailed;
    }
    
    return true;
}
```

### 3.2 系统调用测试

**文件位置**：`tests/programs/test_asm_syscall.uya`

```uya
test "asm syscall write" {
    const SYS_write: i64 = 1;
    const msg = "Hello from @asm!\n";

    var result: i64;  // 显式声明输出变量
    
    @asm {
        "mov rax, {nr}" (SYS_write, -> rax);
        "mov rdi, 1" (-> rdi);
        "mov rsi, {msg}" (msg, -> rsi);
        "mov rdx, 17" (-> rdx);
        "syscall" (rax, rdi, rsi, rdx, -> result);
    } clobbers = ["rcx", "r11", "memory"];
    
    if result != 17 {
        return error.TestFailed;
    }
    
    return true;
}

test "asm syscall exit" {
    const SYS_exit: i64 = 60;
    
    @asm {
        "mov rax, {nr}" (SYS_exit, -> rax);
        "mov rdi, 42" (-> rdi);
        "syscall" (rax, rdi, -> _);
    } clobbers = ["rcx", "r11"];
    
    return true;
}
```

### 3.3 类型安全测试

**文件位置**：`tests/programs/error_asm_type_mismatch.uya`

```uya
// 这个测试应该编译失败

fn add_wrong_types(a: i32, b: f64) i32 {
    var result: i32;
    
    @asm {
        "add {a}, {b}" (a, b, -> result);  // 类型不匹配，应该编译失败
    }
    
    return result;
}
```

### 3.4 内存安全测试

**文件位置**：`tests/programs/test_asm_memory_safe.uya`

```uya
test "asm memory read" {
    fn read_u32(ptr: &u32) u32 {
        var value: u32;
        
        @asm {
            "mov {value}, [{ptr}]" (@asm_mem(ptr), -> value);
        }
        
        return value;
    }
    
    const data: u32 = 0xDEADBEEF;
    const result: u32 = read_u32(&data);
    
    if result != 0xDEADBEEF {
        return error.TestFailed;
    }
    
    return true;
}

test "asm memory write" {
    fn write_u32(ptr: &u32, value: u32) void {
        @asm {
            "mov [{ptr}], {value}" (value, @asm_mem(ptr), -> _);
        }
    }
    
    var data: u32 = 0;
    write_u32(&data, 0xCAFEBABE);
    
    if data != 0xCAFEBABE {
        return error.TestFailed;
    }
    
    return true;
}
```

### 3.5 并发安全测试

**文件位置**：`tests/programs/test_asm_atomic_ops.uya`

```uya
test "asm atomic fetch_add" {
    fn atomic_fetch_add(ptr: &atomic i32, value: i32) i32 {
        var old: i32;
        
        @asm {
            "lock xadd {ptr}, {value}" (@asm_mem(ptr), value, -> old);
        }
        
        return old;
    }
    
    var counter: atomic i32 = 0;
    const old: i32 = atomic_fetch_add(&counter, 5);
    
    if old != 0 {
        return error.TestFailed;
    }
    
    if counter != 5 {
        return error.TestFailed;
    }
    
    return true;
}

test "asm atomic compare_exchange" {
    fn atomic_compare_exchange(ptr: &atomic i32, expected: i32, desired: i32) bool {
        var prev: i32;
        
        @asm {
            "lock cmpxchg [{ptr}], {desired}" (
                @asm_mem(ptr), desired, -> prev
            );
        }
        
        return prev == expected;
    }
    
    var value: atomic i32 = 10;
    const success: bool = atomic_compare_exchange(&value, 10, 20);
    
    if !success {
        return error.TestFailed;
    }
    
    if value != 20 {
        return error.TestFailed;
    }
    
    return true;
}
```

### 3.6 平台检测测试

**文件位置**：`tests/programs/test_asm_platform.uya`

```uya
test "asm platform detection" {
    const target: @asm_target = @asm_target();
    
    if @asm_target() == .x86_64_linux {
        return true;
    } else if @asm_target() == .arm64_linux {
        return true;
    }
    
    return error.TestFailed;
}

test "asm platform specific code" {
    var result: i32;
    
    if @asm_target() == .x86_64_linux {
        @asm {
            "mov {result}, 42" (-> result);
        }
    } else if @asm_target() == .arm64_linux {
        @asm {
            "mov {result}, #42" (-> result);
        }
    } else {
        return error.UnsupportedPlatform;
    }
    
    if result != 42 {
        return error.TestFailed;
    }
    
    return true;
}
```

---

## 4. 集成和测试流程

### 4.1 编译和测试

```bash
# 编译编译器
cd compiler-c
make clean
make build

# 运行基础测试
./build/compiler-mini --c99 ../tests/programs/test_asm_basic.uya
gcc ../tests/programs/build/test_asm_basic.c -o test_asm_basic
./test_asm_basic

# 运行所有 @asm 测试
./scripts/run_asm_tests.sh

# 性能基准测试
./scripts/bench_asm.sh
```

### 4.2 调试

```bash
# 启用详细输出
./build/compiler-mini --c99 --verbose ../tests/programs/test_asm_basic.uya

# 查看生成的 C 代码
cat ../tests/programs/build/test_asm_basic.c

# 使用 GDB 调试
gdb ./test_asm_basic
```

---

## 5. 验收标准

### 5.1 功能完整性

- [ ] 所有基础功能测试通过
- [ ] 所有类型安全测试通过
- [ ] 所有内存安全测试通过
- [ ] 所有并发安全测试通过
- [ ] 所有平台检测测试通过

### 5.2 性能指标

- [ ] @asm 生成的代码与 C99 内联汇编性能一致（误差 < 1%）
- [ ] 编译时间增加 < 5%
- [ ] 生成的代码大小增加 < 2%

### 5.3 代码质量

- [ ] 代码覆盖率 > 90%
- [ ] 无内存泄漏
- [ ] 无编译警告
- [ ] 符合代码规范

---

## 6. 风险和应对

### 6.1 技术风险

**风险 1**：寄存器分配复杂度高

**应对**：
- 初期使用 GCC/Clang 的自动分配（`"r"` 约束）
- 后期优化显式寄存器指定

**风险 2**：跨平台支持困难

**应对**：
- 先实现 x86-64 Linux 平台
- 后续逐步支持其他平台
- 使用条件编译隔离平台特定代码

**风险 3**：性能不如预期

**应对**：
- 提前进行性能基准测试
- 根据测试结果优化代码生成
- 确保零成本抽象

### 6.2 进度风险

**风险 1**：实现时间超出预期

**应对**：
- 按优先级分阶段实施
- 核心功能优先
- 非关键功能可以延后

**风险 2**：测试用例不足

**应对**：
- 边开发边测试
- 增加测试覆盖率
- 使用模糊测试工具

---

## 7. 后续优化方向

### 7.1 性能优化

- 指令级优化
- 寄存器重用
- 常量传播
- 死代码消除

### 7.2 功能扩展

- SIMD 抽象
- 标签跳转
- 内联函数
- 宏支持

### 7.3 工具支持

- 语法高亮
- 自动补全
- 错误提示优化
- 调试信息

---

## 8. 总结

本实施计划详细描述了 @asm 内置函数的实现步骤，包括：

1. **阶段划分**：3周3个阶段，逐步实现
2. **详细步骤**：每个文件的修改点和代码示例
3. **测试用例**：完整的测试套件
4. **验收标准**：明确的功能、性能、质量标准
5. **风险应对**：识别风险并提供应对方案

**预期成果**：

- 完整的 @asm 内置函数实现
- 类型安全、内存安全、并发安全
- 跨平台支持
- 零成本抽象
- 完善的测试和文档

---

**文档版本**：v1.0.0
**最后更新**：2026-02-22
**下次审查**：每周五
