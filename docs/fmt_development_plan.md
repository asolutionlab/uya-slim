# Uya 代码格式化器 (fmt) 开发计划

> 参考 Go `go/format` + `go/printer` + `gofmt` 实现

**版本**: v0.1.1
**更新日期**: 2026-03-29

---

## 概述

### 目标

为 Uya 实现类似 Go `gofmt` 的代码格式化工具，使 Uya 代码风格统一、可读性增强。

### 核心原理

解析源码 → AST → 重新打印（应用格式化规则）

### 项目集成

- 遵循 TDD 开发流程（`make tests` 验证）
- 测试文件放在 `tests/test_fmt_*.uya`
- 库文件放在 `lib/std/fmt/`

---

## 架构说明

### 设计决策：自包含的格式化器

由于编译器的 `Parser`（位于 `src/parser/`）是编译器内部使用的组件，外部库无法直接调用。因此 fmt 库采用**自包含设计**：

1. **Phase 1.1-1.3**：Formatter 和 Printer 独立工作，接收手动构造的 AST 节点
2. **Phase 1.2**：实现**手写 tokenizer**（参考 JSON parser 的词法分析方式），而非依赖编译器 Lexer
3. **Phase 3**：提供可选的"完整格式化"入口，需要 fmt 库内置解析器

这种设计确保 fmt 库可以独立测试和使用，不依赖编译器内部实现。

---

## 文件结构

```
lib/std/fmt/
├── fmt.uya              # 主入口和公开 API
├── formatter.uya        # Formatter 结构体
├── printer.uya          # AST 打印机
├── tokenizer.uya        # 手写 Token 解析器
├── rules.uya            # 格式化规则定义
├── comments.uya         # 注释处理
└── import_sort.uya      # Import 排序

tests/
├── test_fmt_formatter.uya    # Formatter 基础功能
├── test_fmt_tokenizer.uya     # Tokenizer 功能
├── test_fmt_printer.uya      # AST 打印功能
├── test_fmt_expr.uya         # 表达式格式化
├── test_fmt_stmt.uya         # 语句格式化
├── test_fmt_decl.uya         # 声明格式化
├── test_fmt_comments.uya     # 注释处理
├── test_fmt_import_sort.uya  # Import 排序
└── test_fmt_idempotent.uya   # 往返一致性测试

tools/
└── fmt.uya              # CLI 工具（Phase 4）
```

---

## 依赖关系

```
lib/std/fmt/
    ├── formatter.uya      # 无依赖，基础组件
    ├── tokenizer.uya     # 无依赖，手写词法分析
    ├── rules.uya         # 无依赖，格式化规则定义
    ├── printer.uya       # 依赖 formatter, rules
    ├── comments.uya      # 依赖 formatter
    ├── import_sort.uya   # 依赖 formatter
    └── fmt.uya           # 依赖以上所有

tools/fmt.uya
    └── 依赖 lib/std/fmt/*
```

---

## 阶段一：基础格式化引擎

### 1.1 核心数据结构 (formatter.uya)

**任务**: 创建格式化器核心结构

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 1.1.1 | 创建 `lib/std/fmt/formatter.uya` | 文件存在，编译器能解析 |
| 1.1.2 | 定义 `Formatter` 结构体 | 包含 buf, pos, indent, line 字段 |
| 1.1.3 | 实现 `formatter_init()` | 初始化函数可用 |
| 1.1.4 | 实现 `formatter_write()` | 能写入字符串并追踪位置 |
| 1.1.5 | 实现 `formatter_indent()` / `formatter_dedent()` | 缩进增减正确 |

**代码设计**:

