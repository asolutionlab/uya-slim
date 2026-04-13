# 栈优先的异步状态机帧分配设计

**状态**：设计草案  
**最后更新**：2026-04-13  
**相关文档**：
- [std_async_design.md](std_async_design.md) - `Future<T>` / `Poll<T>` / `Waker` / `Scheduler` 现状
- [async_coroutine_transform_design.md](async_coroutine_transform_design.md) - 通用 async lowering / await 段发射
- [plan_async_coroutine_transform.md](plan_async_coroutine_transform.md) - 现有 lowering 计划
- [todo_async_loop_await.md](todo_async_loop_await.md) - 循环内 await 的历史问题与回归
- [buglist.md](../buglist.md) - 真 `@async_fn/@await` async frame 堆分配 bug

## 1. 背景

当前真 `@async_fn/@await` 的 lowering 会把 async frame 直接装箱到堆上。  
在 `benchmarks/http_bench_async_epoll_await_simple.uya` 这类高频短连接 / keep-alive 压测里，生成的 C 代码会出现热路径 `malloc/free`，典型现象是：

- CPU 占用下降
- RSS 持续上涨
- 性能远低于手写 `Future` / 手写状态机版本

根因不是 `epoll` 本身，而是 `@async_fn` 的状态机帧目前仍然以“接口 + 堆对象”方式构造。

## 2. 关键约束

### 2.1 当前 ABI 现实

`lib/std/async.uya` 里的 `Future<T>` 仍是接口形态，运行时表现为：

- `vtable`
- `data`

这意味着：

- 一个“悬挂中的 future 帧”必须有稳定地址
- 只要 future 可能在函数返回后继续被 `poll()`，它就不能简单放在当前函数的自动变量里
- 所谓“纯栈分配”只能对**可证明不逃逸**的 future 成立

### 2.2 不能无条件纯栈

以下场景不能把帧无条件放在当前调用栈上：

- `return foo();`
- `let fut = foo();` 之后延迟很久才 poll
- future 被存进结构体、数组、接口字段或全局状态
- future 需要跨抽象边界传递给未知生命周期的代码

所以本设计不是“所有 async 都强制纯栈”，而是：

1. **栈优先**
2. **池兜底**
3. **仅调试模式才允许 heap fallback**

## 3. 设计目标

- 去掉热路径上的 `malloc/free`
- 保持 `@async_fn/@await` 语义不变
- 让直接 `@await foo()` 的场景尽量走“调用方持有的本地帧”
- 让不逃逸的 async frame 复用栈或调用方持有的内联存储
- 让逃逸的 future 走固定池分配，而不是默认堆分配
- 保留调试回退路径，便于定位生命周期问题

## 4. 总体方案

### 4.1 帧类型与帧位置

把一个 async 函数拆成三件事：

1. **帧结构体**：`struct uya_async_<fn>`
2. **poll 入口**：`fn <fn>_poll(self: &Self, waker: &Waker) Poll<T>`
3. **帧构造入口**：`fn <fn>_frame_init(frame: &uya_async_<fn>, args...)`

帧的存储位置分为四类：

- `StackOwned`
  - 存在当前函数的自动变量里
  - 只用于能证明不逃逸的局部 async 片段
- `InlineOwned`
  - 嵌在父 async 帧结构体字段里
  - 适合 `@await` 直接消费子 future 的路径
- `PoolOwned`
  - 来自固定大小的 frame pool
  - 用于会跨调用边界但仍希望避免 heap 的 future
- `HeapDebug`
  - 仅在显式调试开关下启用
  - 用于保留老行为，方便排查生命周期 bug

### 4.2 两条生成路径

#### 路径 A：直接 await / 父子协程内联

当 `@await foo()` 出现在另一个 async 函数内部，且 `foo()` 的结果不会逃逸时：

- 编译器生成 `foo_frame_init(...)`
- 帧直接写入父帧字段或调用方自动变量
- `poll` 时直接访问该内联帧
- 不经过堆分配

#### 路径 B：第一类 future 值

当 future 需要作为值返回、存入容器、传给接口字段或跨边界保存时：

- 编译器生成 `foo_future_new(...)`
- 该入口先走逃逸分析
- 逃逸但仍可池化时，用 frame pool 分配
- 只有在显式调试模式下才 fallback 到 heap

### 4.3 帧的移动语义

`@frame(foo)` 不是一个可自由复制 / 自由移动的普通值。它是一个**受约束的 pinned 帧类型**：

