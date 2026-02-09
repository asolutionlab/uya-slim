# Uya v0.2.32 版本说明

发布日期：2026-02-06

---

## 🎯 版本概述

v0.2.32 版本主要增强了数字字面量的表达能力，添加了多进制支持和下划线分隔符，同时修复了系统调用相关测试和只读指针类型测试的问题。本版本提升了代码的可读性和类型安全性。

---

## ✨ 新增特性

### 1. 数字字面量增强

#### 多进制整数字面量

- **十六进制**：`0xFF`、`0x1A2B`、`0XDEAD_BEEF`（`0x` 或 `0X` 前缀）
- **八进制**：`0o755`、`0O644`、`0o7_777`（`0o` 或 `0O` 前缀）
- **二进制**：`0b1010`、`0B1111_0000`（`0b` 或 `0B` 前缀）

#### 下划线分隔符

数字中可以包含下划线 `_` 提高可读性：

```uya
const million: i32 = 1_000_000;
const hex_color: i32 = 0xFF_00_AA;
const permissions: i32 = 0o7_7_7;
const pi: f64 = 3.141_592_653;
```

**规则**：
- 下划线可以出现在任意两个数字之间
- 下划线不能出现在开头、结尾或连续出现
- 下划线不能紧跟在进制前缀之后（如 `0x_FF` 非法，`0xFF_00` 合法）

#### 浮点字面量

浮点字面量也支持下划线分隔符（仅限十进制）：

```uya
const e: f64 = 2.718_281_828;
const large: f64 = 1_000.5;
const scientific: f64 = 1.0e1_0;  // 10000000000.0
```

---

## 🔧 实现细节

### 编译器修改

1. **Lexer** (`compiler-mini/src/lexer.c`)
   - 扩展 `read_number` 函数，识别 `0x`/`0o`/`0b` 前缀
   - 支持下划线分隔符，带完整的语法验证
   - 错误检测（连续下划线、末尾下划线、前缀后下划线等）

2. **Parser** (`compiler-mini/src/parser.c`)
   - 添加 `remove_underscores` 辅助函数
   - 添加 `parse_integer_literal` 解析不同进制（使用 `strtol`）
   - 添加 `parse_float_literal` 处理浮点下划线

3. **AST/Checker**
   - 无需修改（整数在 Parser 阶段已转换为统一的十进制值）

4. **Codegen**
   - 无需修改（生成标准十进制 C 字面量）

### 规范文档更新

- `compiler-c-spec/UYA_MINI_SPEC.md` § 3.2 - 完整 BNF 语法
- `uya.md` - 数字字面量语法说明
- `grammar_formal.md` - 终结符定义更新
- `grammar_quick.md` - 类型系统速查表更新

---

## 🐛 Bug 修复

### 系统调用测试修复

1. **test_std_syscall.uya** 修复
   - 不再依赖模块系统，直接定义 syscall 封装函数
   - 修正 `*byte` 类型使用（替换错误的 `*const uint8`）

2. **test_syscall_module.uya** 修复
   - 修复 `struct err_union_int64_t` 重复定义问题
   - 在 `compiler-mini/src/codegen/c99/main.c` 中标记结构体为已定义
   - 修复错误联合类型返回值问题
   - 在 `compiler-mini/src/codegen/c99/stmt.c` 中检测表达式是否已是错误联合类型

### 只读指针类型测试修复

3. **&const T 语法测试用例修复**
   - 修复 `test_const_pointer.uya`：将嵌套函数移到顶层（Uya 不支持函数内嵌套函数）
   - 验证 `test_const_pointer_simple.uya` 通过测试
   - 更新 `test_export_for_c_complete.uya`：使用 `&const byte` 替代 `&byte`，符合只读指针语义
   - 确认 parser 代码中的 `&const T` 处理逻辑（第 316-321 行）正确工作
   - **说明**：`&const T` 语法在 v0.2.31 中已实现，本版本修复了测试用例中的语法错误，验证了功能的正确性

---

## 📊 测试覆盖

### 新增测试

- `compiler-mini/tests/programs/test_number_literals.uya`
  - 测试所有进制的整数字面量
  - 测试下划线分隔符
  - 测试浮点字面量（带下划线）
  - 验证运行时值的正确性

### 回归测试

✅ **所有测试全部通过**，包括：
- 新增的数字字面量测试（`test_number_literals.uya`）
- 修复后的系统调用测试（`test_std_syscall.uya`、`test_syscall_module.uya`）
- 修复后的只读指针类型测试（`test_const_pointer.uya`、`test_const_pointer_simple.uya`）
- 更新的函数导出测试（`test_export_for_c_complete.uya`）
- 所有原有功能测试

---

## 📚 文档

### 新增文档

- `compiler-mini/docs/number_literals_enhancement.md` - 功能详细说明

### 更新文档

- `compiler-c-spec/UYA_MINI_SPEC.md` - BNF 语法更新
- `uya.md` - 数字字面量章节更新
- `grammar_formal.md` - 终结符定义更新
- `grammar_quick.md` - 类型系统速查表更新
- `compiler-mini/todo_mini_to_full.md` - 进度跟踪更新

---

## 📖 使用示例

```uya
fn main() i32 {
    // 多进制整数
    const hex: i32 = 0xFF_00_AA;      // 十六进制：16711850
    const oct: i32 = 0o755;            // 八进制：493
    const bin: i32 = 0b1111_0000;      // 二进制：240
    const dec: i32 = 1_000_000;        // 十进制：1000000
    
    // 浮点字面量（带下划线）
    const pi: f64 = 3.141_592_653;
    const big: f64 = 1_000.5;
    const sci: f64 = 1.0e1_0;          // 10000000000.0
    
    // 常见用例
    const file_perms: i32 = 0o644;     // 文件权限
    const color: i32 = 0xFF_AA_BB;     // RGB 颜色
    const mask: i32 = 0b1111_0000;     // 位掩码
    
    return 0;
}
```

---

## 🔄 向后兼容性

✅ **完全向后兼容**

- 不使用新语法的代码仍然有效
- 所有原有测试通过
- 与 C99 互操作无变化

---

## ⚠️ 限制与已知问题

1. 浮点字面量仅支持十进制（不支持 `0x1.0p10` 等十六进制浮点）
2. 自举编译器（`uya-src/`）尚未同步更新（标记为后续工作）
3. 整数在解析阶段统一转为 `i32`，不保留原始进制信息
4. Uya 不支持函数内嵌套函数定义（函数必须在顶层定义）

---

## 🚀 后续计划

### v0.3.0（目标：2026 Q1）- 标准库里程碑

- 标准库基础设施（`std.c` 完整实现）
  - `@syscall` 内置函数（Linux x86-64 系统调用）
  - `std.c.syscall` 核心模块
  - `std.c.string`、`std.c.stdio`、`std.c.stdlib`
- `@print`/`@println` 内置函数
  - Hosted vs. Freestanding 模式
  - 零外部依赖（-nostdlib 构建）
- `--outlibc` 生成独立 C 库

---

## 🙏 致谢

感谢所有参与测试和反馈的开发者！

---

**完整变更日志**：见 [todo_mini_to_full.md](compiler-mini/todo_mini_to_full.md)

**问题反馈**：请在项目 Issue 中提交