```uya
// lib/std/fmt/formatter.uya
export struct Formatter {
    buf: &byte,        // 输出缓冲区
    cap: usize,        // 缓冲区容量
    pos: usize,        // 当前写入位置
    indent: usize,     // 当前缩进级别
    line: usize,      // 当前行号
    at_line_start: bool,  // 是否在行首
}

export fn formatter_init(f: &Formatter, buf: &byte, cap: usize) void {
    f.buf = buf;
    f.cap = cap;
    f.pos = 0;
    f.indent = 0;
    f.line = 1;
    f.at_line_start = true;
}

export fn formatter_write(f: &Formatter, s: &[byte]) !void {
    if f.pos + s.len > f.cap {
        return error.BufferTooSmall;
    }
    var i: usize = 0;
    while i < s.len {
        f.buf[f.pos] = s[i];
        f.pos = f.pos + 1;
        if s[i] == '\n' as byte {
            f.line = f.line + 1;
            f.at_line_start = true;
        } else {
            f.at_line_start = false;
        }
        i = i + 1;
    }
}

export fn formatter_write_byte(f: &Formatter, b: byte) !void {
    if f.pos >= f.cap {
        return error.BufferTooSmall;
    }
    f.buf[f.pos] = b;
    f.pos = f.pos + 1;
    if b == '\n' as byte {
        f.line = f.line + 1;
        f.at_line_start = true;
    } else {
        f.at_line_start = false;
    }
}

export fn formatter_indent(f: &Formatter) void {
    f.indent = f.indent + 1;
}

export fn formatter_dedent(f: &Formatter) void {
    if f.indent > 0 {
        f.indent = f.indent - 1;
    }
}

export fn formatter_write_indent(f: &Formatter) !void {
    var i: usize = 0;
    while i < f.indent {
        try formatter_write_byte(f, '\t' as byte);
        i = i + 1;
    }
}
```

**测试用例** (`tests/test_fmt_formatter.uya`):

```uya
// test_fmt_formatter - Formatter 基础功能测试
use std.runtime.entry;
use std.fmt.formatter;
use std.fmt.formatter.Formatter;
use std.fmt.formatter.formatter_init;
use std.fmt.formatter.formatter_write;
use std.fmt.formatter.formatter_indent;
use std.fmt.formatter.formatter_dedent;
use std.fmt.formatter.formatter_write_byte;
use std.fmt.formatter.formatter_write_indent;

export fn main() i32 {
    var buf: [byte: 256] = [];
    var f: Formatter = undefined;
    formatter_init(&f, &buf[0], 256);

    // 测试写入字符串
    try formatter_write(&f, "hello" as &[byte]);
    if f.pos != 5 { return 1; }

    // 测试缩进
    formatter_indent(&f);
    if f.indent != 1 { return 2; }
    formatter_dedent(&f);
    if f.indent != 0 { return 3; }

    // 测试写入字节
    try formatter_write_byte(&f, '\n' as byte);
    if f.line != 2 { return 4; }

    // 测试缩进写入
    formatter_indent(&f);
    try formatter_write_indent(&f);
    if f.pos != 7 { return 5; }  // 5 + 1(\n) + 1(\t)

    return 0;
}
```

---

### 1.2 手写 Tokenizer (tokenizer.uya)

**任务**: 实现手写词法分析器，解析简单表达式

**重要设计决策**: 此处实现的是**手写 tokenizer**，用于格式化器的测试和简单表达式解析。不同于依赖编译器 `src/lexer.uya`，这里实现一个简化版本。

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 1.2.1 | 创建 `lib/std/fmt/tokenizer.uya` | Token 类型定义 |
| 1.2.2 | 实现 `TokenType` 枚举 | 包含 NUMBER, STRING, IDENT, PLUS, MINUS, STAR, SLASH, LPAREN, RPAREN, EOF |
| 1.2.3 | 实现 `Token` 结构体 | 包含 type, value, line, column |
| 1.2.4 | 实现 `tokenize_expression()` | 解析简单表达式，返回 Token 列表 |

**代码设计**:

