# 循环内 await 代码生成设计文档

**版本**：v0.1  
**状态**：实现中  
**相关**：[std_async_design.md](std_async_design.md)、[todo_mini_to_full.md](todo_mini_to_full.md) §16 异步编程

---

## 1. 概述

### 1.1 问题背景

`@async_fn` 中的 `try @await` 可能出现在循环内，例如 `async_copy`：

```uya
@async_fn fn async_copy(reader: &MemAsyncReader, writer: &MemAsyncWriter, buf: &byte, buf_len: usize) !Future<usize> {
    var total: usize = 0;
    while true {
        const n: usize = try @await reader.read(buf, buf_len);
        if n == 0 { return total; }
        const written: usize = try @await writer.write(buf as &const byte, n);
        total = total + written;
        if written < n { return total; }
    }
}
```

需要支持：
- **递归收集**：在 while / if / for / block 内递归收集所有 await 点
- **循环回跳**：状态机在完成一轮 read→write 后回到 read，而非线性结束
- **持久化变量**：`total` 等跨 await 的变量需存于状态结构体

### 1.2 设计目标

| 目标 | 说明 |
|------|------|
| 正确性 | 生成的状态机语义与源码等价 |
| 类型安全 | slot 类型与 operand 类型匹配，`!Future<T>` 需 try 后存 `.value` |
| 无悬挂指针 | sync 方法返回的 Future 若指向栈上 compound literal，需复制到状态存储 |
| 与现有兼容 | 线性 await 行为不变，新增逻辑仅影响循环内 await |

---

## 2. 整体架构

```
                    collect_awaits_recursive()
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ await_operands[]  await_bind_names[]  await_bind_types[]  has_await_loop │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ 状态机生成                                                                │
│  • state 0：起点，设置 await_fut = operand[0]                             │
│  • state 1..n：poll await_fut → 绑定变量 → 下一 await 或循环回跳或返回     │
│  • async_loop_var_is_total：n/written 模式 → total 持久化 + 循环回跳       │
└─────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ C 输出                                                                    │
│  struct uya_async_xxx { state; _uya_await_storage; await_fut; _uya_total; … }│
│  static Poll_xxx poll(...) { if state==0 {...} if state==1 {...} ... }    │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 核心数据流

### 3.1 await 收集

| 阶段 | 说明 |
|------|------|
| **collect_awaits_recursive** | 递归遍历 block / while / if / for，收集 `try @await expr` 的 operand、绑定名、绑定类型 |
| **has_await_loop** | 当任一 await 在循环（while/for）内时置 1 |
| **async_loop_var_is_total** | 当 `await_count==2` 且绑定名为 `n`、`written` 时，启用 `_uya_total` 与循环回跳 |

### 3.2 状态机结构体

```c
struct uya_async_std_async_copy {
    int32_t state;
    struct Future_usize _uya_await_storage;      // 仅当 await_operand_is_err_future 时存在
    struct uya_interface_Future_usize await_fut;
    size_t _uya_total;                           // 仅当 async_loop_var_is_total 时存在
    struct MemAsyncReader * reader;
    struct MemAsyncWriter * writer;
    uint8_t * buf;
    size_t buf_len;
};
```

| 字段 | 用途 |
|------|------|
| `state` | 当前状态：0=起点，1..n=各 await 就绪后 |
| `_uya_await_storage` | 存储 sync 方法返回的 Future 值，避免 compound literal 悬挂指针 |
| `await_fut` | 当前 poll 的 child future（接口 fat 指针） |
| `_uya_total` | 循环内累加量，供 `return total` 使用 |

### 3.3 类型与 try 判定

| 变量 | 说明 |
|------|------|
| `return_future_err_union` | 返回类型为 `!Future<T>` 时置 1 |
| `concrete_future_safe` | 从 `effective_return_type` 提取，若 type_args[0] 为 error union 则用 payload 生成 `Future_usize` 等 |
| `state_slot_iface_c` | await_fut 槽位的 C 类型，如 `struct uya_interface_Future_usize` |
| `await_operand_is_err_future` | 当 `return_future_err_union` 或绑定类型为 Future 时置 1，表示 operand 返回 `!Future<T>` 需 try |

---

## 4. 关键实现点

### 4.1 递归 await 收集

```uya
fn collect_awaits_recursive(...) void {
    // 遍历 AST：block、while、if、for
    // 遇到 try @await expr 时：
    //   await_operands[ci] = operand;
    //   await_bind_names[ci] = bind_name;   // 如 "n", "written"
    //   await_bind_types[ci] = bind_type;   // 如 usize
    // 若在 while/for 内，has_await_loop = 1
}
```

### 4.2 return_future_err_union 判定

- **原逻辑**：依赖 `await_count==0`、`ret_expr` 为 Future 初始化、`await_bind_types[0]` 为 Future
- **现逻辑**：当 `full_return_type` 为 error union 且 payload 为 `Future<T>` 时，直接置 1

### 4.3 concrete_future_safe 与 state_slot

- 当 `effective_return_type.type_named_type_args[0]` 为 `AST_TYPE_ERROR_UNION` 时，用 payload 作为 slot 类型参数
- 例：`!Future<usize>` → type_args[0]=`!usize` → payload=`usize` → slot 类型为 `Future_usize`

### 4.4 await 赋值时的 try 与 storage 复制

当 `await_operand_is_err_future` 且存在 `_uya_await_storage` 时：

```c
({
  struct err_union_uya_interface_Future_usize _uya_await_tmp = reader.read(...);
  if (_uya_await_tmp.error_id != 0) return ...;
  s->_uya_await_storage = *(struct Future_usize *)_uya_await_tmp.value.data;
  s->await_fut = (struct uya_interface_Future_usize){
    .vtable = _uya_await_tmp.value.vtable,
    .data = (void*)&s->_uya_await_storage
  };
})
```

**原因**：sync 方法（如 `MemAsyncReader.read`）返回的 Future 的 `.data` 指向函数内 compound literal，函数返回后失效；复制到 `_uya_await_storage` 后由状态机持有，生命周期正确。

### 4.5 循环回跳逻辑

当 `async_loop_var_is_total` 且完成第二个 await（written）后：

```c
s->_uya_total = s->_uya_total + written;
if (written < n) { return Ready(ok); }  // 提前返回
s->state = 1;
s->await_fut = reader.read(...);        // 回到第一个 await
return Pending;
```

该逻辑需同时存在于 `child_inner_is_err_union != 0` 与 `== 0` 两个分支。

### 4.6 total 变量映射

- 在 `get_c_name_for_identifier_ref` 中，当 `async_loop_var_is_total` 时，将 `"total"` 映射为 `"s->_uya_total"`
- 确保 `return total` 生成 `return Ready(Ok(Future::Ready(s->_uya_total)))` 等正确代码

---

## 5. 状态转换示意

以 `async_copy` 为例：

```
state 0 ──────────────────────────────────────────────────────────────┐
    │ await_fut = try reader.read();  state=1                          │
    ▼                                                                  │
