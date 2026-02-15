# Uya v0.3.4 版本说明

**发布日期**：2026-02-15

本版本完成 **测试框架全面迁移**（297 文件变更），并修复自举编译器与 C 编译器的关键 bug，实现完全同步。**348 个测试全部通过，自举对比一致**。

---

## 核心亮点

### 1. 测试框架全面迁移

**完成进度**：348/348 测试文件迁移至 `std.testing` 框架

**迁移模式**：
```uya
// 旧格式
fn main() i32 {
    test "description" {
        assert_eq_i32(actual, expected, "message");
    }
    return 0;
}

// 新格式（std.testing 框架）
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

**迁移成果**：
- 297 个文件变更
- 统一的测试报告格式
- 错误自动传播（`!void` 返回类型）
- 零依赖编译（无需 bridge.c）

### 2. 编译器关键 Bug 修复

**自举编译器修复**：

|| 问题 | 修复 |
|------|------|
| 宏展开未覆盖 test/catch/try/match | 在 `expand_macros_in_node_simple` 添加 `AST_TEST_STMT`、`AST_CATCH_EXPR`、`AST_TRY_EXPR`、`AST_MATCH_EXPR` 处理 |
| err_union 结构体生成顺序不一致 | 延迟生成 + 按名称排序 |
| void* 类型命名错误 | `*` → `ptr` 替换 |
| err_union offset 计算错误 | 修正为 17（`struct err_union_` 长度） |

**C 编译器同步**：
- 添加 `AST_TYPE_ERROR_UNION` 类型收集
- 添加 `AST_METHOD_BLOCK` 方法块处理
- 延迟 err_union 结构体生成
- 与自举编译器输出完全一致

### 3. 编译器同步里程碑

**验证结果**：
```bash
make tests-c     # C 编译器：348/348 通过
make tests-uya   # 自举编译器：348/348 通过
make b           # 自举对比一致 ✓
```

**意义**：C 编译器与自举编译器行为完全同步，自举可信度达 100%。

---

## 技术细节

### 宏展开修复（checker.uya）

```uya
// 在 expand_macros_in_node_simple 中添加
} else if node.type == ASTNodeType.AST_TEST_STMT {
    expand_macros_in_node_simple(checker, &node.test_stmt_body);
} else if node.type == ASTNodeType.AST_CATCH_EXPR {
    expand_macros_in_node_simple(checker, &node.catch_expr_operand);
    expand_macros_in_node_simple(checker, &node.catch_expr_catch_block);
} else if node.type == ASTNodeType.AST_TRY_EXPR {
    expand_macros_in_node_simple(checker, &node.try_expr_operand);
} else if node.type == ASTNodeType.AST_MATCH_EXPR {
    expand_macros_in_node_simple(checker, &node.match_expr_expr);
    // ... arms 处理
}
```

### err_union 延迟生成（types.c）

```c
// 延迟收集
#define C99_MAX_ERR_UNION_STRUCTS 64
const char *err_union_struct_names[C99_MAX_ERR_UNION_STRUCTS];
ASTNode *err_union_payload_types[C99_MAX_ERR_UNION_STRUCTS];
int err_union_struct_count;

// 在函数原型前统一生成
void emit_pending_err_union_structs(C99CodeGenerator *codegen);
```

### 方法块类型收集（main.c）

```c
case AST_METHOD_BLOCK:
    for (int i = 0; i < node->data.method_block.method_count; i++) {
        ASTNode *m = node->data.method_block.methods[i];
        if (m && m->type == AST_FN_DECL) {
            // 收集返回类型中的 slice 和 err_union
            if (m->data.fn_decl.return_type) {
                if (m->data.fn_decl.return_type->type == AST_TYPE_SLICE || 
                    m->data.fn_decl.return_type->type == AST_TYPE_ERROR_UNION) {
                    (void)c99_type_to_c(codegen, m->data.fn_decl.return_type);
                }
                collect_slice_types_from_node(codegen, m->data.fn_decl.return_type);
            }
        }
    }
    break;
```

---

## 文件变更统计

|| 类别 | 变更 |
|------|------|
| 总提交数 | 45 |
| 文件变更 | 297 个文件 |
| 行数变更 | +8839 / -8492 |

**主要模块**：
- `tests/programs/`：全部测试迁移至 std.testing 框架
- `src/checker.uya`：宏展开修复
- `compiler-c/src/`：C 编译器同步修复
- `lib/std/testing/`：测试框架核心

---

## 版本对比

### v0.3.3 → v0.3.4 变更摘要

|| 类别 | 内容 |
|------|------|
| **测试迁移** | 348 个测试全部迁移至 std.testing 框架 |
| **宏展开** | 修复 test/catch/try/match 语句宏展开 |
| **err_union** | 延迟生成 + 排序，C 编译器与自举同步 |
| **类型收集** | 方法块中的 err_union 类型正确收集 |
| **自举验证** | make b 通过，编译器输出一致 |

---

## 相关资源

- **语言规范**：`docs/uya.md`（v0.46）
- **测试规范**：`docs/testing_guide.md`（v1.1.0）
- **变更日志**：`docs/changelog.md`
- **上一版说明**：`docs/RELEASE_v0.3.3.md`

---

**v0.3.4 完成测试框架全面迁移和编译器关键修复，实现 C 编译器与自举编译器完全同步，为后续语言特性扩展奠定坚实基础。**