```uya
// lib/std/fmt/tokenizer.uya
use std.mem.arena;
use std.mem.arena.arena_alloc;

// Token 类型
enum TokenType {
    TOKEN_EOF,
    TOKEN_NUMBER,
    TOKEN_STRING,
    TOKEN_IDENT,
    // 运算符
    TOKEN_PLUS,      // +
    TOKEN_MINUS,     // -
    TOKEN_STAR,      // *
    TOKEN_SLASH,     // /
    TOKEN_PERCENT,   // %
    // 比较运算符
    TOKEN_EQ,        // ==
    TOKEN_NE,        // !=
    TOKEN_LT,        // <
    TOKEN_LE,        // <=
    TOKEN_GT,        // >
    TOKEN_GE,        // >=
    // 赋值
    TOKEN_ASSIGN,    // =
    // 界符
    TOKEN_LPAREN,    // (
    TOKEN_RPAREN,    // )
    TOKEN_LBRACE,    // {
    TOKEN_RBRACE,    // }
    TOKEN_LBRACKET,  // [
    TOKEN_RBRACKET,  // ]
    TOKEN_COMMA,     // ,
    TOKEN_SEMICOLON, // ;
    TOKEN_COLON,     // :
    TOKEN_ARROW,     // ->
    // 关键字
    TOKEN_FN,        // fn
    TOKEN_LET,       // let
    TOKEN_CONST,     // const
    TOKEN_IF,        // if
    TOKEN_WHILE,     // while
    TOKEN_RETURN,    // return
    TOKEN_STRUCT,    // struct
    TOKEN_USE,       // use
    TOKEN_EXPORT,    // export
    // 注释（特殊处理）
    TOKEN_LINE_COMMENT,
    TOKEN_BLOCK_COMMENT,
}

// Token 结构体
export struct Token {
    type: TokenType,
    value: &[byte],    // Token 的字面值
    line: usize,       // 行号（从 1 开始）
    column: usize,     // 列号（从 1 开始）
}

// Tokenizer 状态
struct TokenizerState {
    ptr: &byte,        // 当前解析位置
    end: &byte,        // 结束位置
    line: usize,       // 当前行
    column: usize,     // 当前列
}

// 跳过空白字符
fn skip_whitespace(state: &TokenizerState) void {
    while state.ptr < state.end {
        const c: byte = state.ptr[0];
        if c == ' ' as byte || c == '\t' as byte || c == '\r' as byte {
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
        } else if c == '\n' as byte {
            state.ptr = state.ptr + 1;
            state.line = state.line + 1;
            state.column = 1;
        } else {
            break;
        }
    }
}

// 读取标识符
fn read_ident(state: &TokenizerState, arena: &Arena) &Token {
    const start_ptr: &byte = state.ptr;
    const start_col: usize = state.column;
    while state.ptr < state.end {
        const c: byte = state.ptr[0];
        if (c >= 'a' as byte && c <= 'z' as byte) ||
           (c >= 'A' as byte && c <= 'Z' as byte) ||
           (c >= '0' as byte && c <= '9' as byte) ||
           c == '_' as byte {
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
        } else {
            break;
        }
    }
    const len: usize = state.ptr - start_ptr;
    const value: &[byte] = arena_dup(arena, start_ptr[0:len]);
    const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
    tok.type = TokenType.TOKEN_IDENT;
    tok.value = value;
    tok.line = state.line;
    tok.column = start_col;
    return tok;
}

// 读取数字
fn read_number(state: &TokenizerState, arena: &Arena) &Token {
    const start_ptr: &byte = state.ptr;
    const start_col: usize = state.column;
    while state.ptr < state.end {
        const c: byte = state.ptr[0];
        if c >= '0' as byte && c <= '9' as byte {
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
        } else {
            break;
        }
    }
    const len: usize = state.ptr - start_ptr;
    const value: &[byte] = arena_dup(arena, start_ptr[0:len]);
    const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
    tok.type = TokenType.TOKEN_NUMBER;
    tok.value = value;
    tok.line = state.line;
    tok.column = start_col;
    return tok;
}

// 主 tokenize 函数
export fn tokenize_expression(arena: &Arena, source: &[byte]) !&[Token] {
    var state: TokenizerState = undefined;
    state.ptr = source.ptr;
    state.end = source.ptr + source.len;
    state.line = 1;
    state.column = 1;

    // 简单实现：只解析 "1 + 2" 这种简单表达式
    var tokens: [Token: 16] = [];  // 最多 16 个 token

    var count: usize = 0;
    while state.ptr < state.end {
        skip_whitespace(&state);
        if state.ptr >= state.end { break; }

        const c: byte = state.ptr[0];
        const col: usize = state.column;

        if c >= '0' as byte && c <= '9' as byte {
            const tok: &Token = read_number(&state, arena);
            tokens[count] = tok;
            count = count + 1;
        } else if c == '+' as byte {
            const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
            tok.type = TokenType.TOKEN_PLUS;
            tok.line = state.line;
            tok.column = col;
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
            tokens[count] = tok;
            count = count + 1;
        } else if c == '-' as byte && state.ptr + 1 < state.end && state.ptr[1] == '>' as byte {
            const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
            tok.type = TokenType.TOKEN_ARROW;
            tok.line = state.line;
            tok.column = col;
            state.ptr = state.ptr + 2;
            state.column = state.column + 2;
            tokens[count] = tok;
            count = count + 1;
        } else if c == '*' as byte {
            const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
            tok.type = TokenType.TOKEN_STAR;
            tok.line = state.line;
            tok.column = col;
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
            tokens[count] = tok;
            count = count + 1;
        } else if c == '/' as byte {
            const tok: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
            tok.type = TokenType.TOKEN_SLASH;
            tok.line = state.line;
            tok.column = col;
            state.ptr = state.ptr + 1;
            state.column = state.column + 1;
            tokens[count] = tok;
            count = count + 1;
        } else {
            return error.InvalidCharacter;
        }
    }

    // 添加 EOF token
    const eof: &Token = arena_alloc(arena, sizeof(Token) as usize) as &Token;
    eof.type = TokenType.TOKEN_EOF;
    eof.line = state.line;
    eof.column = state.column;
    tokens[count] = eof;
    count = count + 1;

    return arena_dup(arena, tokens[0:count]);
}
```