- 默认 **不可拷贝**
- 默认 **不可按值移动**
- 只能通过 `&frame` 访问
- `poll()` 只接受帧的引用，不接受按值传递

原因是 async 帧内部会持有：

- 当前状态号
- 子 future / await 槽位
- 跨 await 存活的局部变量
- 可能由 `@await` 暂存的内部指针

一旦把 frame 当普通值移动，这些内部引用就可能失效。

因此，开发者可以把 frame 放在：

- 局部变量
- 父结构体字段
- frame pool 中

但**不能**把 frame 当成普通可移动 struct 随意赋值、返回或重新装箱。  
如果某个父结构体含有 frame 字段，那么这个父结构体也必须被编译器视为 pinned aggregate，不能再走普通移动语义。

### 4.4 诊断契约

这类约束必须报**明确、可操作**的编译错误，而不是只报“类型不匹配”或“内部错误”。

建议统一遵守以下规则：

- **主错误指向违规用法本身**
  - 例如：移动发生处、按值传参处、返回处、字段赋值处、错误的池分配处
- **附加说明指向 frame 定义处 / 字段定义处**
  - 例如：`@frame(foo)` 定义、包含 frame 字段的父结构体声明、泛型实例化位置
- **错误信息必须包含可识别的对象名**
  - 例如：`@frame(http_handle)`、`Worker.req`、`foo<T>`、`align=16`
- **必须带修改建议**
  - 例如：改用引用、把 frame 放进 pinned 父结构体、改用 `async_frame_pool_alloc(pool, size, align)`、先单态化再取 frame

推荐的错误模板：

- `error: cannot move pinned async frame '@frame(http_handle)'`
  - `note: async frame is pinned; keep it by reference or place it in a pinned parent struct`
- `error: struct 'Worker' contains pinned field 'req: @frame(http_handle)' and cannot be moved by value`
  - `note: move the struct by reference, or store the frame in a pool-backed holder`
- `error: async frame allocation alignment mismatch for '@frame(foo<T>)'`
  - `note: requested align=16, but the pool/API only guarantees align=8`
- `error: '@frame(foo<T>)' requires a monomorphized instance`
  - `note: instantiate 'foo<T>' with concrete type arguments before taking its frame type`

实现上，checker 应优先产出：

1. 主错误位置信息
2. 相关声明位置 note
3. 修复建议 note

### 4.5 checker 识别规则

`@frame(foo)` 相关约束不应该靠“约定”来维持，而应该被 checker 显式识别。建议把它们视为一组可判定的类型属性：

- `is_async_frame = true`
- `is_pinned = true`
- `is_copyable = false`
- `is_movable_by_value = false`
- `frame_align = N`
- `frame_key = concrete_instance_key`

当 checker 遇到下列操作时，应直接报错：

| 违规场景 | checker 触发点 | 建议错误主题 | 建议 note |
| --- | --- | --- | --- |
| 按值赋值 frame | `var a = b` / `a = b` | `cannot move pinned async frame` | `frame is pinned; use reference or pool holder` |
| 按值传参 frame | 函数调用实参标识符 | `cannot pass pinned async frame by value` | `pass by reference instead` |
| 返回 frame | `return frame` | `cannot return pinned async frame by value` | `return a handle/reference or pool-owned wrapper` |
| 结构体字段初始化 | `Container{ field: frame }` | `cannot move pinned async frame into field by value` | `initialize the field in place or store a reference` |
| 数组元素赋值 | `arr[i] = frame` | `cannot store pinned async frame by value` | `store pointer/reference or pool slot` |
| 父结构体整体移动 | `move Parent` | `struct contains pinned frame field and cannot be moved` | `move by reference or redesign ownership` |
| 错误对齐分配 | pool alloc / cast 入口 | `async frame allocation alignment mismatch` | `requested align=N, allocator guarantees align=M` |
| 未单态化 frame | `@frame(foo<T>)` 未 concrete | `requires a monomorphized instance` | `instantiate concrete type arguments first` |

checker 的报错策略建议保持一致：

- 主错误放在**发生违规的表达式**上
- `note` 至少给出一个**定义位置**
- `note` 至少给出一个**修改建议**
- 如果涉及父结构体，note 应指出**哪个字段导致 pinned 传播**
- 如果涉及泛型，note 应指出**具体的 type args 实例**

### 4.6 checker 落点

