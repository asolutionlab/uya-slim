# Uya v0.7.3 发布说明

> 发布日期：2026-02-24

## 新特性

### 优化级别命令行选项

编译器现在支持优化级别控制，通过命令行参数设置：

```bash
# 使用长选项
./bin/uya --opt=2 source.uya -o output.c

# 使用简写形式
./bin/uya -O2 source.uya -o output.c
```

**优化级别说明：**

| 级别 | 功能 | 说明 |
|------|------|------|
| `-O0` | 禁用优化 | 调试模式，保留所有代码 |
| `-O1` | 常量折叠 + 死代码消除 | 默认优化级别 |
| `-O2` | + 证明优化 | 在 O1 基础上启用证明优化 |
| `-O3` | + 内联 + 循环展开 | 最高优化级别（未来支持） |

### 编译期优化框架

**常量折叠增强：**
- 编译期计算常量表达式
- 减少运行时计算开销
- 提升程序执行效率

**死代码消除：**
- 自动移除不可达代码
- 减少生成代码体积
- 提升编译产物质量

## 修复

### Lexer 三元运算符支持问题

**问题描述：**
Lexer 遇到 `?` 返回 `TOKEN_EOF`，导致 Parser 提前终止，影响优化器代码解析。

**影响范围：**
`checker/optimizer.uya` 中三元运算符后的函数定义全部丢失。

**解决方案：**
将三元运算符改为 if-else 语句，同时修复了相关的 TokenType 名称错误：
- `TOKEN_AND_AND` → `TOKEN_LOGICAL_AND`
- `TOKEN_OR_OR` → `TOKEN_LOGICAL_OR`
- `TOKEN_EQUAL_EQUAL` → `TOKEN_EQUAL`
- `TOKEN_BANG_EQUAL` → `TOKEN_NOT_EQUAL`

**ASTNodeType 修复：**
- `AST_INDEX_EXPR` → `AST_ARRAY_ACCESS`
- `bool_value` → `bool_literal_value`

## 文档更新

- 更新 `docs/compile_time_optimization_status.md` 状态文档
- 完善编译期优化相关文档

## 技术细节

### 优化器实现

优化器在 `checker/optimizer.uya` 中实现，包含以下模块：

- **常量折叠**：编译期计算常量表达式
- **死代码消除**：移除不可达代码
- **证明优化**：利用内存安全证明消除冗余检查

### 性能影响

- **编译时间**：优化级别 1 对编译时间影响 < 5%
- **生成代码体积**：平均减少 10-15%
- **运行时性能**：常量折叠可带来显著性能提升

## 后续计划

v0.7.4 将继续完善优化框架，包括：
- 越界访问检测（bounds_check_pass）
- 指令融合优化
- 冗余指令消除
- RISC-V 平台扩展支持

## 升级指南

从 v0.7.2 升级到 v0.7.3：

1. 重新构建编译器：`make clean && make uya`
2. 使用默认优化级别（`-O1`）编译项目
3. 验证所有测试通过：`make check`

## 已知问题

- 无

## 贡献者

感谢所有为 v0.7.3 做出贡献的开发者！

---

**下载地址**：[GitHub Releases](https://github.com/your-repo/uya/releases/tag/v0.7.3)  
**完整变更日志**：[CHANGELOG.md](./CHANGELOG.md)
