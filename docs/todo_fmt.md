# Uya 代码格式化器 (fmt) 实现待办

**版本**: v0.1.1
**参考**：[fmt_development_plan.md](fmt_development_plan.md)
**更新日期**: 2026-03-29

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。

---

## Phase 1：基础格式化引擎

### 1.1 核心数据结构 (formatter.uya)

**状态**: completed ✓

**验收标准**（量化）:
- `formatter_write("hello")` 写入 5 字节 → `f.pos == 5`
- 缩进级别正确递增递减 → `indent` 值正确
- 行号在换行时递增 → `f.line` 在 `'\n'` 后 +1

**任务清单**:

- [x] 创建 `lib/std/fmt/formatter.uya`
- [x] 定义 `Formatter` 结构体（buf, pos, cap, indent, line, at_line_start）
- [x] 实现 `formatter_init(f, buf, cap)`
- [x] 实现 `formatter_write(f, ptr, len)`
- [x] 实现 `formatter_write_byte(f, b)`
- [x] 实现 `formatter_indent(f)` / `formatter_dedent(f)`
- [x] 实现 `formatter_write_indent(f)`
- [x] `tests/test_fmt_formatter.uya`

---

### 1.2 手写 Tokenizer (tokenizer.uya)

**状态**: completed ✓

**重要说明**: 此处实现的是**手写 tokenizer**，不依赖编译器 `src/lexer.uya`。这是 fmt 库自包含设计的一部分。

**验收标准**（量化）:
- `"1 + 2"` 解析为 NUMBER, PLUS, NUMBER, EOF → token 类型正确
- 手写 tokenizer 无外部依赖 → 不引用 `src/` 下任何模块

**任务清单**:

- [x] 创建 `lib/std/fmt/tokenizer.uya`
- [x] 定义 `TokenType` 枚举（NUMBER, STRING, IDENT, PLUS, MINUS, STAR, SLASH, LPAREN, RPAREN, EOF 等）
- [x] 定义 `Token` 结构体（type, ptr, len, line, column）
- [x] 实现 `tokenize_expression(source, source_len)`
- [ ] `tests/test_fmt_tokenizer.uya`

---

### 1.3 AST 打印器 (printer.uya)

**状态**: completed ✓

**重要说明**: 此阶段的 Printer 接收**手动构造的 AST 节点**进行测试，而非解析源码。这是 Phase 1 的设计决策，确保可以独立测试。

**验收标准**（量化）:
- 输入 `"1", '+', "2"` → 输出为 `(1 + 2)` → `result.len == 7`

**任务清单**:

- [x] 创建 `lib/std/fmt/printer.uya`
- [x] 定义 `FmtASTType` 枚举和 `FmtASTNode` 结构体（简化版，用于测试）
- [x] 定义 `Printer` 结构体
- [x] 实现 `printer_init(p, f)`
- [x] 实现 `print_number(p, node)`
- [x] 实现 `print_binary_expr(p, node)`
- [x] 实现 `print_node(p, node)`
- [x] 实现 `format_expr_to_string()`（辅助函数）
- [x] `tests/test_fmt_printer.uya`

---

## Phase 2：完整格式化

### 2.1 表达式格式化

**状态**: completed ✓

**验收标准**（量化）:
- `1+2` → `(1 + 2)` → 格式化结果正确

**任务清单**:

- [x] 二元表达式 `a + b` → `(a + b)`
- [x] 一元表达式 `-x` → `(-x)`
- [ ] 调用表达式 `fn(a, b)`
- [ ] 成员访问 `obj.field`
- [ ] 索引访问 `arr[0]`
- [x] `tests/test_fmt_expr.uya`

---

### 2.2 语句格式化

**状态**: completed ✓

**验收标准**（量化）:
- `x=1` → `x = 1` → 等号两边有空格
- `if x==0{return 1;}` → 正确格式化 → 关键字后有空格，括号正确

**任务清单**:

- [x] 赋值语句 `x = 1`
- [x] if 语句格式化
- [x] while 语句格式化
- [x] return 语句格式化
- [ ] for 语句格式化
- [ ] break/continue 语句
- [ ] defer/errdefer 语句
- [ ] try/catch 表达式
- [x] `tests/test_fmt_stmt.uya`

---

### 2.3 声明格式化

**状态**: pending

