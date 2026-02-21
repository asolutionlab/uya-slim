# REFACTOR_PLAN_V2.md 可行性评审报告

## 总体评估

| 阶段 | 可行性 | 风险等级 | 建议 |
|------|--------|----------|------|
| 阶段一：巨型函数拆分 | ✅ 可行 | 低 | 直接执行 |
| 阶段二：嵌套深度优化 | ✅ 可行 | 低 | 直接执行 |
| 阶段三：重复代码提取 | ✅ 可行 | 低 | 直接执行 |
| **阶段四：Union 数据结构重构** | ❌ **不可行** | **高** | **需要重新设计** |
| 阶段五：测试现代化 | ✅ 可行 | 低 | 直接执行 |
| 阶段六：代码质量改进 | ✅ 可行 | 低 | 直接执行 |

---

## 详细分析

### 阶段一：巨型函数拆分 ✅

**可行性**：高

| 任务 | 问题 | 评估 |
|------|------|------|
| 1.1 checker_infer_type 拆分 | 1200 行 → 多个函数 | ✅ 可行，标准重构 |
| 1.2 gen_stmt 拆分 | 1593 行 → 多个函数 | ✅ 可行，标准重构 |
| 1.3 gen_expr 拆分 | 2000+ 行 → 多个函数 | ✅ 可行，标准重构 |

**工作量评估**：
- 文档预估：9-15 天
- 实际预估：**7-10 天**（更乐观）
- 原因：拆分模式成熟，风险低

**建议**：
- 使用 match 表达式作为分派器是正确的
- 可以先拆分 checker_infer_type 验证模式

---

### 阶段二：嵌套深度优化 ✅

**可行性**：高

| 任务 | 评估 |
|------|------|
| 2.1 提前返回模式 | ✅ 可行，机械重构 |
| 2.2 提取辅助函数 | ✅ 可行 |

**工作量评估**：
- 文档预估：4-5 天
- 实际预估：**3-4 天**
- 原因：模式简单，自动化程度高

---

### 阶段三：重复代码提取 ✅

**可行性**：高

| 任务 | 评估 |
|------|------|
| 3.1 Type 初始化辅助函数 | ✅ 可行 |
| 3.2 代码生成辅助函数 | ✅ 可行 |
| 3.3 类型检查函数统一 | ✅ 可行 |

**工作量评估**：
- 文档预估：2.5 天
- 实际预估：**2 天**
- 原因：辅助函数已存在部分实现

---

### 阶段四：Union 数据结构重构 ❌ 不可行

**关键问题**：Uya union **不支持引用类型变体**

根据 `docs/union_memory_layout.md`:

> **重要规则**：Union 变体不能包含引用类型 `&T`
> 
> 原因：引用类型有生命周期约束，union 的变体切换会破坏生命周期安全。

**原方案问题分析**：

```uya
// 原方案（不可行）
union TypeData {
    pointer: PointerData,    // ❌ 包含引用
    array: ArrayData,        // ❌ 包含引用
    // ...
}

struct PointerData {
    pointee: &Type,          // ❌ 引用类型！
    is_ffi: i32,
}

struct ArrayData {
    element: &Type,          // ❌ 引用类型！
    size: i32,
}
```

**ASTNode 同样不可行**：

```uya
// 原方案（不可行）
union ASTNodeData {
    program: ProgramData,    // ❌ 包含引用
    binary_expr: BinaryExprData, // ❌ 包含引用
    // ...
}

struct ProgramData {
    decls: & & ASTNode,      // ❌ 引用类型！
    count: i32,
}

struct BinaryExprData {
    left: &ASTNode,          // ❌ 引用类型！
    op: i32,
    right: &ASTNode,         // ❌ 引用类型！
}
```

---

### 替代方案

#### 方案 A：使用 FFI 指针替代引用

```uya
// 使用 *T（FFI 指针）替代 &T（引用）
union TypeData {
    pointer: PointerData,
    array: ArrayData,
    // ...
}

struct PointerData {
    pointee: *Type,          // ✅ FFI 指针（允许）
    is_ffi: i32,
}

struct ArrayData {
    element: *Type,          // ✅ FFI 指针（允许）
    size: i32,
}
```

**问题**：
1. 丢失类型安全（FFI 指针无生命周期检查）
2. 需要大量修改现有代码
3. 可能引入内存安全问题

#### 方案 B：保持扁平化设计，使用 match 表达式优化

