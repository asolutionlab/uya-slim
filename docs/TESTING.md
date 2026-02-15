# Uya 回归测试说明

**版本**：v0.3.4+  
**更新日期**：2026-02-15

---

## 测试框架

自 v0.3.4 起，所有测试使用 `std.testing` 框架：

```uya
use std.testing.*;

fn test_feature() !void {
    try expect_eq(actual, expected, "description");
}

export fn main() i32 {
    test_suite_begin("Module Tests");
    run_test("feature", test_feature);
    return test_suite_end();
}
```

---

## 运行测试

### 完整测试套件

```bash
make tests-uya
```

输出示例：
```
================================
总计: 348 个测试
通过: 348
失败: 0
================================
```

### 并行测试

```bash
./tests/run_programs_parallel.sh
```

### 单个测试

```bash
bin/uya tests/programs/test_basic.uya -o /tmp/test.c --c99
gcc -std=c99 /tmp/test.c -o /tmp/test -lm
/tmp/test
```

---

## 测试分类

| 类别 | 文件前缀 | 数量 |
|------|----------|------|
| 基础语法 | `test_basic*.uya` | ~20 |
| 类型系统 | `test_type*.uya` | ~30 |
| 函数 | `test_fn*.uya` | ~15 |
| 结构体 | `test_struct*.uya` | ~20 |
| 联合体 | `test_union*.uya` | ~10 |
| 接口 | `test_interface*.uya` | ~10 |
| 错误处理 | `test_error*.uya`, `test_try*.uya` | ~15 |
| 宏 | `test_macro*.uya` | ~10 |
| 泛型 | `test_generic*.uya` | ~10 |
| 切片 | `test_slice*.uya` | ~15 |
| 指针 | `test_pointer*.uya` | ~20 |
| 标准库 | `test_std_*.uya` | ~20 |
| libc | `test_ctype.uya`, `test_stdio.uya` 等 | ~10 |
| 其他 | 其他 | ~143 |

---

## 自举验证

```bash
make b
```

自举验证流程：
1. `bin/uya` 编译 `src/*.uya` → `bin/uya_bootstrap.c`
2. 对比 `bin/uya.c` 与 `bin/uya_bootstrap.c`
3. 一致则通过

---

## 测试编写规范

### 断言函数

| 函数 | 用途 |
|------|------|
| `expect_eq(actual, expected, msg)` | 通用相等断言 |
| `expect_true(cond, msg)` | 布尔断言 |
| `assert_eq_i32(a, b, msg)` | i32 相等 |
| `assert_eq_i64(a, b, msg)` | i64 相等 |
| `assert_eq_u64(a, b, msg)` | u64 相等 |

### 测试命名

- 文件名：`test_<功能>.uya`
- 测试函数：`test_<功能>_<场景>()`

### 错误处理

测试函数返回 `!void`，错误即测试失败：

```uya
fn test_division() !void {
    const result = divide(10, 2) catch |err| {
        return error.TestFailed;  // 显式失败
    };
    try expect_eq(result, 5, "10/2 should equal 5");
}
```

---

## CI 集成

推荐 CI 流程：

```yaml
test:
  script:
    - gcc -std=c99 -O2 bin/uya.c -o bin/uya -lm
    - make tests-uya
    - make b
```

---

## 测试覆盖率

当前状态：
- **总测试数**：348
- **通过率**：100%
- **自举验证**：通过

---

## 相关文档

- **开发指导**：[DEVELOPMENT.md](./DEVELOPMENT.md)
- **测试框架源码**：`lib/std/testing/testing.uya`
- **测试规范**：[testing_guide.md](./testing_guide.md)
