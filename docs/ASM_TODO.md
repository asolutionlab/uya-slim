# @asm 内置函数实施 TODO 清单

**创建日期**: 2026-02-22
**预计完成**: 2026-03-15 (3周)
**优先级**: P0 (核心功能)
**当前状态**: 设计阶段完成,准备开始实施

---

## 📋 项目概述

@asm 是 Uya 语言的核心内置函数,用于编写类型安全的内联汇编代码。本 TODO 清单将实施计划分解为具体的、可追踪的任务项。

**核心目标**:
- ✅ 类型安全的内联汇编
- ✅ 内存安全保证
- ✅ 并发安全保证
- ✅ 跨平台支持
- ✅ 零成本抽象

---

## 📚 文档状态

| 文档 | 状态 | 版本 | 路径 |
|------|------|------|------|
| 设计文档 | ✅ 已完成 | v1.0.1 | `docs/asm_design.md` |
| 实施计划 | ✅ 已完成 | v1.0.1 | `docs/asm_implementation_plan.md` |
| API 参考 | ✅ 已完成 | v1.0.1 | `docs/asm_api_reference.md` |
| 测试文档 | ✅ 已完成 | v1.0.0 | `tests/programs/README_asm.md` |
| 总结文档 | ✅ 已完成 | v1.0.1 | `docs/asm_summary.md` |
| 演示代码 | ✅ 已完成 | v1.0.0 | `examples/demo_asm.uya` |
| 修复报告 | ✅ 已完成 | v1.0.1 | `docs/ASM_FIXES_REPORT.md` |
|| 测试用例 | ✅ 已完成 | v1.0.0 | `tests/test_asm_*.uya`, `tests/error_asm_*.uya` |

---

## 🎯 阶段 1: 基础架构 (第1周, 3-5天)

### 目标
建立 @asm 的基础语法和类型系统,能够编译简单的 @asm 块并生成对应的 C99 内联汇编。

---

### Day 1-2: 语法和 AST ⏱️ 2天

#### Task 1.1: Lexer 支持 `@asm` 关键字
- [x] **在 `compiler-c/src/lexer.c` 中添加 `@asm` 识别**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/lexer.c`
  - 详情:
    - 在 `is_builtin_function` 函数中添加 `"asm"` 分支
    - 确保 `TOKEN_AT_IDENTIFIER` 能正确识别 `@asm`
  - 验收标准:
    - Lexer 能正确识别 `@asm` 为内置函数
    - 测试: `make test_lexer_asm` 通过

- [x] **支持字符串字面量转义序列**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/lexer.c`
  - 详情:
    - 实现转义序列处理 (`\n`, `\t`, `\\`, `\"` 等)
    - 确保指令字符串中的转义序列正确处理
  - 验收标准:
    - 字符串字面量中的转义序列正确解析
    - 测试: 包含转义序列的 @asm 指令正确编译

#### Task 1.2: AST 添加 `AST_ASM` 节点
- [x] **在 `compiler-c/src/ast.h` 中定义 AST_ASM 节点类型**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/ast.h`
  - 详情:
    ```c
    typedef enum {
        // ... 现有节点类型 ...
        AST_ASM,  // 新增：@asm 内置函数
    } ASTNodeType;
    ```
  - 验收标准:
    - AST 节点类型正确添加
    - 编译通过,无警告

- [x] **定义 @asm 节点数据结构**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/ast.h`
  - 详情:
    ```c
    typedef struct ASTAsmStmt {
        const char *instruction;  // 指令字符串
        ASTNode **inputs;         // 输入表达式数组
        ASTNode **outputs;        // 输出表达式数组
        int input_count;          // 输入个数
        int output_count;         // 输出个数
    } ASTAsmStmt;
    
    // 在 ASTNode 联合中添加
    struct {
        ASTAsmStmt *stmts;        // 语句数组
        int stmt_count;           // 语句个数
        ASTNode **clobbers;       // clobber 寄存器数组
        int clobber_count;        // clobber 个数
        bool clobbers_memory;     // 是否修改内存
    } asm;
    ```
  - 验收标准:
    - 数据结构定义完整
    - 包含所有必要字段