**测试用例** (`tests/test_fmt_tokenizer.uya`):

```uya
// test_fmt_tokenizer - Tokenizer 功能测试
use std.runtime.entry;
use std.mem.arena;
use std.mem.arena.arena_init;
use std.fmt.tokenizer;
use std.fmt.tokenizer.tokenize_expression;
use std.fmt.tokenizer.TokenType;

export fn main() i32 {
    var arena_buf: [byte: 4096] = [];
    var a: Arena = undefined;
    arena_init(&a, &arena_buf[0], 4096);

    const src: &[byte] = "1 + 2 * 3" as &[byte];
    const tokens: &[Token] = try tokenize_expression(&a, src);

    // 验证 token 数量和类型
    if tokens.len < 4 { return 1; }

    if tokens[0].type != TokenType.TOKEN_NUMBER { return 2; }
    if tokens[1].type != TokenType.TOKEN_PLUS { return 3; }
    if tokens[2].type != TokenType.TOKEN_NUMBER { return 4; }
    if tokens[3].type != TokenType.TOKEN_STAR { return 5; }
    if tokens[4].type != TokenType.TOKEN_NUMBER { return 6; }
    if tokens[5].type != TokenType.TOKEN_EOF { return 7; }

    return 0;
}
```

---

### 1.3 AST 打印器 (printer.uya)

**任务**: 将 AST 节点打印为格式化字符串

**重要设计决策**: 此阶段的 Printer 接收**手动构造的 AST 节点**进行测试，而非解析源码。解析源码的功能在 Phase 3 讨论。

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 1.3.1 | 创建 `lib/std/fmt/printer.uya` | Printer 结构体定义 |
| 1.3.2 | 实现 `printer_init()` | 初始化打印机 |
| 1.3.3 | 实现 `print_number()` | 打印数字节点 |
| 1.3.4 | 实现 `print_binary_expr()` | 打印二元表达式 |
| 1.3.5 | 实现 `print_node()` | 分发到对应打印函数 |

**代码设计**:

```uya
// lib/std/fmt/printer.uya
use std.fmt.formatter;
use std.fmt.formatter.Formatter;
use std.fmt.formatter.formatter_init;
use std.fmt.formatter.formatter_write;
use std.fmt.formatter.formatter_write_byte;
use std.fmt.formatter.formatter_write_indent;

// 简化的 AST 节点类型（用于测试）
enum FmtASTType {
    FMT_AST_NUMBER,
    FMT_AST_BINARY_EXPR,
    FMT_AST_IDENT,
}

// 简化的 AST 节点（用于测试）
export struct FmtASTNode {
    type: FmtASTType,
    value: &[byte],           // 用于 NUMBER 和 IDENT
    left: &FmtASTNode,        // 用于 BINARY_EXPR
    right: &FmtASTNode,       // 用于 BINARY_EXPR
    op: byte,                 // 操作符：'+', '-', '*', '/'
}

// Printer 结构体
export struct Printer {
    f: &Formatter,
    indent_incr: usize,
}

export fn printer_init(p: &Printer, f: &Formatter) void {
    p.f = f;
    p.indent_incr = 1;
}

fn print_number(p: &Printer, node: &FmtASTNode) !void {
    try formatter_write(p.f, node.value);
}

fn print_binary_expr(p: &Printer, node: &FmtASTNode) !void {
    try formatter_write_byte(p.f, '(' as byte);
    try print_node(p, node.left);
    try formatter_write_byte(p.f, ' ' as byte);
    try formatter_write_byte(p.f, node.op as byte);
    try formatter_write_byte(p.f, ' ' as byte);
    try print_node(p, node.right);
    try formatter_write_byte(p.f, ')' as byte);
}

export fn print_node(p: &Printer, node: &FmtASTNode) !void {
    match node.type {
        .FMT_AST_NUMBER => { try print_number(p, node); },
        .FMT_AST_BINARY_EXPR => { try print_binary_expr(p, node); },
        .FMT_AST_IDENT => { try formatter_write(p.f, node.value); },
        else => { try formatter_write(p.f, "???" as &[byte]); },
    }
}

// 辅助函数：格式化表达式
export fn format_expr(arena: &Arena, left: &[byte], op: byte, right: &[byte]) !&[byte] {
    var buf: [byte: 256] = [];
    var f: Formatter = undefined;
    formatter_init(&f, &buf[0], 256);

    var p: Printer = undefined;
    printer_init(&p, &f);

    // 构建 AST 节点
    var left_node: FmtASTNode = undefined;
    left_node.type = FmtASTType.FMT_AST_NUMBER;
    left_node.value = left;

    var right_node: FmtASTNode = undefined;
    right_node.type = FmtASTType.FMT_AST_NUMBER;
    right_node.value = right;

    var expr_node: FmtASTNode = undefined;
    expr_node.type = FmtASTType.FMT_AST_BINARY_EXPR;
    expr_node.left = &left_node;
    expr_node.right = &right_node;
    expr_node.op = op;

    try print_node(&p, &expr_node);

    return arena_dup(arena, &buf[0:f.pos]);
}
```

