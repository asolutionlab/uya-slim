# Uya 变更日志

## v0.7.4 - P1/P2 可选任务实现

> 发布日期：2026-02-24

### 新特性

#### P1 任务

- **越界访问检测（bounds_check_pass）**
  - 在 `checker/proof.uya` 中实现编译期静态分析
  - 检测数组访问越界风险
  - 检测指针算术越界风险
  - 检测切片边界越界风险
  - 支持 `BoundsCheckRisk` 枚举（SAFE/WARNING/ERROR）

#### P2 任务

- **指令融合优化（instruction_fusion_pass）**
  - 在 `checker/optimizer.uya` 中实现指令融合框架
  - 检测可融合的连续算术指令
  - 检测乘加融合（MAC）模式
  - 为后续优化提供分析基础

- **冗余指令消除（redundant_instruction_elimination_pass）**
  - 在 `checker/optimizer.uya` 中实现冗余指令检测
  - 检测 nop 等无副作用指令
  - 检测自移动指令（如 mov r0, r0）
  - 寄存器生命周期分析框架

- **RISC-V 平台扩展支持**
  - 新增 `TYPE_ASM_REG_RISCV_V` 类型（向量扩展）
  - 新增 `TYPE_ASM_REG_RISCV_F` 类型（单精度浮点）
  - 新增 `TYPE_ASM_REG_RISCV_D` 类型（双精度浮点）
  - 更新 `is_riscv_reg_type()` 函数支持新类型
  - 更新 `asm_reg_type_name()` 函数支持新类型

### 新增函数

- `check_array_bounds_const()` - 检测数组访问越界（常量索引）
- `check_pointer_arithmetic_bounds()` - 检测指针算术越界
- `check_slice_bounds()` - 检测切片边界越界
- `bounds_check_pass()` - 全程序越界访问检测 Pass
- `can_fuse_arithmetic_instructions()` - 检测指令融合机会
- `instruction_fusion_pass()` - 指令融合优化 Pass
- `detect_redundant_instruction()` - 检测冗余指令
- `analyze_register_lifecycle()` - 寄存器生命周期分析
- `redundant_instruction_elimination_pass()` - 冗余指令消除 Pass
- `optimize_asm_block()` - @asm 块综合优化入口

### 测试

- 新增 `tests/programs/test_bounds_check.uya` 测试文件
- 所有 462 个现有测试通过

---

## v0.7.3 - 编译期优化功能完善

> 发布日期：2026-02-24

### 新特性

- **优化级别命令行选项**
  - `--opt=<0-3>` 设置优化级别
  - `-O0`, `-O1`, `-O2`, `-O3` 简写形式
  - 默认优化级别为 1（常量折叠 + 死代码消除）

### 优化级别说明

| 级别 | 功能 |
|------|------|
| 0 | 禁用优化（调试模式） |
| 1 | 常量折叠 + 死代码消除（默认） |
| 2 | + 证明优化 |
| 3 | + 内联 + 循环展开（未来） |

### 修复

- **修复 Lexer 不支持三元运算符导致的优化器解析问题**
  - 问题：lexer 遇到 `?` 返回 `TOKEN_EOF`，导致 parser 提前终止
  - 影响：`optimizer.uya` 中三元运算符后的函数定义全部丢失
  - 修复：将三元运算符改为 if-else 语句
  - 同时修复了被掩盖的 TokenType 名称错误：
    - `TOKEN_AND_AND` → `TOKEN_LOGICAL_AND`
    - `TOKEN_OR_OR` → `TOKEN_LOGICAL_OR`
    - `TOKEN_EQUAL_EQUAL` → `TOKEN_EQUAL`
    - `TOKEN_BANG_EQUAL` → `TOKEN_NOT_EQUAL`
  - 修复 ASTNodeType 和字段名错误：
    - `AST_INDEX_EXPR` → `AST_ARRAY_ACCESS`
    - `bool_value` → `bool_literal_value`

### 文档更新

- 更新 `docs/compile_time_optimization_status.md` 状态文档

---

## v0.7.2 - @asm 测试覆盖率完善

> 发布日期：2026-02-23

### 测试

- **@asm 功能测试覆盖率 100%**
  - 新增 9 个正向测试文件，覆盖基础功能、类型系统、clobbers、边界情况等
  - 新增 17 个反向测试文件，覆盖语法错误、类型错误、限制检查等
  - 修复了类型检查器中 `AST_ASM` 节点作为语句使用时未进行类型检查的 bug

### 新增测试文件

**正向测试（9 个）：**
- `test_asm_basic.uya` - 基础功能：简单指令、无输入输出、多输入多输出
- `test_asm_types.uya` - 类型系统：i8/i16/i32/i64/u8/u16/u32/u64/usize/指针
- `test_asm_clobbers.uya` - clobbers 声明：单/多寄存器、memory、混合
- `test_asm_edge_cases.uya` - 边界情况：空指令、最大输入/输出、控制流中使用
- `test_asm_codegen.uya` - 代码生成验证
- `test_asm_expressions.uya` - 表达式：变量、常量、数组元素、结构体字段
- `test_asm_duplicate_output.uya` - 多输出变量测试
- `test_asm_const_output.uya` - 输出测试
- `test_asm_void_output.uya` - 无输出测试

