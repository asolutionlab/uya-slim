# Uya v0.9.3 发布说明

> 发布日期：2026-04-14

## 概要

v0.9.3 引入 `@frame(foo)` 类型构造器及其完整的 checker 语义，为显式控制 async frame 的存储位置提供语言级支持，同时通过 pinned 语义保证帧在运行时的地址稳定性。

---

## 新增特性

### 1. `@frame(foo)` 类型构造器

语法：

```uya
var f: @frame(some_async_fn);           // 无初始化，由声明点分配
var f: @frame(generic_async<i32>);      // 支持泛型单态实例
```

- 解析器支持 `@frame(fn_name[<T>])` 语法。
- 类型检查器将其解析为 `TYPE_STRUCT("uya_async_<fn>")`。
- `@frame` 类型变量允许无显式初始化（由声明点负责零初始化）。

### 2. Pinned 语义检查

async frame 被视为 **pinned** 类型，禁止以下操作：

- **整体赋值**：`a = b` 报错 `cannot assign to pinned type`
- **按值初始化**：`var a = frame` 报错 `cannot initialize variable with pinned type by value`
- **按值传参**：`foo(frame)` 报错 `cannot pass pinned type by value in function argument`
- **按值返回**：`return frame` 报错 `cannot return pinned type by value`

按引用传递（`&frame`）不受影响。

### 3. C99 前向声明

codegen 在函数原型中自动为 `@frame` 参数/返回类型生成 `struct uya_async_xxx;` 前向声明，避免跨 TU 编译时出现 incomplete type 错误。

---

## 测试

- `make check`：**785** 项测试全部通过（新增 5 项）
- `make b`：自举验证通过，主编译器与自举编译器生成的可执行文件字节相同

新增测试：

- `tests/test_async_frame_type.uya` — 3 项正向测试
- `tests/error_async_frame_pinned_move.uya`
- `tests/error_async_frame_pinned_arg.uya`
- `tests/error_async_frame_pinned_return.uya`
- `tests/error_async_frame_pinned_method_arg.uya`

---

## 相关文件变更

- `src/lexer.uya`
- `src/parser/types.uya`
- `src/parser/statements.uya`
- `src/checker/type_from_ast.uya`
- `src/checker/check_node_extra.uya`
- `src/checker/check_stmt.uya`
- `src/checker/check_call.uya`
- `src/checker/main.uya`
- `src/codegen/c99/types.uya`
- `src/codegen/c99/function.uya`
- `docs/async_frame_allocation_design.md`
- `docs/todo_async_frame_allocation.md`