**测试用例** (`tests/test_fmt_printer.uya`):

```uya
// test_fmt_printer - AST 打印功能测试
use std.runtime.entry;
use std.mem.arena;
use std.mem.arena.arena_init;
use std.fmt.printer;
use std.fmt.printer.format_expr;

export fn main() i32 {
    var arena_buf: [byte: 4096] = [];
    var a: Arena = undefined;
    arena_init(&a, &arena_buf[0], 4096);

    // 测试格式化表达式
    const result: &[byte] = try format_expr(&a, "1" as &[byte], '+' as byte, "2" as &[byte]);

    // 验证结果应该是 "(1 + 2)"
    if result.len != 7 { return 1; }
    // result[0] == '('
    // result[1] == '1'
    // result[2] == ' '
    // result[3] == '+'
    // result[4] == ' '
    // result[5] == '2'
    // result[6] == ')'

    return 0;
}
```

---

## 阶段二：完整格式化

### 2.1 表达式格式化

**任务**: 格式化各种表达式类型

| 步骤 | 内容 | 验收标准 | 量化指标 |
|------|------|----------|----------|
| 2.1.1 | 二元表达式 `a + b` | 括号和空格正确 | `1+2` → `(1 + 2)` |
| 2.1.2 | 一元表达式 `-x` | 一元运算符正确 | `-x` → `(-x)` |
| 2.1.3 | 调用表达式 `fn(a, b)` | 参数列表格式化 | 参数逗号后有空格 |
| 2.1.4 | 成员访问 `obj.field` | 点号正确 | |
| 2.1.5 | 索引访问 `arr[0]` | 中括号正确 | |

**格式化规则**:

```uya
// 二元表达式：始终添加括号和空格
(a + b)    // 加减
(a * b)    // 乘除
(a && b)   // 逻辑与
(a || b)   // 逻辑或
```

### 2.2 语句格式化

**任务**: 格式化各种语句类型

| 步骤 | 内容 | 验收标准 | 量化指标 |
|------|------|----------|----------|
| 2.2.1 | 赋值语句 `x = 1` | 等号两边有空格 | `x=1` → `x = 1` |
| 2.2.2 | if 语句 | 关键字和括号正确 | `if x==0{return 1;}` → 正确格式化 |
| 2.2.3 | while 语句 | 循环格式正确 | |
| 2.2.4 | return 语句 | return 和值之间有空格 | `return x+1;` → `return x + 1;` |
| 2.2.5 | 函数调用 | 表达式语句格式 | |

**格式化规则**:

```uya
// if 语句
if condition {
    // body
}

// while 语句
while condition {
    // body
}

// return 语句
return value;
```

### 2.3 声明格式化

**任务**: 格式化各种声明类型