- [x] **实现 @asm 节点构造函数**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/ast.c`
  - 详情:
    - 实现 `create_asm_node` 函数
    - 正确初始化所有字段
  - 验收标准:
    - 函数正确实现
    - 测试: `make test_ast_asm` 通过

#### Task 1.3: Parser 实现基础语法解析
- [x] **在 `primary_expr` 中识别 `@asm`**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/parser.c`
  - 详情:
    - 检测 `TOKEN_AT_IDENTIFIER` 值为 `"asm"`
    - 调用 `parse_asm_block` 函数
  - 验收标准:
    - Parser 能识别 `@asm` 开始的块

- [x] **实现 `parse_asm_block` 函数**
  - 优先级: P0
  - 预计时间: 4小时
  - 文件: `compiler-c/src/parser.c`
  - 详情:
    - 解析 `@asm { ... }` 语法
    - 解析指令字符串模板
    - 解析输入/输出表达式列表
    - 解析可选的 clobbers 声明
  - 子任务:
    - [x] 解析 `{` 开始符号
    - [x] 解析指令字符串
    - [x] 解析 `(inputs, outputs)` 语法
    - [x] 解析 `->` 分隔符
    - [x] 解析 `clobbers = [...]` 语法
    - [x] 解析 `}` 结束符号
  - 验收标准:
    - 正确解析基本语法
    - 错误情况有清晰的错误提示
    - 测试: `make test_parser_asm` 通过

---

### Day 3-4: 类型检查 ⏱️ 2天

#### Task 1.4: Checker 实现基础类型检查
- [x] **实现 `check_asm_block` 函数**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 遍历所有语句
    - 检查输入表达式类型
    - 检查输出表达式是否是左值
    - 检查输出表达式类型
    - 检查 clobbers 声明
  - 验收标准:
    - 类型检查逻辑完整
    - 错误提示清晰

- [x] **实现类型验证辅助函数**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - `is_valid_asm_input_type`: 验证输入类型
    - `is_valid_asm_output_type`: 验证输出类型
    - `is_register_type`: 检查寄存器类型
    - `is_asm_mem_type`: 检查内存操作类型
  - 验收标准:
    - 辅助函数正确实现
    - 类型检查完整

- [x] **添加寄存器类型系统**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/types.h`, `compiler-c/src/types.c`
  - 详情:
    - 添加 `TYPE_ASM_REG` 类型
    - 添加 `TYPE_ASM_REG_X64` 类型
    - 添加 `TYPE_ASM_REG_ARM64` 类型
    - 添加 `TYPE_ASM_MEM` 类型
  - 验收标准:
    - 类型定义完整
    - 类型推断正确

- [x] **在 `check_expr` 中添加 @asm 处理**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 在 switch 语句中添加 `AST_ASM` 分支
    - 调用 `check_asm_block` 函数
  - 验收标准:
    - 类型检查集成完成
    - 测试: `make test_checker_asm` 通过

---

### Day 5: 基础代码生成 ⏱️ 1天

#### Task 1.5: Codegen 实现简单指令生成
- [x] **实现 `gen_asm_block` 函数**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 生成临时变量声明
    - 生成内联汇编
    - 将结果复制到输出变量
  - 验收标准:
    - 能生成正确的 C99 内联汇编
    - 生成的代码可编译

- [x] **实现 `gen_asm_stmt` 函数**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 构建内联汇编字符串
    - 生成输出操作数
    - 生成输入操作数
    - 生成 clobbers 声明
  - 验收标准:
    - 单条指令正确生成
    - 多条指令正确处理

- [x] **添加临时变量生成函数**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/codegen/c99/utils.c`
  - 详情:
    - 实现 `gen_asm_temp_var` 函数
    - 生成唯一的临时变量名
  - 验收标准:
    - 变量名唯一
    - 格式规范

- [x] **在 `gen_expr` 中添加 @asm 处理**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 在 switch 语句中添加 `AST_ASM` 分支
    - 调用 `gen_asm_block` 函数
  - 验收标准:
    - 代码生成集成完成
    - 测试: `make test_codegen_asm` 通过

