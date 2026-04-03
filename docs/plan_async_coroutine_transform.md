# 通用 @async_fn 协程变换实现计划

## Context

当前 `@async_fn` 的状态机在 C99 codegen 层通过模式匹配 AST 形状生成（`gen_async_function_stage_b`，~800 行）。只支持 `const x = try @await expr` 单一模式，导致 Bug A（连续 while 循环）、Bug B（await 间同步代码丢失）、Bug C（return try @await）、Bug D（分裂点变量丢失）。

**目标**：用通用算法替换 `gen_async_function_stage_b` 的内部实现，支持 `@async_fn` 中任意 Uya 控制流（while/for/if/break/continue/return + @await 任意组合）。

**策略**：不改 parser/checker，不创建新 AST 节点。在 C codegen 层用「递归段发射」算法直接输出 C 代码。保持相同的外部接口（状态结构体 + poll 函数 + wrapper + vtable）。

---

## 生成的 C 代码模式（不变）

```c
// 1. 状态结构体
struct uya_async_<name> {
    int32_t state;
    struct { void *vtable; void *data; } await_fut;
    <type> _uya_bind_<name>;   // 每个 await 的绑定变量
    <type> _uya_loc_<name>;    // 跨 await 存活的局部变量
    <type> <param>;            // 函数参数
};

// 2. poll 函数
static <Poll_T> uya_<name>_poll(void *self, struct Waker *waker) {
    struct uya_async_<name> *s = (struct uya_async_<name> *)self;
    if (s == NULL) return Pending;
    if (s->state == 0) { /* segment 0 */ }
    if (s->state == 1) { /* poll await 0, then segment 1 */ }
    if (s->state == 2) { /* poll await 1, then segment 2 */ }
    ...
    return Pending; // unreachable
}

// 3. vtable + wrapper（不变）
```

---

## 核心算法：递归段发射

### 概念

函数体被 `@await` 切分为 N+1 个「段」(segment)。每个段是两个相邻 await 之间的代码。段内的代码用普通 `gen_stmt`/`gen_expr` 生成——**不需要任何 async 特殊逻辑**。

### 关键函数

```
emit_segment(codegen, block, start_idx, end_idx_or_await, state_after)
```

遍历 `block.stmts[start_idx .. end_idx]`，对每条语句：
- **普通语句**（不含 await）：直接 `gen_stmt(codegen, stmt)`
- **var_decl with try @await**：这是分裂点——生成「设置 await_fut → state = K → return Pending」
- **return try @await**：同上，但 Ready 后直接 return Ready(value)
- **while/for（体内含 await）**：不生成 C 的 while，而是：
  1. 发射条件检查：`if (cond) {`
  2. 发射循环体的前半段（到第一个 await）
  3. 生成 await 分裂
  4. 下一个 state 中：发射循环体后半段 + 回跳条件检查
  5. 条件为假时：`} else {` 继续发射循环后代码
- **if/else（分支含 await）**：两个分支各自递归 emit_segment
- **while/for（体内无 await）**：直接 `gen_stmt` 生成正常 C while

### 状态编号分配

在发射前，预扫描函数体分配状态号：

```
state 0 = 入口（参数复制 + 第一个 await 之前的代码）
state 1 = await 0 的 poll + await 0 Ready 后到 await 1 之前的代码
state 2 = await 1 的 poll + await 1 Ready 后到 await 2 之前的代码
...
state N = await N-1 的 poll + 最终代码 + return Ready
```

循环内的 await 回跳到自身的 state 号（不分配新号），循环退出跳到下一个 state。

### 变量提升

**保守策略**（简单正确）：函数体**所有**顶层 `var` 声明都提升到状态结构体的 `_uya_loc_*` 字段。函数参数全部捕获。

**生成代码中的变量引用**：现有的 `get_c_name_for_identifier_ref`（global.uya:330-451）已经将 `async_local_names` 中的标识符重写为 `s->_uya_loc_*`。只需正确填充 `async_local_names/types/count`。

---

## 实现步骤

### Step 1：新函数 `gen_async_poll_body_universal`

**文件**：`src/codegen/c99/function.uya`（在 `gen_async_function_stage_b` 旁边）