state 1 (poll reader)                                                  │
    │ n = p.u.Ready                                                    │
    │ if n==0 return Ready(total)                                      │
    │ await_fut = try writer.write();  state=2                         │
    ▼                                                                  │
state 2 (poll writer)                                                  │
    │ written = p.u.Ready                                              │
    │ total += written                                                 │
    │ if written<n return Ready(total)                                 │
    │ await_fut = try reader.read();  state=1 ─────────────────────────┘
    │ return Pending
```

---

## 6. 已知限制与待修复

| 问题 | 状态 | 说明 |
|------|------|------|
| test_async_copy 段错误 | 🔴 待查 | AddressSanitizer 报告 stack-buffer-overflow，可能与 block_on 栈布局或 f.data 传递有关 |
| Poll 返回类型 | ⚠️ 待确认 | `block_on_usize_plain` 期望 `Poll<usize>`，当前可能返回 `Poll<!Future<usize>>`，需核对类型链 |
| 通用 n/written 模式 | 📋 计划 | 目前仅识别 `n`+`written` 绑定名，更通用的循环变量持久化可扩展 |

---

## 7. 涉及文件

| 路径 | 职责 |
|------|------|
| `src/codegen/c99/function.uya` | `collect_awaits_recursive`、`gen_async_function_stage_b`、状态机生成 |
| `src/codegen/c99/internal.uya` | `async_collect_*`、`async_loop_var_*` 收集接口 |
| `src/codegen/c99/global.uya` | `get_c_name_for_identifier_ref` 对 `total` 的映射 |
| `lib/std/async.uya` | `async_copy` 定义 |
| `tests/test_async_copy.uya` | 测试入口 |
