---
name: ""
overview: ""
todos: []
isProject: false
---

# Codegen 可达性分析优化计划（桶式哈希）

## 问题分析

当前 `collect_reachable_top_level_functions_from_node` 递归遍历 AST，每次调用 `find_function_decl_c99`（含 `strcmp`），导致 `strcmp` 热点占 15.28%。

## 优化方案

在 codegen 预处理阶段一次性遍历 AST 收集调用关系到**桶式哈希表**，后续基于调用图做 BFS 可达性分析。

## 桶式哈希设计

```
┌─────────────────────────────────────────────────────┐
│  Bucket[0]  → [entry1] → [entry2] → null        │
│  Bucket[1]  → [entry3] → null                   │
│  Bucket[2]  → null                              │
│  ...                                              │
│  Bucket[N]  → [entryX] → null                   │
└─────────────────────────────────────────────────────┘

每个桶存储同一哈希值的调用关系链表
查找时遍历桶内元素（通常 1-3 个）
```

## 实施步骤

### 1. 添加调用图结构体

**文件**: `src/codegen/c99/internal.uya`

```uya
// 调用图配置（桶式哈希）
const C99_CALLGRAPH_BUCKET_COUNT: i32 = 4096;
const C99_MAX_CALL_ENTRIES: i32 = 8192;
const C99_MAX_CALLEES_PER_FUNC: i32 = 32;

// 调用图条目（链表节点）
struct CallGraphEntry {
    caller_name: &byte,     // 调用者函数名
    callee_names: [&byte: C99_MAX_CALLEES_PER_FUNC],
    callee_count: i32,
    next: &CallGraphEntry,  // 链表 next
}
```

在 `C99CodeGenerator` 添加：

```uya
callgraph_initialized: i32,
callgraph_buckets: [&CallGraphEntry: C99_CALLGRAPH_BUCKET_COUNT],
```

### 2. 桶式哈希表操作

**文件**: `src/codegen/c99/main.uya`

```uya
// 初始化桶
fn init_callgraph_buckets(codegen: &C99CodeGenerator) void {
    var i: i32 = 0;
    while i < C99_CALLGRAPH_BUCKET_COUNT {
        codegen.callgraph_buckets[i] = null;
        i = i + 1;
    }
}

// 桶哈希函数
fn callgraph_bucket(caller: &byte) i32 {
    return (hash_string(caller) & (C99_CALLGRAPH_BUCKET_COUNT - 1)) as i32;
}

// 添加调用边（插入到桶链表头部）
fn add_callgraph_edge(codegen: &C99CodeGenerator, caller: &byte, callee: &byte) void {
    if caller == null || callee == null { return; }

    const bucket_idx: i32 = callgraph_bucket(caller);

    // 遍历桶内条目，查找匹配的 caller
    var entry: &CallGraphEntry = codegen.callgraph_buckets[bucket_idx];
    while entry != null {
        if strcmp(entry.caller_name as *byte, caller as *byte) == 0 {
            // 找到匹配，追加 callee
            if entry.callee_count < C99_MAX_CALLEES_PER_FUNC {
                entry.callee_names[entry.callee_count] = callee;
                entry.callee_count = entry.callee_count + 1;
            }
            return;
        }
        entry = entry.next;
    }

    // 未找到，创建新条目（插入桶头部）
    const new_entry: &CallGraphEntry = arena_alloc(codegen.arena,
        @size_of(CallGraphEntry) as usize) as &CallGraphEntry;
    if new_entry == null { return; }

    new_entry.caller_name = caller;
    new_entry.callee_count = 1;
    new_entry.callee_names[0] = callee;
    new_entry.next = codegen.callgraph_buckets[bucket_idx];
    codegen.callgraph_buckets[bucket_idx] = new_entry;
}

// 查找某函数的所有直接调用
fn get_callgraph_callees(codegen: &C99CodeGenerator, caller: &byte) & [&byte] {
    if caller == null { return null; }

    const bucket_idx: i32 = callgraph_bucket(caller);
    var entry: &CallGraphEntry = codegen.callgraph_buckets[bucket_idx];

    while entry != null {
        if strcmp(entry.caller_name as *byte, caller as *byte) == 0 {
            return &entry.callee_names[0];
        }
        entry = entry.next;
    }
    return null;
}
```