- [x] **创建基础测试用例**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/test_asm_basic.uya`
  - 详情:
    - 测试基本算术运算
    - 测试单条指令
    - 测试多条指令
  - 验收标准:
    - 基础测试通过
    - 生成的代码正确运行

---

### 阶段 1 交付物检查清单

- [x] Lexer 能识别 `@asm` 关键字
- [x] AST 包含完整的 @asm 节点结构
- [x] Parser 能正确解析基础语法
- [x] Checker 能进行基础类型检查
- [x] Codegen 能生成 C99 内联汇编
- [x] 基础测试用例通过 (`test_asm_basic.uya`)
- [x] 可以编译简单的 @asm 块
- [x] 生成的 C 代码可编译和运行

---

## 🚀 阶段 2: 核心功能 (第2周, 5-7天)

### 目标
完善类型安全、内存安全和并发安全机制,实现平台抽象基础。

---

### Day 6-7: 类型安全增强 ⏱️ 2天

#### Task 2.1: 完善输入/输出类型检查
- [x] **实现占位符类型推断**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 从指令模板中提取占位符
    - 推断占位符类型
    - 验证类型兼容性
  - 验收标准:
    - ✅ 占位符类型正确推断
    - ✅ 类型不匹配时给出清晰错误
    - 测试: `tests/programs/test_asm_placeholder.uya` 通过

- [x] **完善寄存器约束验证**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 验证显式寄存器声明
    - 检查寄存器与调用约定冲突
    - 验证平台特定寄存器
  - 验收标准:
    - ✅ 寄存器约束验证完整
    - ✅ 冲突时有清晰错误提示
    - 测试: `tests/programs/test_asm_type_safety.uya` 通过

- [x] **添加类型安全测试用例**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: 
    - `tests/programs/test_asm_type_safety.uya`
  - 详情:
    - 测试类型检查正确性
    - 测试类型不匹配错误
  - 验收标准:
    - ✅ 正确示例通过
    - ✅ 错误示例编译失败
    - 测试结果: 所有类型安全测试通过

---

### Day 8-9: 内存安全验证 ⏱️ 2天

#### Task 2.2: 实现内存安全验证
- [x] **实现指针类型安全检查**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 验证 `@asm_mem` 类型使用正确
    - 检查 FFI 指针不能直接使用
    - 验证指针类型转换
  - 验收标准:
    - ✅ 指针类型检查完整
    - ✅ 不安全操作被拒绝
    - 测试: `tests/programs/test_asm_memory_safety.uya` 通过

- [x] **实现内存操作类型验证**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 验证内存操作的类型安全
    - 检查内存操作语义
    - 确保不会越界访问(编译期可证明时)
  - 验收标准:
    - ✅ 内存操作类型验证完整
    - ✅ 潜在不安全操作有警告

- [ ] **实现越界访问检测(可选)**
  - 优先级: P1
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 编译期静态分析
    - 检测数组越界风险
    - 报告潜在问题
  - 验收标准:
    - 能检测简单越界情况
    - 误报率低

- [x] **添加内存安全测试用例**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: 
    - `tests/programs/test_asm_memory_safety.uya`
  - 详情:
    - 测试内存安全操作
    - 测试边界检查
  - 验收标准:
    - ✅ 安全操作通过
    - ✅ 不安全操作被拒绝
    - 测试结果: 所有内存安全测试通过

---

### Day 10-11: 并发安全验证 ⏱️ 2天

#### Task 2.3: 实现并发安全验证
- [ ] **实现原子操作类型检查**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 验证原子操作使用 `atomic T` 类型
    - 检查原子操作语义正确性
    - 验证内存屏障指令
  - 验收标准:
    - 原子操作类型检查完整
    - 非原子类型操作被拒绝

- [ ] **实现数据竞争检测(基础)**
  - 优先级: P1
  - 预计时间: 4小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 静态分析数据竞争风险
    - 检测未同步的共享内存访问
    - 报告潜在数据竞争
  - 验收标准:
    - 能检测明显的数据竞争
    - 有清晰的警告信息

- [ ] **添加并发安全测试用例**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: 
    - `tests/programs/test_asm_atomic_ops.uya`
    - `tests/programs/test_asm_concurrent_counter.uya`
  - 详情:
    - 测试原子操作
    - 测试并发计数器
  - 验收标准:
    - 原子操作测试通过
    - 并发测试正确运行

---

### Day 12: 平台抽象 ⏱️ 1天

#### Task 2.4: 实现平台检测
- [ ] **创建平台检测文件**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/codegen/c99/platform.c`
  - 详情:
    - 实现 `get_target_platform` 函数
    - 支持 x86-64、ARM64 等平台
    - 支持不同操作系统
  - 验收标准:
    - 平台检测正确
    - 所有目标平台支持