| 步骤 | 内容 | 验收标准 | 量化指标 |
|------|------|----------|----------|
| 2.3.1 | const/var 声明 | 类型标注对齐 | `const x:i32=1;` → `const x: i32 = 1;` |
| 2.3.2 | fn 函数声明 | 函数签名格式正确 | |
| 2.3.3 | struct 声明 | 结构体字段对齐 | |
| 2.3.4 | interface 声明 | 接口方法列表对齐 | |
| 2.3.5 | use 语句 | use 路径正确格式 | |

**格式化规则**:

```uya
// 函数声明
export fn main() i32 {
    return 0;
}

// 结构体
struct Point {
    x: i32,
    y: i32,
}

// use 语句
use std.fmt.formatter;
```

### 2.4 注释处理

**任务**: 保留并正确放置注释

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 2.4.1 | 行注释 `// comment` | 保持原位置 |
| 2.4.2 | 块注释 `/* comment */` | 块注释正确 |
| 2.4.3 | 文档注释 | 保留在声明前 |
| 2.4.4 | 行尾注释 | 注释对齐 |

**代码设计**:

```uya
// 注释结构
export struct Comment {
    text: &[byte],
    is_line_comment: bool,  // true = 行注释, false = 块注释
    line: usize,
    column: usize,
}

// 追踪注释位置
export struct CommentedNode {
    node: &ASTNode,
    before: &[Comment],  // 节点前的注释
    after: &[Comment],   // 节点后的注释
    line_start: bool,     // 是否在行首
}
```

### 2.5 Import 排序

**任务**: 自动排序 import 语句

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 2.5.1 | 收集 import | 提取所有 use 语句 |
| 2.5.2 | 分组排序 | std 在前，其他在后 |
| 2.5.3 | 字母排序 | 同组内按字母排序 |
| 2.5.4 | 去重 | 移除重复的 use |

**排序规则**:

```uya
// 排序前
use std.json.parser;
use std.mem.arena;
use foo.bar;
use std.json.encoder;

// 排序后
use std.json.encoder;
use std.json.parser;
use std.mem.arena;
use foo.bar;
```

---

## 阶段三：主入口和 API

### 3.1 核心 API

**任务**: 提供统一的格式化接口

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 3.1.1 | `fmt.format(source)` | 源码 → 格式化源码 |
| 3.1.2 | `fmt.format_node(node)` | AST → 格式化源码 |
| 3.1.3 | `fmt.is_formatted(source)` | 检查是否已格式化 |
| 3.1.4 | 往返测试 | format(format(x)) == format(x) |

**注意**: 完整的 `format(source)` 功能需要解析器支持。考虑到编译器的 Parser 在 `src/` 内部，有两种方案：
1. **方案 A（推荐）**: fmt 库包含自己的简化解析器
2. **方案 B**: fmt 库作为编译器扩展，在编译器构建时包含解析器

**代码设计** (方案 A):

```uya
// lib/std/fmt/fmt.uya
// 主入口和公开 API

// 格式化源码（需要内置解析器）
export fn format(arena: &Arena, source: &[byte]) !&[byte] {
    // 1. 词法分析
    const tokens: &[Token] = try tokenize(arena, source);

    // 2. 解析为 AST（简化版）
    const node: &ASTNode = try parse_tokens(arena, tokens);

    // 3. 格式化 AST
    var buf: [byte: 65536] = [];
    var f: Formatter = undefined;
    formatter_init(&f, &buf[0], 65536);
    var p: Printer = undefined;
    printer_init(&p, &f);
    try print_node(&p, node);

    // 4. 返回结果
    return arena_dup(arena, &buf[0:f.pos]);
}

export fn is_formatted(arena: &Arena, source: &[byte]) bool {
    const formatted: &[byte] = try format(arena, source);
    return slice_equals(source, formatted);
}
```

---

### 3.2 往返一致性测试

**任务**: 确保格式化是幂等的

```uya
// test_fmt_idempotent - 往返一致性测试
export fn main() i32 {
    var arena_buf: [byte: 4096] = [];
    var a: Arena = undefined;
    arena_init(&a, &arena_buf[0], 4096);

    const src: &[byte] = `
fn   foo(  x:i32)->i32{
return   x+1;
}
` as &[byte];

    const f1: &[byte] = try format(&a, src);
    const f2: &[byte] = try format(&a, f1);

    // 格式化两次应该相同
    if !slice_equals(f1, f2) {
        return 1;
    }

    return 0;
}
```

---

## 阶段四：CLI 工具

### 4.1 命令行工具