### 3. 调用图收集

```uya
fn collect_all_function_calls(codegen: &C99CodeGenerator, ast: &ASTNode) void {
    if codegen == null || ast == null { return; }
    codegen.callgraph_initialized = 1;
    init_callgraph_buckets(codegen);
    collect_calls_from_node(codegen, ast, null);
}

fn collect_calls_from_node(codegen: &C99CodeGenerator, node: &ASTNode, current_fn: &byte) void {
    if node == null { return; }

    if node.type == ASTNodeType.AST_CALL_EXPR {
        const callee: &ASTNode = node.call_expr_callee;
        if callee != null && callee.type == ASTNodeType.AST_IDENTIFIER
            && callee.identifier_name != null {
            if current_fn != null {
                add_callgraph_edge(codegen, current_fn, callee.identifier_name);
            }
        }
    } else if node.type == ASTNodeType.AST_FN_DECL && node.fn_decl_body != null {
        collect_calls_from_node(codegen, node.fn_decl_body, node.fn_decl_name);
    }
    // ... 处理其他节点类型 ...
}
```

### 4. BFS 可达性分析

```uya
fn collect_reachable_top_level_functions(codegen: &C99CodeGenerator, ast: &ASTNode, tests: & &ASTNode, test_count: &i32) void {
    if codegen.callgraph_initialized == 0 {
        collect_all_function_calls(codegen, ast);
    }

    codegen.reachable_function_decl_count = 0;

    var queue: [&byte: C99_MAX_REACHABLE_FUNCTIONS] = [];
    var q_head: i32 = 0;
    var q_tail: i32 = 0;

    // 初始化队列（main, export extern 等）
    // ...

    while q_head < q_tail {
        const fn_name: &byte = queue[q_head];
        q_head = q_head + 1;

        const callees: & [&byte] = get_callgraph_callees(codegen, fn_name);
        if callees == null { continue; }

        var i: i32 = 0;
        while i < C99_MAX_CALLEES_PER_FUNC {
            const callee_name: &byte = callees[i];
            if callee_name == null { break; }
            i = i + 1;

            const fn_decl: &ASTNode = find_function_decl_c99(codegen, callee_name);
            if fn_decl != null && is_top_level_function_reachable(codegen, fn_decl) == 0 {
                mark_top_level_function_reachable(codegen, fn_decl);
                queue[q_tail] = callee_name;
                q_tail = q_tail + 1;
            }
        }
    }
}
```

## 性能对比


| 方案     | 查找    | 冲突处理   | 最坏情况                  |
| ------ | ----- | ------ | --------------------- |
| 线性探测   | O(1)  | 探测下一个槽 | O(n) - 连续冲突           |
| **桶式** | O(1)* | 遍历桶    | O(bucket_size) ≈ O(1) |


*注：桶内元素数量通常很小（1-3个），近似 O(1)

## 数据流

```mermaid
graph LR
    subgraph 预处理阶段
        A1[AST 遍历] --> A2[add_callgraph_edge]
        A2 --> A3[桶式哈希表<br/>Bucket[0] → entry → ...
        A2 --> A4[Bucket[1] → entry
        A2 --> A5[...]
    end

    subgraph BFS传播
        A3 --> B1[从入口函数开始]
        B1 --> B2[查桶获取 callees]
        B2 --> B3[标记可达]
        B3 --> B2
    end
```



## 验证

```bash
bash scripts/bench_compile_stats.sh --runs 3
make check
```