- [ ] **实现 `@asm_target()` 内置函数**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: 
    - `compiler-c/src/lexer.c`
    - `compiler-c/src/parser.c`
    - `compiler-c/src/checker.c`
    - `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - Lexer 识别 `@asm_target`
    - Parser 解析函数调用
    - Checker 验证类型
    - Codegen 生成平台检测代码
  - 验收标准:
    - `@asm_target()` 函数可用
    - 返回正确的平台枚举值

- [ ] **实现平台特定寄存器类型**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: 
    - `compiler-c/src/types.h`
    - `compiler-c/src/codegen/c99/platform.c`
  - 详情:
    - 添加 x86-64 寄存器类型
    - 添加 ARM64 寄存器类型
    - 实现寄存器约束映射
  - 验收标准:
    - 平台特定寄存器类型可用
    - 寄存器约束正确映射

- [ ] **实现条件编译支持**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 支持 `if @asm_target() == .x86_64_linux` 语法
    - 生成平台特定代码
    - 排除其他平台代码
  - 验收标准:
    - 条件编译正确工作
    - 生成高效的代码

- [ ] **添加跨平台测试用例**
  - 优先级: P0
  - 预计时间: 1小时
  - 文件: 
    - `tests/programs/test_asm_platform_detection.uya`
    - `tests/programs/test_asm_platform_x86_64.uya`
  - 详情:
    - 测试平台检测
    - 测试平台特定代码
  - 验收标准:
    - 平台检测测试通过
    - 平台特定代码正确运行

---

### 阶段 2 交付物检查清单

- [x] 完整的类型安全验证
- [x] 寄存器约束验证
- [x] 占位符类型推断
- [x] 内存安全验证
- [x] 指针类型安全检查
- [ ] 并发安全验证
- [ ] 原子操作类型检查
- [ ] 平台检测功能
- [ ] 条件编译支持
- [x] 所有类型安全测试通过
- [x] 所有内存安全测试通过
- [ ] 所有并发安全测试通过
- [ ] 所有平台检测测试通过

---

## ⚡ 阶段 3: 优化和测试 (第3周, 5-7天)

### 目标
性能优化、跨平台支持、完整测试、文档完善。

---

### Day 13-14: 代码生成优化 ⏱️ 2天

#### Task 3.1: 编译期优化
- [ ] **实现编译期常量折叠**
  - 优先级: P1
  - 预计时间: 3小时
  - 文件: `compiler-c/src/checker.c`
  - 详情:
    - 检测常量指令
    - 编译期计算结果
    - 直接替换为常量
  - 验收标准:
    - 常量指令被优化
    - 生成的代码更高效

- [ ] **实现指令融合**
  - 优先级: P2
  - 预计时间: 4小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 检测可融合的指令序列
    - 合并为单条指令
    - 减少指令数量
  - 验收标准:
    - 指令融合正确
    - 性能提升明显

- [ ] **实现冗余消除**
  - 优先级: P2
  - 预计时间: 3小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 检测冗余的指令
    - 删除无用指令
    - 优化寄存器使用
  - 验收标准:
    - 冗余指令被消除
    - 代码大小减少

- [ ] **实现寄存器重用优化**
  - 优先级: P1
  - 预计时间: 3小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 分析寄存器生命周期
    - 重用不再需要的寄存器
    - 减少寄存器压力
  - 验收标准:
    - 寄存器使用更高效
    - 性能提升

---

### Day 15-16: 跨平台支持 ⏱️ 2天

#### Task 3.2: ARM64 平台支持
- [ ] **添加 ARM64 寄存器类型**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: 
    - `compiler-c/src/types.h`
    - `compiler-c/src/codegen/c99/platform.c`
  - 详情:
    - 定义 ARM64 寄存器类型
    - 实现寄存器约束映射
  - 验收标准:
    - ARM64 寄存器类型可用
    - 约束映射正确

- [ ] **实现 ARM64 代码生成**
  - 优先级: P0
  - 预计时间: 4小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 生成 ARM64 汇编语法
    - 处理不同的调用约定
    - 生成正确的寄存器操作
  - 验收标准:
    - ARM64 代码正确生成
    - 生成的代码可运行

- [ ] **添加 ARM64 测试用例**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/test_asm_platform_arm64.uya`
  - 详情:
    - 测试 ARM64 基本功能
    - 测试 ARM64 特定指令
  - 验收标准:
    - ARM64 测试通过
    - 跨平台代码正确

