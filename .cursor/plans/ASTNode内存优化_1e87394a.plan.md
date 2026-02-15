---
name: ASTNode 内存优化
overview: ASTNode 当前使用 flat struct（约 1432 字节），而 C 版本使用 union（约 72 字节），大小比约 20x。本计划通过节点类型分离或 tag + payload 模式，将内存占用降低到接近 C 版本水平。
todos: []
isProject: false
---

# ASTNode 内存优化计划

## 问题分析

### 当前状态

| 指标 | C 编译器 | 自举编译器 | 倍数 |
|------|----------|------------|------|
| ASTNode 大小 | ~72 字节 | ~1432 字节 | **~20x** |
| 核心原因 | 使用 `union` 复用内存 | flat struct 包含所有字段 |

### 根因分析

**C 版本（union）**：
```c
typedef struct ASTNode {
    int type;
    int line;
    int column;
    const char *filename;
    union {
        struct { /* binary expr */ } binary;
        struct { /* function call */ } call;
        struct { /* if stmt */ } if_stmt;
        // ... 每种节点类型
    } data;
} ASTNode;
```

**Uya 版本（flat struct）**：
```uya
struct ASTNode {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    // 所有节点类型的字段平铺
    // 约 150 个指针字段
    // 约 50 个 int 字段
    // 1 个 double 字段
}
```

### 内存影响估算

编译器自举时约有多少 ASTNode：

| 阶段 | 节点数（估算） | C 版本内存 | Uya 版本内存 |
|------|---------------|------------|--------------|
| 单文件解析 | ~50,000 | ~3.5 MB | ~70 MB |
| 32 文件自举 | ~1,600,000 | ~110 MB | ~2.2 GB |

**关键洞察**：flat struct 是内存占用大的根本原因，arena 回滚优化只是缓解了累积问题。

---

## 优化策略

### 策略 1：节点类型分离（推荐）

为每种 AST 节点定义独立结构体，使用类型标记和指针转换。

#### 设计

```uya
// 基础节点头（所有节点共享）
struct ASTNodeBase {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
}

// 程序节点
struct ASTProgramNode {
    base: ASTNodeBase,
    decls: &&ASTNode,
    decl_count: i32,
}

// 二元表达式
struct ASTBinaryExprNode {
    base: ASTNodeBase,
    left: &ASTNode,
    op: i32,
    right: &ASTNode,
}

// 函数调用
struct ASTCallExprNode {
    base: ASTNodeBase,
    callee: &ASTNode,
    args: &&ASTNode,
    arg_count: i32,
}

// If 语句
struct ASTIfStmtNode {
    base: ASTNodeBase,
    condition: &ASTNode,
    then_branch: &ASTNode,
    else_branch: &ASTNode,
}

// ... 为每种节点类型定义独立结构体

// 通用节点指针（用于链表、数组等）
// 使用 ASTNodeBase* 并向上转型
```

#### 内存对比

| 节点类型 | 当前 flat | 分离后 | 减少 |
|----------|-----------|--------|------|
| ASTProgramNode | 1432 字节 | ~32 字节 | 98% |
| ASTBinaryExprNode | 1432 字节 | ~32 字节 | 98% |
| ASTCallExprNode | 1432 字节 | ~40 字节 | 97% |
| ASTIfStmtNode | 1432 字节 | ~32 字节 | 98% |
| **平均** | **1432 字节** | **~40 字节** | **~97%** |

#### 预期效果

- 单文件解析：70 MB → ~2 MB
- 32 文件自举：2.2 GB → ~60 MB
- arena_buffer：256 MB → ~32 MB（接近 C 版本）

---

### 策略 2：Tag + Payload 模式

使用类型标记 + void* payload，运行时根据类型转换。

#### 设计

```uya
struct ASTNode {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    payload: &byte,  // 指向具体节点数据
}

// 节点数据结构
struct BinaryExprData {
    left: &ASTNode,
    op: i32,
    right: &ASTNode,
}

struct CallExprData {
    callee: &ASTNode,
    args: &&ASTNode,
    arg_count: i32,
}

// 使用时转换
fn get_binary_expr(node: &ASTNode) &BinaryExprData {
    return node.payload as &BinaryExprData;
}
```

#### 优缺点

| 方面 | 优点 | 缺点 |
|------|------|------|
| 类型安全 | ❌ 需要 unsafe 转换 | - |
| 实现难度 | ✅ 改动较小 | - |
| 内存效率 | ✅ 接近策略 1 | - |

---

### 策略 3：混合模式（base 嵌入 + 变长尾部）

将常用字段嵌入 base，罕见字段使用额外分配。

#### 设计