**任务**: 创建 `uya fmt` 命令

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 4.1.1 | 创建 `tools/fmt.uya` | 工具入口 |
| 4.1.2 | `uya fmt file.uya` | 打印格式化结果 |
| 4.1.3 | `uya fmt -w file.uya` | 写入文件 |
| 4.1.4 | `uya fmt -d file.uya` | 显示差异 |
| 4.1.5 | `uya fmt -l file.uya` | 列出需格式化的文件 |

**使用方式**:

```bash
# 格式化并输出到 stdout
uya fmt source.uya

# 原地格式化
uya fmt -w source.uya

# 检查是否已格式化（返回 0 表示已格式化）
uya fmt -l source.uya

# 显示差异
uya fmt -d source.uya
```

---

### 4.2 Makefile 集成

**任务**: 添加 `make fmt` 命令

```makefile
# 格式化所有源码
fmt:
	@find . -name "*.uya" -not -path "./bin/*" -not -path "./.uyacache/*" | \
	while read f; do $(UYA) fmt -w "$$f"; done

# 检查格式化状态
check-fmt:
	@find . -name "*.uya" -not -path "./bin/*" -not -path "./.uyacache/*" | \
	while read f; do \
		if ! $(UYA) fmt -l "$$f" > /dev/null 2>&1; then \
			echo "Need formatting: $$f"; \
		fi; \
	done
```

---

## 阶段五：高级特性（可选）

### 5.1 简化模式

| 步骤 | 内容 | 验收标准 |
|------|------|----------|
| 5.1.1 | 移除冗余括号 | `(x)` → `x` |
| 5.1.2 | 简化 `*&x` | `*&x` → `x` |
| 5.1.3 | 简化 `x+0` / `x*1` | 算数简化 |

### 5.2 Rewrite 规则

类似 `gofmt -r`：

```bash
# 应用 rewrite 规则
uya fmt -r "foo.bar -> bar"
```

---

## 开发顺序

### 推荐的开发顺序

1. **Phase 1.1** - formatter.uya（核心数据结构）
2. **Phase 1.2** - tokenizer.uya（手写 tokenizer）
3. **Phase 1.3** - printer.uya（基础表达式）
4. **Phase 2.1** - 表达式格式化 + test_fmt_expr
5. **Phase 2.2** - 语句格式化 + test_fmt_stmt
6. **Phase 2.3** - 声明格式化 + test_fmt_decl
7. **Phase 2.4** - 注释处理 + test_fmt_comments
8. **Phase 2.5** - Import 排序 + test_fmt_import_sort
9. **Phase 3.1** - fmt.uya 主入口 + test_fmt_idempotent
10. **Phase 4.1** - tools/fmt.uya CLI

---

## 验收标准

每阶段完成后应满足：

| 阶段 | 验收标准 | 量化指标 |
|------|----------|----------|
| 1.1 | `formatter_write("hello")` 写入 5 字节 | `f.pos == 5` |
| 1.1 | 缩进级别正确递增递减 | `indent` 值正确 |
| 1.1 | 行号在换行时递增 | `f.line` 在 `'\n'` 后 +1 |
| 1.2 | Token 列表正确解析 | `"1 + 2"` 解析为 NUMBER, PLUS, NUMBER, EOF |
| 1.2 | 手写 tokenizer 无外部依赖 | 不引用 `src/` 下任何模块 |
| 1.3 | 简单表达式如 `1 + 2` 正确打印 | 输出为 `(1 + 2)` |
| 2.1 | `1+2` → `(1 + 2)` | 格式化结果正确 |
| 2.2 | `if x==0{return 1;}` 正确格式化 | 关键字后有空格，括号正确 |
| 2.3 | 函数声明格式正确 | `fn main() i32` 各部分间距正确 |
| 2.4 | 注释位置保持正确 | 行注释和块注释位置不变 |
| 2.5 | Import 语句正确排序 | std 在前，字母排序 |
| 3.1 | `format(source)` 返回格式化结果 | 源码 → 格式化源码 |
| 3.2 | 往返格式化一致 | `format(format(x)) == format(x)` |
| 4.1 | CLI 工具可用 | `uya fmt file.uya` 输出格式化结果 |

---

## 版本历史

| 版本 | 日期 | 更新内容 |
|------|------|----------|
| v0.1.0 | 2026-03-29 | 初始版本 |
| v0.1.1 | 2026-03-29 | 优化架构设计：明确 tokenizer 为手写，不依赖编译器 Lexer；增加量化验收标准 |