#### Task 3.3: RISC-V 平台支持(可选)
- [ ] **添加 RISC-V 寄存器类型**
  - 优先级: P2
  - 预计时间: 2小时
  - 文件: 
    - `compiler-c/src/types.h`
    - `compiler-c/src/codegen/c99/platform.c`
  - 详情:
    - 定义 RISC-V 寄存器类型
    - 实现寄存器约束映射
  - 验收标准:
    - RISC-V 寄存器类型可用

- [ ] **实现 RISC-V 代码生成**
  - 优先级: P2
  - 预计时间: 4小时
  - 文件: `compiler-c/src/codegen/c99/expr.c`
  - 详情:
    - 生成 RISC-V 汇编语法
    - 处理 RISC-V 调用约定
  - 验收标准:
    - RISC-V 代码正确生成

---

### Day 17-18: 完整测试 ⏱️ 2天

#### Task 3.4: 单元测试完善
- [x] **完善基础功能测试**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `tests/test_asm_basic.uya`, `tests/test_asm_types.uya`, `tests/test_asm_clobbers.uya`
  - 详情:
    - 添加更多算术运算测试
    - 添加位运算测试
    - 添加控制流测试
  - 验收标准:
    - ✅ 所有基础测试通过
    - ✅ 覆盖率 100%

- [x] **完善类型安全测试**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/error_asm_invalid_input_type.uya`, `tests/error_asm_invalid_output_type.uya`
  - 详情:
    - 测试类型检查正确性
    - 测试类型不匹配错误
  - 验收标准:
    - ✅ 正确示例通过
    - ✅ 错误示例编译失败

- [x] **完善边界情况测试**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/test_asm_edge_cases.uya`, `tests/test_asm_codegen.uya`
  - 详情:
    - 测试最大输入/输出限制
    - 测试空指令
    - 测试控制流中使用
  - 验收标准:
    - ✅ 边界情况测试通过

- [x] **完善系统调用测试**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/test_asm_syscall.uya`
  - 详情:
    - 测试更多系统调用
    - 测试错误处理
  - 验收标准:
    - ✅ 所有系统调用测试通过

- [ ] **完善内存操作测试**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/test_asm_memory.uya`
  - 详情:
    - 测试不同大小的内存操作
    - 测试内存拷贝
  - 验收标准:
    - 所有内存操作测试通过

#### Task 3.5: 性能基准测试
- [ ] **实现内存拷贝性能测试**
  - 优先级: P0
  - 预计时间: 3小时
  - 文件: `tests/programs/bench_asm_memcpy.uya`
  - 详情:
    - 对比 @asm 与 memcpy 性能
    - 测试不同数据大小
    - 测试 SIMD 优化效果
  - 验收标准:
    - 性能与 C99 内联汇编一致
    - 性能差异 < 1%