替换当前 `gen_async_function_stage_b` 中 lines 2785-3081 的状态循环。新函数接收：
- `codegen`, `fn_decl`, `body`（函数体 AST）
- `await_points[]`, `await_count`（已收集的 await 点）
- `poll_ret_c`, `poll_union_c`, `ready_payload_c` 等 C 类型字符串
- `ret_expr`（return 表达式，null 表示 return await）

内部算法：
1. 发射 `if (s->state == 0) { ... }`：初始化 + 第一段代码
2. 对 `state_k = 1 .. await_count`：发射 `if (s->state == K) { poll + 段代码 }`
3. 如果有终态（循环退出后）：发射最终 return Ready

### Step 2：递归段发射函数 `emit_async_segment`

```
fn emit_async_segment(
    codegen, block, from_si, to_si,
    await_points, await_count,
    next_state_on_complete,
    poll_ret_c, poll_union_c, ready_payload_c
)
```

遍历 `block.stmts[from_si .. to_si]`：
- 跳过 `is_await_bind_stmt()` 的语句（由 state 转移处理）
- 对含 await 的 while/for：拆分为条件检查 + 段发射 + 回跳
- 对含 await 的 if：两分支递归
- 其余：`gen_stmt(codegen, stmt)`

### Step 3：while/for 内 await 处理

```
// while (cond) { pre_stmts; @await; post_stmts; }
// 变换为：

// 当前 state 尾部：
if (cond) {
    emit pre_stmts;
    s->await_fut = ...; s->state = K; return Pending;
}
// 后续代码...

// state K:
poll await_fut; extract result;
emit post_stmts;
if (cond) {  // 回跳
    emit pre_stmts;
    s->await_fut = ...; s->state = K; return Pending;
} else {
    emit 循环后代码 or state = next;
}
```

### Step 4：集成

在 `gen_async_function_stage_b` 中：
1. 保留状态结构体生成（lines 2699-2743）——不变
2. 保留 poll 函数签名（line 2789）——不变
3. **替换** 状态循环（lines 2794-3081）为 `gen_async_poll_body_universal`
4. 保留 vtable + wrapper（lines 3210-3274）——不变

### Step 5：清理

- `collect_awaits_recursive` → 用 `async_collect_all_awaits`（async_transform.uya）替换
- 删除 `c99_emit_async_while_multi_loopback` 等旧的模式匹配函数（~400 行）
- 删除 `c99_emit_async_poll_not_last_transition`（~200 行）
- 删除 `c99_emit_async_while_exit_transition` 及相关辅助函数

---

## 关键文件

| 文件 | 改动 |
|------|------|
| `src/codegen/c99/function.uya` | 替换 state 循环为通用算法，删除旧辅助函数 |
| `src/codegen/c99/async_transform.uya` | 扩展：添加 `emit_async_segment` 等函数 |
| `src/codegen/c99/internal.uya` | 无变化（async_local_* 字段保留） |
| `src/codegen/c99/global.uya` | 无变化（`get_c_name_for_identifier_ref` 保留） |
| `src/codegen/c99/stmt.uya` | 无变化（`gen_stmt` 保留） |
| `src/codegen/c99/expr.uya` | 无变化（`gen_expr` 保留） |

## 复用的现有机制

- `get_c_name_for_identifier_ref`（global.uya:330-451）：标识符 → `s->_uya_loc_*` / `s->_uya_bind_*` 重写
- `gen_stmt` / `gen_expr`（stmt.uya / expr.uya）：普通代码生成，段内直接调用
- `async_local_names/types/count`（internal.uya:328-332）：提升变量的名称/类型存储
- `collect_async_pre_return_locals`（function.uya:2356）：收集函数体顶层 var 声明
- `emit_async_state0_pre_first_await_local_inits`（function.uya:2083）：初始化提升变量
- 状态结构体 / vtable / wrapper 生成逻辑（保留不变）

## 验证

1. **Bug A 测试**：`test_async_bug_a_two_while.uya.pending` → 恢复为 `.uya`，通过
2. **Bug B 测试**：`test_async_bug_b_sync_between.uya.pending` → 恢复为 `.uya`，通过
3. **Bug C 测试**：`test_async_bug_c_tail_await.uya`（已通过，不回归）
4. **现有 async 测试**：`test_async_while_multi_await.uya`、`test_async_copy.uya` 等不回归
5. **全量回归**：`make tests e` 通过
6. **自举**：`make b` 一致