现有 checker 已经有移动追踪基础，因此这套规则应尽量挂在已有入口上，而不是另起一套特殊路径。建议按 AST 节点拆分：

| AST 节点 | 触发位置 | 需要检查的内容 | 推荐报错位置 |
| --- | --- | --- | --- |
| `AST_VAR_DECL` | `var x = y` / `var x = frame` | 初始化值是否为 pinned frame、是否把 pinned frame 放进可移动父结构体 | 初始化表达式或变量声明处 |
| `AST_ASSIGN` | `x = y`、`obj.field = y`、`arr[i] = y` | 左值是否承接 pinned frame、父结构体是否含 pinned 字段、数组元素是否间接保存 frame | 赋值语句处 |
| `AST_RETURN_STMT` | `return frame` | 是否把 frame 作为按值返回值返回 | `return` 关键字处 |
| `AST_CALL_EXPR` | 函数实参按值传递 | 实参是否是 pinned frame；形参是否要求按值接收 frame | 实参位置，必要时补参数序号 note |
| `AST_STRUCT_INIT` | `T{ field: frame }` | 字段是否把 pinned frame 作为按值成员写入 | 字段值表达式处 |
| `AST_ARRAY_LITERAL` | `[frame, ...]` | 元素是否保存 pinned frame | 元素表达式处 |
| `AST_MEMBER_ACCESS` | 读/写 frame 字段 | 是否访问到包含 pinned frame 的父结构体字段 | 只有在后续移动/赋值时才报错 |
| `AST_ARRAY_ACCESS` | 读/写 frame 数组元素 | 是否访问到保存 frame 的元素槽位 | 只有在后续移动/赋值时才报错 |

建议的实现顺序：

1. 先在 `AST_VAR_DECL` / `AST_ASSIGN` / `AST_RETURN_STMT` 上拦住最直接的按值移动
2. 再补 `AST_CALL_EXPR` 的按值传参与参数序号提示
3. 再补 `AST_STRUCT_INIT` / `AST_ARRAY_LITERAL` 的嵌套保存检查
4. 最后补 `AST_MEMBER_ACCESS` / `AST_ARRAY_ACCESS` 的递归传播，让父结构体 pinned 属性往外层扩散

### 4.7 建议的 checker 元数据与 helper

为了让上面的落点变成可实现的代码，建议在 checker 侧新增一层 async frame 元数据。结构风格可以直接参考现有的 `MonoInstance`：固定上限数组 + 线性查找 + 单态实例键。

#### 4.7.1 建议新增的元数据结构

- `AsyncFrameFieldMeta`
  - `field_name: &byte`
  - `field_type: Type`
  - `field_offset: usize`
  - `field_align: usize`
  - `is_pinned: i32`
  - `is_movable_by_value: i32`
- `AsyncFrameMeta`
  - `frame_key: &byte`
  - `fn_name: &byte`
  - `generic_name: &byte`
  - `type_arg_count: i32`
  - `decl_node: &ASTNode`
  - `instance_node: &ASTNode`
  - `frame_size: usize`
  - `frame_align: usize`
  - `escape_class: i32`
  - `is_pinned: i32`
  - `contains_pinned_field: i32`
  - `needs_drop: i32`
  - `field_count: i32`
  - `fields: [AsyncFrameFieldMeta: N]`

建议在 `TypeChecker` 里增加与 `mono_instances` 同风格的表：

- `async_frame_metas: [AsyncFrameMeta: N]`
- `async_frame_meta_count: i32`
- `async_frame_key_index: ...`（可选，后续再做索引表）

这些元数据的职责是：

- 给 checker 提供 `frame_key -> meta` 的稳定查询入口
- 给 note 输出提供定义点 / 实例化点 / 字段点
- 给泛型 async 的单态实例区分提供依据

#### 4.7.2 建议新增的查询 helper

建议把“是不是 frame / frame 是否 pinned / 是否拥有 frame / 是否引用 frame”拆成独立 helper，这样 AST 各入口都可以复用：

- `checker_register_async_frame_meta(...)`
  - 在检查 async 函数声明时注册 frame 元数据
- `checker_register_async_frame_field_meta(...)`
  - 记录 frame 字段、偏移、对齐、是否 pinned
- `checker_find_async_frame_meta_by_key(checker, frame_key)`
  - 线性查找 frame 元数据
- `checker_async_frame_meta_for_fn(checker, fn_decl)`
  - 从函数声明直接取 frame 元数据