- [ ] **实现原子操作性能测试**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/bench_asm_atomic.uya`
  - 详情:
    - 对比 @asm 与 std.atomic 性能
    - 测试不同原子操作
  - 验收标准:
    - 性能与 C99 内联汇编一致

- [ ] **实现字符串操作性能测试**
  - 优先级: P1
  - 预计时间: 2小时
  - 文件: `tests/programs/bench_asm_strlen.uya`
  - 详情:
    - 对比 @asm 与标准库性能
    - 测试 SIMD 优化效果
  - 验收标准:
    - 性能与 C99 内联汇编一致

#### Task 3.6: 集成测试
- [ ] **创建集成测试脚本**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `tests/programs/run_asm_tests.sh`
  - 详情:
    - 自动化运行所有测试
    - 生成测试报告
    - 统计覆盖率
  - 验收标准:
    - 所有测试自动运行
    - 报告清晰完整

- [ ] **跨平台测试**
  - 优先级: P0
  - 预计时间: 3小时
  - 详情:
    - 在 x86-64 平台测试
    - 在 ARM64 平台测试(如有硬件)
    - 验证跨平台兼容性
  - 验收标准:
    - 所有平台测试通过
    - 跨平台代码正确

---

### Day 19: 文档和示例 ⏱️ 1天

#### Task 3.7: 文档完善
- [ ] **完善 API 文档**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `docs/asm_api_reference.md`
  - 详情:
    - 补充缺失的示例
    - 更新 API 说明
    - 添加常见问题解答
  - 验收标准:
    - 文档完整准确
    - 示例可运行

- [ ] **创建使用指南**
  - 优先级: P1
  - 预计时间: 2小时
  - 文件: `docs/asm_usage_guide.md`
  - 详情:
    - 创建详细的使用指南
    - 包含最佳实践
    - 包含常见陷阱
  - 验收标准:
    - 指南清晰易懂
    - 覆盖主要使用场景

- [ ] **创建最佳实践文档**
  - 优先级: P1
  - 预计时间: 2小时
  - 文件: `docs/asm_best_practices.md`
  - 详情:
    - 性能优化建议
    - 安全性建议
    - 可移植性建议
  - 验收标准:
    - 建议实用有效
    - 有示例代码

#### Task 3.8: 示例代码完善
- [ ] **完善演示代码**
  - 优先级: P0
  - 预计时间: 2小时
  - 文件: `examples/demo_asm.uya`
  - 详情:
    - 添加更多示例
    - 添加注释说明
    - 确保代码可运行
  - 验收标准:
    - 示例完整
    - 代码可编译运行

- [ ] **创建实际应用示例**
  - 优先级: P1
  - 预计时间: 3小时
  - 文件: 
    - `examples/example_string.uya`
    - `examples/example_math.uya`
    - `examples/example_crypto.uya`
  - 详情:
    - 字符串操作示例
    - 数学运算示例
    - 加密算法示例
  - 验收标准:
    - 示例实用
    - 代码质量高

---

### 阶段 3 交付物检查清单

- [ ] 编译期优化实现
- [ ] 常量折叠功能
- [ ] 指令融合功能(可选)
- [ ] 冗余消除功能(可选)
- [ ] ARM64 平台支持
- [ ] RISC-V 平台支持(可选)
- [ ] 所有单元测试通过
- [ ] 所有性能测试通过
- [ ] 集成测试脚本完成
- [ ] 跨平台测试通过
- [ ] API 文档完善
- [ ] 使用指南完成
- [ ] 最佳实践文档完成
- [ ] 示例代码完善
- [ ] 代码覆盖率 > 90%
- [ ] 性能与 C99 内联汇编一致

---

## 📊 验收标准

### 功能完整性
- [x] 所有基础功能测试通过
- [x] 所有类型安全测试通过
- [ ] 所有内存安全测试通过
- [ ] 所有并发安全测试通过
- [ ] 所有平台检测测试通过

### 性能指标
- [ ] @asm 生成的代码与 C99 内联汇编性能一致(误差 < 1%)
- [ ] 编译时间增加 < 5%
- [ ] 生成的代码大小增加 < 2%

### 代码质量
- [ ] 代码覆盖率 > 90%
- [ ] 无内存泄漏
- [ ] 无编译警告
- [ ] 符合代码规范

---

## 🔧 开发环境设置

### 编译器
```bash
# 编译 C 版编译器
cd compiler-c
make clean
make build

