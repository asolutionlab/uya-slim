# Uya v0.5.8 版本说明

**发布日期：** 2026年2月19日

## 里程碑：编译器零依赖构建

本版本实现编译器完全静态链接，零外部依赖。编译器现在可以独立运行，不依赖任何 C 标准库或系统动态库。

---

## 核心功能

### 1. 编译器 -nostdlib 构建（Sprint 4）

- **完全静态链接**：`ldd bin/uya` 显示"不是动态可执行文件"
- **零未定义符号**：`nm bin/uya | grep ' U '` 无输出
- **自定义启动代码**：使用 C 内联汇编实现 `_start`
- **纯 Uya 标准库**：编译器使用自实现的 Uya 标准库，不再依赖 C 标准库

### 2. 约束证明系统增强

- **交换律支持**：`10 > i` 等价于 `i < 10`
- **线性表达式支持**：`i + offset < n` 转换为 `i < n - offset`
- **const 变量识别**：`if i < N { }` 其中 N 是 const 变量
- **错误去重**：同一 (变量名, 数组大小) 只报告一次安全证明错误

---

## 使用示例

### 边界检查增强

```uya
// 交换律：10 > i 等价于 i < 10
fn process(arr: [i32: 10], i: i32) i32 {
    if 10 > i && i >= 0 {  // 现在可以正确识别
        return arr[i];
    }
    return -1;
}

// 线性表达式：i + 1 < @len(arr)
fn next(arr: [i32: 10], i: i32) i32 {
    if i + 1 < @len(arr) {  // 自动推导 i < 9
        return arr[i + 1];
    }
    return -1;
}

// const 变量边界
const MAX_SIZE: i32 = 100;
fn safe_access(arr: [i32: 100], i: i32) i32 {
    if i < MAX_SIZE {  // 识别 const 变量
        return arr[i];
    }
    return -1;
}
```

### 静态链接编译器

```bash
# 默认构建（静态链接，零依赖）
make uya

# 验证无外部依赖
ldd bin/uya
# 输出: 不是动态可执行文件

# 调试构建（标准库链接）
make uya-std
```

---

## 文件变更

### 编译器构建
- `Makefile` - 默认静态链接，新增 `uya-std` 目标
- `compile.sh` - 支持 `--nostdlib` 模式，内联 `_start` 汇编
- `lib/std/runtime/entry/` - 移除独立启动文件，集成到 compile.sh

### 约束证明
- `src/checker.uya` - 增强约束系统
  - 交换律转换
  - 线性表达式简化
  - const 变量识别
  - 错误去重

### 测试
- 新增 5 个约束证明测试用例：
  - `test_swapped_comparison.uya` - 交换律
  - `test_linear_expr.uya` - 线性表达式
  - `test_else_branch.uya` - else 分支约束
  - `test_const_bounds.uya` - const 变量边界
  - `test_multi_access.uya` - 多次访问合并证明

---

## 技术改进

### 启动代码实现

```c
// 使用 __attribute__((naked)) 和内联汇编
__attribute__((naked)) void _start(void) {
    __asm__ volatile (
        "xor %%rbp, %%rbp\n"      // 清除帧指针
        "mov (%%rsp), %%rdi\n"    // argc
        "lea 8(%%rsp), %%rsi\n"   // argv
        "call main\n"             // 调用 main
        "mov %%eax, %%edi\n"      // 返回值
        "mov $60, %%eax\n"        // exit 系统调用
        "syscall\n"
        ::: "memory"
    );
}
```

### Makefile 变更

| 目标 | 说明 |
|------|------|
| `make uya` | 默认静态链接，零依赖 |
| `make uya-std` | 标准库链接，用于调试 |
| `make release` | 发布版本（-O3 优化 + strip） |

---

## 测试状态

- 自举验证：✓ 通过
- 单元测试：399/399 通过
- 静态链接验证：✓ 通过

---

## 贡献者

- winger - 核心开发

---

## 下一步计划

- [ ] 支持跨函数约束传播
- [ ] IDE 集成错误提示
- [ ] 更多非线性表达式分析

---

**编译自由，零依赖！**