- `checker_frame_key_for_mono_instance(checker, generic_name, type_args, type_arg_count)`
  - 为 `foo<T>` 生成 concrete instance key
- `checker_is_async_frame_type(checker, type)`
  - 判断某个 `Type` 是否为 async frame
- `checker_type_owns_async_frame(checker, type)`
  - 判断结构体 / 数组 / 元组等按值存储层里是否拥有 frame；指针 / 引用包装层不算 owner
- `checker_type_refs_async_frame(checker, type)`
  - 判断某个引用类型是否指向 async frame；该 helper 只用于诊断和 API 校验，不传播 pinned owner 语义
- `checker_expr_owns_async_frame(checker, expr)`
  - 供 `AST_STRUCT_INIT`、`AST_ARRAY_LITERAL`、`AST_ASSIGN`、`AST_RETURN_STMT` 复用
- `checker_type_contains_pinned_field(checker, type)`
  - 判断父结构体是否因为 frame 字段而变成 pinned aggregate

#### 4.7.3 建议新增的诊断 helper

现有 `checker_report_error` 只打印主错误。为了满足“主错误 + note + 修改建议”的需求，建议补一组专用 helper，输出格式尽量稳定：

- `checker_report_error_with_note(checker, node, message, note)`
- `checker_report_error_with_notes(checker, node, message, note1, note2)`
- `checker_report_frame_move_error(checker, node, frame_name)`
- `checker_report_frame_field_move_error(checker, node, parent_name, field_name, frame_name)`
- `checker_report_frame_align_error(checker, node, frame_name, requested_align, actual_align)`
- `checker_report_frame_monomorphization_error(checker, node, generic_name)`

建议约定：

- 主错误仍然占第一行
- note 用缩进行输出
- note 至少包含一个“定义位置”或“实例化位置”
- note 至少包含一个“怎么改”

例如：

```text
file.uya:(12:5): 错误: cannot move pinned async frame '@frame(http_handle)'
  note: async frame is pinned; keep it by reference or place it in a pinned parent struct
  note: field 'req' in 'Worker' holds this frame
```

## 5. 逃逸分析

### 5.1 需要判定的输入

编译器需要为每个 async 函数记录：

- `frame_size`
- `frame_align`
- `needs_drop`
- `child_future_count`
- `has_nested_await`
- `escape_class`

### 5.2 逃逸来源

一个 future 视为逃逸，常见原因包括：

- 函数返回 future 本身
- future 存入结构体字段 / 数组元素 / 全局变量
- future 被转成接口值并传给未知边界
- future 被保存在任务队列里，生命周期超过当前栈帧

### 5.3 安全判定

满足以下条件时，可走 `StackOwned` 或 `InlineOwned`：

- future 的生命周期被当前函数完整覆盖
- 不会从当前函数返回后继续被 poll
- 没有被写入会逃逸的存储位置

如果无法证明安全，就选择 `PoolOwned`。

## 6. 运行时接口

建议新增一个轻量模块，例如：

- `lib/std/async_frame.uya`

建议提供这些能力：

- `AsyncFramePool`
- `async_frame_pool_init`
- `async_frame_pool_alloc`
- `async_frame_pool_free`
- `async_frame_pool_reset`

建议额外提供调试配置：

- `ASYNC_FRAME_DEBUG_HEAP`
- `ASYNC_FRAME_POOL_CAP`
- `ASYNC_FRAME_STACK_LIMIT`

### 6.1 Pool 语义

Pool 不是“为了更快地 malloc”。
它的目标是：

- 不进通用堆分配器
- 不在热路径上做碎片化分配
- 可重复回收
- 可按线程或按 scheduler 切分

Pool 分配接口必须带对齐信息，不能只传 size。  
frame 的布局由 `frame_size` 和 `frame_align` 共同决定。

建议的最小接口形态：

```uya
fn async_frame_pool_alloc(pool: &AsyncFramePool, size: usize, align: usize) !&byte;
fn async_frame_pool_free(pool: &AsyncFramePool, ptr: &byte, size: usize, align: usize) void;
```

若需要更方便的泛型封装，可再提供：

```uya
fn async_frame_pool_alloc_t<T>(pool: &AsyncFramePool) !&T;
```

### 6.2 Stack 语义

Stack 路径只负责“当前作用域内可证明安全”的 frame：