# 编译自举编译器
cd src && ./compile.sh --c99 -e && cd ..
```

### 运行测试
```bash
# 运行单个测试
bin/uya --c99 tests/programs/test_asm_basic.uya
gcc tests/programs/build/test_asm_basic.c -o test_asm_basic
./test_asm_basic

# 运行所有 @asm 测试
cd tests/programs
./run_asm_tests.sh
```

### 调试
```bash
# 启用详细输出
bin/uya --c99 --verbose tests/programs/test_asm_basic.uya

# 查看生成的 C 代码
cat tests/programs/build/test_asm_basic.c

# 使用 GDB 调试
gdb ./test_asm_basic
```

---

## 📝 注意事项

### 设计规则(必须遵守)
1. **输出变量声明**: @asm 块的输出变量必须在块外显式声明
2. **类型转换**: i64 → i32 必须使用 `as!` (可能溢出)
3. **寄存器混用**: 自动分配(`@asm_reg`)与显式寄存器不得在同一 @asm 块中混用
4. **内存安全**: FFI 指针不能直接使用,必须转换为 `@asm_mem`
5. **原子操作**: 必须使用 `atomic T` 类型

### 编码规范
- 所有新增代码必须包含单元测试
- 所有公共 API 必须有文档注释
- 遵循现有代码风格
- 使用有意义的变量名
- 避免魔术数字,使用常量

### 提交规范
- 每个 commit 只做一件事
- commit message 清晰描述改动
- 大改动拆分为多个小 commit
- 每个 commit 都能独立编译和测试

---

## 📈 进度追踪

### 每日检查清单
- [ ] 更新本文档的任务状态
- [ ] 提交代码到版本控制
- [ ] 运行测试确保无回归
- [ ] 更新相关文档

### 每周检查清单
- [ ] 审查本周完成的任务
- [ ] 规划下周任务
- [ ] 更新进度报告
- [ ] 团队会议讨论问题

### 里程碑
- **第1周结束**: 阶段1完成,基础功能可用
- **第2周结束**: 阶段2完成,核心功能完善
- **第3周结束**: 阶段3完成,全部验收通过

---

## 🆘 风险和应对

### 技术风险
| 风险 | 概率 | 影响 | 应对方案 |
|------|------|------|----------|
| 寄存器分配复杂度高 | 中 | 高 | 初期使用 GCC/Clang 自动分配 |
| 跨平台支持困难 | 中 | 中 | 先实现 x86-64,逐步扩展 |
| 性能不如预期 | 低 | 高 | 提前基准测试,根据结果优化 |

### 进度风险
| 风险 | 概率 | 影响 | 应对方案 |
|------|------|------|----------|
| 实现时间超出预期 | 中 | 高 | 按优先级分阶段实施 |
| 测试用例不足 | 中 | 中 | 边开发边测试,增加覆盖率 |
| 文档不完善 | 低 | 中 | 及时更新文档 |

---

## 📚 参考资料

- **设计文档**: `docs/asm_design.md`
- **实施计划**: `docs/asm_implementation_plan.md`
- **API 参考**: `docs/asm_api_reference.md`
- **测试文档**: `tests/programs/README_asm.md`
- **GCC Inline Assembly**: https://gcc.gnu.org/onlinedocs/gcc/Extended-Asm.html
- **System V AMD64 ABI**: https://refspecs.linuxbase.org/elf/x86_64-abi-0.99.pdf

---

## 🎉 完成标志

当以下所有条件满足时,项目视为完成:

1. ✅ 所有 P0 优先级任务完成
2. ✅ 所有测试通过
3. ✅ 代码覆盖率 > 90%
4. ✅ 性能指标达标
5. ✅ 文档完善
6. ✅ 代码审查通过
7. ✅ 无未解决的 bug
8. ✅ 可以成功编译和运行示例代码

---

**最后更新**: 2026-02-22
**下次审查**: 每周五
**维护者**: Uya 开发团队
