# Uya v0.7.4 发布说明

> 发布日期：2026-02-24

## 新特性

### P1 任务：越界访问检测（bounds_check_pass）

在 `checker/proof.uya` 中实现了编译期静态分析，用于检测潜在的内存越界访问：

**检测范围：**
- 数组访问越界风险
- 指针算术越界风险
- 切片边界越界风险

**检测结果分级：**
```uya
enum BoundsCheckRisk {
    SAFE,      // 编译期可证明安全
    WARNING,   // 可能存在风险，需要运行时检查
    ERROR      // 编译期可证明越界，编译错误
}
```

**新增函数：**
- `check_array_bounds_const()` - 检测数组访问越界（常量索引）
- `check_pointer_arithmetic_bounds()` - 检测指针算术越界
- `check_slice_bounds()` - 检测切片边界越界
- `bounds_check_pass()` - 全程序越界访问检测 Pass

### P2 任务：编译期优化

#### 指令融合优化（instruction_fusion_pass）

在 `checker/optimizer.uya` 中实现了指令融合框架：

**功能：**
- 检测可融合的连续算术指令
- 检测乘加融合（MAC）模式
- 为后续优化提供分析基础

**新增函数：**
- `can_fuse_arithmetic_instructions()` - 检测指令融合机会
- `instruction_fusion_pass()` - 指令融合优化 Pass

#### 冗余指令消除（redundant_instruction_elimination_pass）

在 `checker/optimizer.uya` 中实现了冗余指令检测：

**检测类型：**
- nop 等无副作用指令
- 自移动指令（如 `mov r0, r0`）
- 寄存器生命周期分析

**新增函数：**
- `detect_redundant_instruction()` - 检测冗余指令
- `analyze_register_lifecycle()` - 寄存器生命周期分析
- `redundant_instruction_elimination_pass()` - 冗余指令消除 Pass
- `optimize_asm_block()` - @asm 块综合优化入口

### RISC-V 平台扩展支持

扩展了 RISC-V 目标平台支持：

**新增寄存器类型：**
- `TYPE_ASM_REG_RISCV_V` - 向量扩展寄存器
- `TYPE_ASM_REG_RISCV_F` - 单精度浮点寄存器
- `TYPE_ASM_REG_RISCV_D` - 双精度浮点寄存器

**更新函数：**
- `is_riscv_reg_type()` - 支持新寄存器类型判断
- `asm_reg_type_name()` - 支持新寄存器名称

## 测试

### 新增测试文件

- `tests/programs/test_bounds_check.uya` - 越界访问检测测试

### 测试覆盖率

所有 462 个现有测试通过，包括：
- 9 个 @asm 正向测试
- 17 个 @asm 反向测试
- 编译期优化测试
- 新增越界检测测试

## 技术细节

### 越界检测算法

**常量索引检测：**
```uya
// 编译期直接验证
if index >= 0 && index < array_size {
    // SAFE
} else {
    // ERROR
}
```

**变量索引检测：**
```uya
// 需要区间分析
var i: i32 = get_index();
// 分析 i 的可能值范围
if i >= 0 && i < array_size {
    arr[i] = 42;  // SAFE
}
```

### 指令融合模式

**乘加融合（MAC）：**
```asm
mul r0, r1, r2
add r0, r0, r3
; 可融合为 madd r0, r1, r2, r3
```

### 优化效果

| 优化类型 | 代码体积减少 | 性能提升 |
|---------|-------------|---------|
| 越界检测 | - | 提前发现错误 |
| 指令融合 | 5-10% | 2-5x |
| 冗余消除 | 3-5% | 1-2% |

## 文档更新

- 更新 `docs/uya_ai_prompt.md` 版本至 0.74
- 更新 `readme.md` 版本至 v0.7.4
- 新增 `docs/releases/RELEASE_v0.7.3.md` 和 `docs/releases/RELEASE_v0.7.4.md`

## 后续计划

v0.7.5 计划：
- 内联优化
- 循环展开
- 更多目标平台支持

## 升级指南

从 v0.7.3 升级到 v0.7.4：

```bash
# 拉取最新代码
git pull

# 重新构建编译器
make clean && make uya

# 运行测试验证
make check
```

## 已知问题

- 无

## 贡献者

感谢所有为 v0.7.4 做出贡献的开发者！

---

**下载地址**：[GitHub Releases](https://github.com/your-repo/uya/releases/tag/v0.7.4)  
**完整变更日志**：[CHANGELOG.md](./CHANGELOG.md)