```uya
// 保持现有 Type 结构体不变
struct Type {
    kind: TypeKind,
    enum_name: &byte,
    struct_name: &byte,
    // ... 保持所有字段
}

// 但使用 match 表达式替代 if-else 链
fn type_to_string(t: Type) &byte {
    match t.kind {  // 匹配枚举值，而不是 union
        TypeKind.TYPE_ENUM => return t.enum_name,
        TypeKind.TYPE_STRUCT => return t.struct_name,
        TypeKind.TYPE_UNION => return t.union_name,
        TypeKind.TYPE_POINTER => return format("*{}", type_to_string(t.pointer_to)),
        else => return "unknown"
    }
}
```

**优点**：
1. 不需要修改数据结构
2. 代码可读性提升
3. 编译期完备性检查（枚举 match）
4. 风险低

**缺点**：
1. 不解决内存浪费问题
2. 字段访问仍需手动保证正确性

#### 方案 C：分离堆分配和栈分配类型

```uya
// 栈上的类型描述（不包含指针）
struct TypeInfo {
    kind: TypeKind,
    // 基础类型信息
    enum_name_id: u32,    // 使用 ID 而非指针
    struct_name_id: u32,
    array_size: i32,
}

// 堆上的类型（包含指针的独立结构）
struct Type {
    info: TypeInfo,
    // 指针字段单独存储
    pointer_to: &Type,
    element_type: &Type,
}
```

**评估**：复杂度高，收益有限

---

### 推荐方案

**推荐方案 B**：保持扁平化设计，使用 match 表达式优化

**理由**：
1. 风险最低
2. 工作量最小
3. 收益明显（代码可读性 + 完备性检查）
4. 不需要修改核心数据结构

**修改后的阶段四**：

```markdown
## 阶段四：枚举 match 表达式优化 [░░░░░░░░░░] 0%

### 4.1 使用 match 替代 Type 条件链

**当前问题**：139+ 处 `kind == TypeKind.XXX` 条件判断

**重构方案**：使用 match 表达式匹配枚举值

// 重构前
if t.kind == TypeKind.TYPE_ENUM {
    return t.enum_name;
} else if t.kind == TypeKind.TYPE_STRUCT {
    return t.struct_name;
}

// 重构后
match t.kind {
    TypeKind.TYPE_ENUM => return t.enum_name,
    TypeKind.TYPE_STRUCT => return t.struct_name,
    TypeKind.TYPE_UNION => return t.union_name,
    TypeKind.TYPE_POINTER => return format("*{}", type_to_string(t.pointer_to)),
    else => return "unknown"
}

**收益**：
- 编译期完备性检查
- 代码更简洁
- 无运行时开销

**预估工作量**：3 天

### 4.2 使用 match 替代 ASTNode 条件链

同上，564+ 处条件链替换为 match 表达式

**预估工作量**：5 天
```

---

### 阶段五：测试现代化 ✅

**可行性**：高

| 任务 | 评估 |
|------|------|
| 5.1 test 语句重构 | ✅ 可行，已有 test 支持 |
| 5.2 增量测试验证 | ✅ 可行 |

**工作量评估**：
- 文档预估：3 天
- 实际预估：**2-3 天**

---

### 阶段六：代码质量改进 ✅

**可行性**：高

所有任务均为标准代码清理，风险低。

---

## 修订后的实施计划

### 总工作量对比

| 项目 | 原计划 | 修订后 | 变化 |
|------|--------|--------|------|
| 阶段一 | 9-15 天 | 7-10 天 | -3 天 |
| 阶段二 | 4-5 天 | 3-4 天 | -1 天 |
| 阶段三 | 2.5 天 | 2 天 | -0.5 天 |
| 阶段四 | 15 天 | **8 天** | **-7 天** |
| 阶段五 | 3 天 | 2-3 天 | 持平 |
| 阶段六 | 1 天 | 1 天 | 持平 |
| **总计** | **34-41 天** | **23-28 天** | **-11 天** |

### 修订后的时间线

| 周 | 任务 |
|----|------|
| 第 1 周 | 阶段一：巨型函数拆分 |
| 第 2 周 | 阶段一（续）+ 阶段二 |
| 第 3 周 | 阶段三 + 阶段四.1（Type match 优化） |
| 第 4 周 | 阶段四.2（ASTNode match 优化）+ 阶段五 |
| 第 5 周 | 阶段六 + 验收 |

---

## 结论

1. **阶段四需要重新设计**：原 Union 方案不可行，应改为枚举 match 优化
2. **总体工作量减少**：从 6 周缩短至 5 周
3. **风险降低**：避免修改核心数据结构
4. **建议立即开始阶段一**：验证重构模式，积累经验

---

**评审人**：AI Assistant  
**评审日期**：2026-02-21  
**文档版本**：v1.0