**反向测试（17 个）：**
- `error_asm_empty_block.uya` - @asm 块不能为空
- `error_asm_missing_string.uya` - 期望指令字符串
- `error_asm_invalid_input_type.uya` - f32 输入类型错误
- `error_asm_invalid_output_type.uya` - f64 输出类型错误
- `error_asm_output_pointer.uya` - 指针不能作为输出
- `error_asm_f64_input.uya` - f64 输入类型错误
- `error_asm_f64_output.uya` - f64 输出类型错误
- `error_asm_missing_paren.uya` - 语法错误：缺少 '('
- `error_asm_missing_close_paren.uya` - 语法错误：缺少 ')'
- `error_asm_missing_brace.uya` - 语法错误：缺少 '{'
- `error_asm_missing_close_brace.uya` - 语法错误：缺少 '}'
- `error_asm_too_many_inputs.uya` - 输入超过最大限制
- `error_asm_too_many_outputs.uya` - 输出超过最大限制
- `error_asm_void_input.uya` - void 类型输入错误
- `error_asm_struct_input.uya` - 结构体输入错误
- `error_asm_array_input.uya` - 数组输入错误
- `error_asm_slice_input.uya` - 切片输入错误

### 修复

- 修复 `src/checker/main.uya`：`AST_ASM` 节点作为语句使用时未调用类型检查

---

## v0.7.1 - 切片字面量 & 语法增强

> 发布日期：2026-02-21

### 新特性

- **切片字面量**：支持从数组字面量直接创建切片
  - `const slice: &[i32] = &[1, 2, 3];`
  - `const slice: &[i32] = &[0: 10];`
  - 无需先声明数组变量，直接创建切片

- **match 表达式省略分号**
  - 当所有分支都是 block 时可省略分号
  - 提升代码流畅性和可读性

### 改进

- 类型推断增强：变量声明时正确推断切片类型
- 代码生成优化：切片字面量生成高效的 C99 复合字面量

---

## v0.7.0 - 编译器重构 & 性能优化

> 发布日期：2026-02-21

### 重构（阶段一：模块拆分）

**checker.uya 拆分为 16 个文件：**
- `types.uya` - 类型定义 (224 行)
- `symbols.uya` - 符号表操作 (668 行)
- `type_utils.uya` - 类型工具函数 (481 行)
- `lookup.uya` - 查找函数 (452 行)
- `generics.uya` - 泛型单态化 (177 行)
- `proof.uya` - 安全证明 (331 行)
- `type_from_ast.uya` - 类型解析 (335 行)
- `check_expr.uya` - 表达式检查 (1465 行)
- `check_stmt.uya` - 语句检查 (754 行)
- `check_call.uya` - 调用检查 (747 行)
- `interval.uya` - 区间算术 (1027 行)
- `check_expr_extra.uya` - 表达式辅助 (824 行)
- `check_node_extra.uya` - 节点检查 (641 行)
- `modules.uya` - 模块系统 (1197 行)
- `macro_expand.uya` - 宏展开 (1168 行)
- `main.uya` - 检查器入口 (610 行)

**parser.uya 拆分为 6 个文件：**
- `types.uya` - 类型解析 (599 行)
- `primary.uya` - 基础表达式 (2393 行)
- `expressions.uya` - 二元/一元表达式 (925 行)
- `statements.uya` - 语句解析 (616 行)
- `declarations.uya` - 声明解析 (2200 行)
- `main.uya` - 解析器入口 (479 行)

### 内存优化（阶段二）

- **Arena 按需增长**：动态分配新 chunk，避免静态分配浪费
- **静态内存减少 75%**：320MB → 81MB

### 性能优化（阶段三）

- **作用域链表优化**：符号表查找从 O(32768) → O(当前作用域符号数)
- **自举编译时间**：8.2s → 1.8s（提升 4.5 倍）
- **字符串池**：减少字符串比较开销

### 修复

- 修复 `fprintf` 参数类型警告

### 代码统计

| 模块 | 文件数 | 总行数 |
|------|--------|--------|
| checker | 16 | 10,978 |
| parser | 6 | 7,212 |
| codegen/c99 | 10 | ~8,000 |

---

## v0.6.0 - 统一测试框架 & CLI 重构

> 发布日期：2026-02-20

### 新特性

- **统一命令行接口**：`uya build`、`uya run`、`uya test` 子命令
- **统一测试框架**：`test "name" {}` 语法，自动收集和运行测试
- **自动入口检测**：编译器自动检测 `test` 和 `export fn main`
- **--nostdlib 模式**：静态链接，零依赖可执行文件
- **编译阶段计时**：显示各编译阶段耗时

### 修复

- `try` 表达式在 void 函数中正确工作

---

## v0.5.9 - 错误处理增强

### 新特性

- 错误联合类型 `!T` 改进
- 预定义错误集支持

---

## v0.5.8 - 接口系统

### 新特性

- 鸭子类型接口
- 零注册，编译期生成

---

## v0.5.7 - 泛型系统

### 新特性

- 泛型语法 `<T>` 支持
- 泛型约束 `<T: Trait>`
- 泛型单态化

---

## v0.5.5 - 内存安全

### 新特性

- 编译期内存安全证明
- 指针非空追踪
- 移动语义检查

---

## v0.5.4 - Union 类型

### 新特性

- 联合体（union）类型
- 编译期标签跟踪
- C union 100% 互操作

---

## v0.5.3 - 模块系统

### 新特性

- 目录级模块
- 显式导出 `export`
- 路径导入 `use`

---

## v0.5.0 - 初始发布

### 核心特性

- 零 GC
- 默认高级安全
- 单页纸可读完
- 无 lifetime 符号
- 无隐式控制
- 编译期证明