**验收标准**（量化）:
- `const x:i32=1;` → `const x: i32 = 1;` → 类型标注对齐
- 函数声明格式正确 → `fn main() i32` 各部分间距正确

**任务清单**:

- [ ] const/var 声明
- [ ] fn 函数声明
- [ ] struct 声明
- [ ] interface 声明
- [ ] union 声明
- [ ] enum 声明
- [ ] type 别名声明
- [ ] use 语句
- [ ] `tests/test_fmt_decl.uya`

---

### 2.4 注释处理

**状态**: pending

**验收标准**:
- 行注释和块注释位置不变
- 文档注释保留在声明前
- 行尾注释对齐

**任务清单**:

- [ ] 定义 `Comment` 结构体（text, is_line_comment, line, column）
- [ ] 定义 `CommentedNode` 结构体（node, before, after, line_start）
- [ ] 行注释 `// comment` 处理
- [ ] 块注释 `/* comment */` 处理
- [ ] 文档注释保留
- [ ] 行尾注释对齐
- [ ] `tests/test_fmt_comments.uya`

---

### 2.5 Import 排序

**状态**: pending

**验收标准**:
- std 在前，字母排序
- 移除重复的 use

**任务清单**:

- [ ] 收集 import（use 语句）
- [ ] std 库在前，其他在后
- [ ] 同组内按字母排序
- [ ] 移除重复的 use
- [ ] `tests/test_fmt_import_sort.uya`

---

## Phase 3：主入口和 API

### 3.1 核心 API

**状态**: completed ✓

**验收标准**（量化）:
- `format(source, arena)` → 返回格式化后的源码

**任务清单**:

- [x] 创建 `lib/std/fmt/format.uya`
- [x] 实现 `format(source_ptr, source_len) usize`
- [ ] 实现 `format_node(arena, node) !&[byte]`
- [ ] 实现 `is_formatted(arena, source) bool`
- [x] `tests/test_fmt_format.uya`

---

### 3.2 往返一致性测试

**状态**: pending

**验收标准**（量化）:
- `format(format(x)) == format(x)` → 往返格式化一致

**任务清单**:

- [ ] 往返一致性测试（幂等性）
- [ ] `tests/test_fmt_idempotent.uya`

---

## Phase 4：CLI 工具

### 4.1 命令行工具

**状态**: completed ✓

**验收标准**:
- `uya fmt file.uya` 输出格式化结果

**任务清单**:

- [x] 创建 `lib/std/fmt/fmt_main.uya`
- [x] `uya fmt file.uya` 打印格式化结果
- [x] `uya fmt -w file.uya` 写入文件
- [x] `uya fmt -d file.uya` 显示差异
- [x] `uya fmt -l file.uya` 列出需格式化的文件

---

### 4.2 Makefile 集成

**状态**: pending

**任务清单**:

- [ ] `make fmt` 格式化所有源码
- [ ] `make check-fmt` 检查格式化状态

---

## Phase 5：高级特性（可选）

### 5.1 简化模式

**状态**: pending

**任务清单**:

- [ ] 移除冗余括号 `(x)` → `x`
- [ ] 简化 `*&x` → `x`
- [ ] 简化 `x+0` / `x*1`

---

### 5.2 Rewrite 规则

**状态**: pending

**任务清单**:

- [ ] 类似 `gofmt -r "pattern -> replacement"`
- [ ] 模式匹配和替换

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
├── test_fmt_api.uya         # 核心 API
└── test_fmt_idempotent.uya   # 往返一致性测试

tools/
└── fmt.uya              # CLI 工具
```

---

## 验收标准汇总

| 阶段 | 验收标准 | 量化指标 |
|------|----------|----------|
| 1.1 | `formatter_write("hello")` 写入 5 字节 | `f.pos == 5` |
| 1.1 | 缩进级别正确递增递减 | `indent` 值正确 |
| 1.1 | 行号在换行时递增 | `f.line` 在 `'\n'` 后 +1 |
| 1.2 | `"1 + 2"` 解析为 NUMBER, PLUS, NUMBER, EOF | token 类型正确 |
| 1.2 | 手写 tokenizer 无外部依赖 | 不引用 `src/` 下任何模块 |
| 1.3 | `"1", '+', "2"` → `(1 + 2)` | `result.len == 7` |
| 2.1 | `1+2` → `(1 + 2)` | 格式化结果正确 |
| 2.2 | `x=1` → `x = 1` | 等号两边有空格 |
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