```uya
// 小节点（大多数）
struct ASTNodeSmall {
    type: ASTNodeType,
    line: i32,
    column: i32,
    filename: &byte,
    // 常用字段
    left: &ASTNode,
    right: &ASTNode,
    value_int: i64,
    value_str: &byte,
}

// 大节点（少数，如 Program、Struct）
struct ASTNodeLarge {
    small: ASTNodeSmall,
    // 额外字段
    decls: &&ASTNode,
    decl_count: i32,
    // ...
}
```

---

## 实现计划

### 阶段 1：准备（低风险）

1. **审计 ASTNode 定义**
   - 统计所有字段及其使用频率
   - 按节点类型分组字段
   - 确定每种节点的最小字段集

2. **创建节点类型枚举到结构体的映射表**
   ```uya
   // 节点类型 -> 对应结构体
   // AST_PROGRAM -> ASTProgramNode
   // AST_BINARY_EXPR -> ASTBinaryExprNode
   // ...
   ```

### 阶段 2：渐进式迁移（中风险）

1. **选择 3-5 个简单节点类型试点**
   - 建议从 AST_INT_LITERAL、AST_BOOL_LITERAL、AST_IDENTIFIER 开始
   - 这些节点字段少、使用简单

2. **修改 parser 创建节点**
   ```uya
   // 原来
   var node: ASTNode = arena_alloc(arena, sizeof(ASTNode));
   node.type = AST_INT_LITERAL;
   node.value_int = value;
   
   // 改为
   var node: &ASTIntLiteralNode = arena_alloc(arena, sizeof(ASTIntLiteralNode));
   node.base.type = AST_INT_LITERAL;
   node.value = value;
   ```

3. **修改 checker/codegen 访问节点**
   ```uya
   // 原来
   if node.type == AST_INT_LITERAL {
       result = node.value_int;
   }
   
   // 改为
   if node.base.type == AST_INT_LITERAL {
       var int_node: &ASTIntLiteralNode = node as &ASTIntLiteralNode;
       result = int_node.value;
   }
   ```

4. **验证自举对比**
   - 每迁移一批节点，运行 `make b`
   - 确保输出一致

### 阶段 3：全面迁移（高风险）

1. **迁移所有节点类型**
   - 按复杂度排序，从简单到复杂
   - 每迁移一批，完整验证

2. **优化访问模式**
   - 提取辅助函数减少重复代码
   - 考虑宏或代码生成

3. **内存验证**
   - 测量实际内存使用
   - 调整 arena_buffer 大小

---

## 关键文件

| 文件 | 影响范围 |
|------|----------|
| `src/ast.uya` | ASTNode 定义、所有节点结构体 |
| `src/parser.uya` | 创建 AST 节点 |
| `src/checker.uya` | 类型检查、访问 AST 节点 |
| `src/codegen.uya` | 代码生成、访问 AST 节点 |
| `src/main.uya` | ARENA_BUFFER_SIZE 常量 |

---

## 风险与缓解

### 风险 1：自举对比失败

**原因**：节点字段顺序变化可能影响 C 输出顺序

**缓解**：
- 保持字段名称不变
- 输出 C 时按字段名排序
- 每批迁移后验证 `make b`

### 风险 2：类型安全丧失

**原因**：void* 转换或基类指针转换

**缓解**：
- 在 debug 模式添加类型检查
- 使用辅助函数封装转换逻辑
- 编译时检查类型标记

### 风险 3：代码量大幅增加

**原因**：每种节点类型需要独立处理

**缓解**：
- 使用宏减少重复
- 代码生成工具
- 渐进式迁移

---

## 预期收益

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| ASTNode 平均大小 | 1432 字节 | ~40 字节 | **97%** |
| arena_buffer | 256 MB | ~32 MB | **87%** |
| 总内存占用 | 320 MB | ~100 MB | **69%** |
| 编译速度 | 基准 | 可能更快 | 缓存友好 |

---

## 依赖关系

- **前置**：无（可独立进行）
- **后续**：
  - 进一步优化 arena 分配策略
  - 考虑 AST 序列化/反序列化
  - 增量编译支持

---

## 时间估算

| 阶段 | 工作量 | 时间 |
|------|--------|------|
| 阶段 1：准备 | 审计、设计 | 1-2 天 |
| 阶段 2：试点 | 3-5 个节点类型 | 2-3 天 |
| 阶段 3：全面迁移 | 剩余节点类型 | 5-7 天 |
| 验证与调优 | 测试、性能测量 | 2-3 天 |
| **总计** | | **10-15 天** |

---

## 建议优先级

1. **高优先级**：策略 1（节点类型分离）
   - 最大内存收益
   - 类型安全
   - 代码清晰

2. **中优先级**：策略 2（Tag + Payload）
   - 改动较小
   - 类型安全较弱

3. **低优先级**：策略 3（混合模式）
   - 复杂度高
   - 收益不确定