- 不需要 free
- 退出作用域自动销毁
- 只适用于编译器能看见完整生命周期的路径

## 7. 代码生成改动

### 7.1 `src/codegen/c99/function.uya`

这个文件是主改动点。需要：

- 把当前 `malloc(sizeof(...))` 的 async frame 创建改成“帧初始化 + 位置选择”
- 生成 `*_frame_init` 和 `*_poll`
- 保留 vtable / interface 包装
- 在能内联的 await 路径上生成 caller-owned frame，而不是额外装箱

### 7.2 `src/codegen/c99/stmt.uya`

需要配合处理：

- `return try @await ...`
- 直接返回 future 的路径
- 需要把“儿子 future”写进父帧字段而不是立刻 heap box 的路径

### 7.3 `src/codegen/c99/internal.uya`

建议新增：

- 帧大小/对齐的元信息结构
- 逃逸分类缓存
- `can_stack` / `needs_pool` / `needs_heap_debug` 标志位

### 7.4 `lib/std/async.uya`

建议保留当前 `Future<T>` 接口，但补充：

- frame pool 相关辅助函数
- `Future` 的构造和释放辅助
- 诊断辅助函数（例如池耗尽计数）

### 7.5 对外暴露 `@frame(foo)`

为了避免开发者直接接触编译器生成的具体符号名，建议对外提供一个稳定的帧类型构造器：

```uya
var f: @frame(http_handle) = @frame(http_handle){};
```

它的语义是：

- `@frame(foo)` 代表 `foo` 这个 `@async_fn` 对应的帧类型
- 它**只暴露类型，不暴露所有权**
- 它**不带** `stack/pool/inline` 之类的归属参数
- 归属由普通变量、结构体字段、池 API 决定
- 对于泛型 async 函数，`@frame(foo<Concrete>)` 表示**单态化后的具体实例**，不是抽象的泛型族；不同类型实参会得到不同的 frame layout
- `@frame(foo<T>)` 只有在 `T` 已经是当前单态化上下文中的具体类型实参时才合法；如果 `T` 仍是未解析泛型参数，checker 必须报错

因此，下面三种写法都可以持有同一帧类型：

```uya
var a: @frame(http_handle) = @frame(http_handle){};

struct Worker {
    req: @frame(http_handle),
}

var worker: Worker = Worker{};
http_handle_frame_init(&worker.req, cfd);

const p: &byte = try async_frame_pool_alloc(
    pool,
    @size_of(@frame(http_handle)),
    @align_of(@frame(http_handle)),
);
const c: &@frame(http_handle) = p as &@frame(http_handle);
```

如果要取泛型 async 函数的帧类型，必须写成具体实例：

```uya
var f_i32: @frame(load_item<i32>) = @frame(load_item<i32>){};
```

结构体字段可以拥有 frame，但字段应通过 in-place 初始化进入可用状态。`Worker{ req: other_frame }` 这种从另一个 frame 按值搬进字段的写法仍然非法。

`@frame(foo)` 只是把“编译器生成的内部帧类型”变成可见、可声明、可存储的类型视图，便于 runtime 和高性能框架显式管理生命周期。

## 8. 推荐的分层落地

### 第一层：去掉热路径 heap

先保证：

- 常见 async benchmark 不再 `malloc/free`
- 允许 pool 分配
- stack 优先仅用于可证明安全的局部路径

### 第二层：扩大 stack 覆盖面

通过逃逸分析把更多 `@await` 子 future 转成调用方持有的内联帧。

### 第三层：调试回退收口

当主路径稳定后：

- 默认关闭 heap fallback
- heap 仅作为 debug/diagnostic 开关存在

## 9. 风险点

- `Future<T>` 仍是接口，纯栈并不能覆盖所有用法
- 逃逸分析过保守会导致大量 fallback 到 pool
- 逃逸分析过激进会引入悬挂指针
- pool 大小过小会产生 `PoolFull`
- pool 大小过大又会占用额外内存

## 10. 验收标准

- `benchmarks/http_bench_async_epoll_await_simple.uya` 生成的 C 代码中，热路径不再出现 `malloc(sizeof(struct uya_async_...))`
- `curl -v http://localhost:8876/` 正常返回
- `ab -n 1000000 -c 500 -k http://localhost:8876/` 不再因为 frame 分配导致 reset / RSS 飙升
- `make check`、`make b` 通过
- 逃逸路径仍然正确释放，不出现 use-after-free 或 double free
