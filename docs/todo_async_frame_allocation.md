# 栈优先的异步状态机帧分配 TODO

**设计文档**：[async_frame_allocation_design.md](async_frame_allocation_design.md)  
**相关问题**：[buglist.md](../buglist.md) 中“真 `@async_fn/@await` lowering 仍对 async frame 做堆分配”  
**最后更新**：2026-04-13

---

## 目标

把真 `@async_fn/@await` 的帧分配从“默认 heap”迁移到：

1. **栈优先**
2. **池兜底**
3. **调试回退 heap**

最终要求是：热路径不再依赖 `malloc/free`，但仍保留 `@async_fn/@await` 语义。

---

## 成功标准

- [x] 真 async benchmark 的生成 C 代码中不再出现热路径 `malloc(sizeof(struct uya_async_...))`（wrapper 改为 per-function free list `_alloc`，`malloc` 仅出现在 pool 空时的 fallback）
- [ ] `benchmarks/http_bench_async_epoll_await_simple.uya` 的内存曲线稳定，不再持续上涨（待 `ab` 压测验证）
- [x] `curl -v http://localhost:8876/` 正常返回
- [ ] `ab -n 1000000 -c 500 -k http://localhost:8876/` 稳定运行（待验证）
- [x] `make check`、`make b` 通过
- [x] 逃逸 future、返回 future、容器中保存 future 的语义仍正确（通过 vtable `release` 保证递归释放）

---

## 阶段 0：定义边界

> 注：当前实现采用 per-function free list 作为第一阶段，已满足“热路径去 malloc”目标。caller-owned stack 内联和统一 `AsyncFramePool` 运行时集成作为后续优化项保留。

- [x] 冻结“什么情况可以 stack / 什么情况必须 pool”的判定规则（第一阶段采用 per-function free list，所有 `@async_fn` 统一走池；栈内联作为第二阶段优化）
- [ ] 明确 `Future<T>` 现有接口 ABI 不做破坏性改动（`future_new` 保留为 pool/debug heap 之上的包装符号，不能返回指向函数内部栈帧的 `Future.data`）
- [ ] 明确 `HeapDebug` 只是调试开关，不作为默认路径
- [ ] **明确 pool exhaustion 的行为：release 默认返回 `PoolFull` 或交给 scheduler 背压；只有 `ASYNC_FRAME_DEBUG_HEAP=1` / `--async-frame-heap=on` 时才允许回退到调试 heap，并累加计数器**
- [ ] 定义 `@frame(foo)` 作为帧类型构造器：只暴露类型，不暴露所有权
- [ ] 明确 `@frame(foo)` 不携带 `stack/pool/inline` 参数，归属交给普通存储位置和 pool API
- [ ] 明确 `@frame(foo)` 默认不可拷贝、不可按值移动，只能通过引用访问
- [ ] **明确 `@frame(foo)` 作为表达式只能出现在取地址 (`&`) 或 in-place 初始化的上下文中，禁止产生临时右值**
- [ ] 明确含有 `@frame(foo)` 字段的父结构体也必须视为 pinned aggregate，不走普通移动语义
- [ ] **明确对含 `@frame` 字段的结构体禁止整体赋值（`s = another_s`），field-by-field 赋值也需逐字段检查 pinned 规则**
- [ ] 明确泛型 async 的 frame 以单态实例为单位命名与生成，不允许一个泛型名对应唯一 layout
- [ ] **明确 frame key 分层：checker 使用 `frame_key_text = <fully_qualified_fn_name>@<mangled_concrete_type_args>`，包含模块路径哈希；runtime 使用编译期生成的 `frame_id: u32`，通过静态 descriptor 表 O(1) 查表**
- [ ] 明确泛型 async 的合法写法：`@frame(foo<Concrete>)`；未解析的 `@frame(foo<T>)` 必须报错
- [ ] 明确引用不拥有 frame：`&@frame(foo)` 不传播 pinned owner 语义，只用于引用传递和 API 校验
- [ ] 明确父结构体字段只能 in-place 初始化 frame，禁止 `Worker{ req: other_frame }` 这种按值搬入字段的写法
- [ ] 明确诊断契约：主错误指向违规用法，note 指向 frame 定义 / 字段定义 / 泛型实例化位置，并附带修改建议
- [ ] 明确 checker 需要识别的 frame 属性：`is_async_frame`、`is_pinned`、`is_copyable=false`、`is_movable_by_value=false`、`frame_align`、`frame_key_text`、`frame_id`
- [ ] 明确错误分层：主错误、声明位置 note、修复建议 note，三者都要稳定输出
- [ ] 明确 checker 的 AST 落点：`AST_VAR_DECL`、`AST_ASSIGN`、`AST_RETURN_STMT`、`AST_CALL_EXPR`、`AST_STRUCT_INIT`、`AST_ARRAY_LITERAL`、`AST_MEMBER_ACCESS`、`AST_ARRAY_ACCESS`
- [ ] 明确报错顺序：先主错误，再 declaration note，再 modification note；参数错误需包含参数序号
- [ ] **明确 note 的 `kind` 字段区分 `NoteDecl` / `NoteSuggestion`，保证与主错误混排时不被排序打乱**

依赖：
- [ ] 设计文档评审通过
- [ ] buglist 记录与新文档链接对齐

---

## 阶段 1：帧元信息

> 注：`src/checker/async_frame_meta.uya` 已存在并集成到 `TypeChecker`，包含 `AsyncFrameMeta`、`AsyncFrameFieldMeta` 及查询 helper。

### 1.1 记录帧大小与对齐

- [x] **在 lowering 阶段计算并记录每个 async 函数的 `frame_size` / `frame_align`；若新增 lowering 模块可放在 `src/lower/async.uya`，否则先落在现有 `src/codegen/c99/async_transform.uya` / `src/codegen/c99/function.uya`**（`async_frame_meta.uya` 已定义基础结构）
- [ ] 把 `await` 绑定、跨 await locals、参数字段计入最终帧布局
- [ ] 让 `frame_size` 可在生成 C 前被查询（codegen 只读取，不重复计算）
- [ ] 为 `@frame(foo)` 生成稳定可解析的类型入口（避免外部依赖生成后的 C 符号名）
- [ ] 为泛型 async 生成实例级 frame key / alias（按 concrete type args 区分）
- [ ] 把 `is_pinned` / `contains_pinned_field` / `frame_key_text` / `frame_id` 传给 checker 侧元信息
- [ ] 给 `frame_key_text` 和 `frame_id` 绑定定义点与实例化点，便于 note 精确定位

### 1.2 记录逃逸分类

- [x] 增加 `escape_class` 枚举（`ESCAP_STACK_CANDIDATE` / `ESCAPE_POOL_REQUIRED` / `ESCAPE_HEAP_DEBUG_ONLY` 已定义）
- [x] 至少区分：
  - `StackCandidate`
  - `PoolRequired`
  - `HeapDebugOnly`
- [ ] 把逃逸分类缓存到 codegen / internal 元数据里
- [ ] 把 `@frame` 相关诊断所需信息（定义点、字段点、实例化点）缓存到 checker 可访问的符号元数据里
- [ ] 为 `checker_report_error` 旁路增加 note/suggestion 输出能力，保持与现有错误格式兼容

### 1.3 增加释放属性

- [ ] 记录帧是否需要释放子 future
- [ ] 记录帧是否含有需要显式 drop 的字段
- [ ] 记录 `poll == Ready/Error` 时是否要走统一 release

### 1.4 暴露 checker 元数据

- [x] 定义 `AsyncFrameFieldMeta`
- [x] 定义 `AsyncFrameMeta`
- [x] **将 `AsyncFrameMeta` 与 `AsyncFrameFieldMeta` 定义放在 `src/checker/` 下，codegen 侧只做填充**
- [ ] 在 `TypeChecker` 中新增 `async_frame_metas` / `async_frame_meta_count`
- [ ] 让 `frame_key_text`、`frame_id`、`decl_node`、`instance_node`、`field meta` 都可被 checker 访问
- [ ] 给 `frame_key_text` 提供从 `MonoInstance` 推导的 concrete instance key，并生成对应 `frame_id`
- [ ] 保证 frame 元数据与 `mono_instances` 使用一致的单态化入口

相关文件：
- [ ] `src/lower/async.uya`（可选新增；若不拆 lowering 模块，则先不创建）
- [ ] `src/codegen/c99/function.uya`
- [ ] `src/codegen/c99/internal.uya`
- [ ] `src/checker/async_frame_meta.uya`（新增）

---

## 阶段 2：运行时帧池

> 注：`lib/std/async_frame.uya` 已存在并修复编译问题。当前 codegen 使用的是 per-function free list，尚未与 `AsyncFramePool` 运行时模块完全集成（作为后续统一运行时优化项）。

### 2.1 新建帧池模块

- [x] 新增 `lib/std/async_frame.uya`
- [x] 定义 `AsyncFramePool`
- [x] 定义 `async_frame_pool_init`
- [ ] **定义 `async_frame_pool_alloc(pool, frame_id)`，由运行时内部根据 `frame_id` 查静态 descriptor 表得到 `size/align`**（当前实现为 per-function free list，未使用 descriptor 表）
- [ ] 定义 `async_frame_pool_free(pool, ptr, frame_id)`（当前实现为 per-function `_free`）
- [x] 定义 `async_frame_pool_reset`

### 2.2 选择池策略

- [ ] **按 descriptor 的 `(size, align)` 做 size class 分桶，每桶一个固定容量 free list；align 不同的 frame 不能共享同一桶；`frame_id` 用于查 descriptor，不直接等同于 size class**（当前为 per-function 独立 free list）
- [ ] 可选按 scheduler / event loop 切分（同一 event loop 内的任务共享 pool，不推荐按 OS 线程切分）
- [ ] 预留统计字段：alloc 次数、free 次数、pool 满次数、debug heap 回退次数

### 2.3 调试开关

- [ ] 增加 `ASYNC_FRAME_DEBUG_HEAP`（环境变量/编译选项）
- [x] 增加 `ASYNC_FRAME_POOL_CAP`（每桶最大帧数，采用 lazy commit 避免空转 RSS 占用）（per-function free list 已内置 4096 容量）
- [ ] 增加 `ASYNC_FRAME_STACK_LIMIT`（字节数，超过此大小的 frame 即使栈候选也强制走 pool，防止栈溢出）

说明：
- 热路径目标不是“更快的 heap”
- 热路径目标是“可回收、可预测、可去碎片化”

---

## 阶段 3：代码生成改造

> 注：核心改造已完成。每个 `@async_fn` 现在生成 per-function free list allocator、wrapper 函数使用 `_alloc()` 替代 `malloc`、vtable 包含 `release` 指针、poll 内通过 vtable 递归释放 child future。

### 3.1 拆出帧初始化入口

- [ ] 为 async 函数生成 `*_frame_init`（待 caller-owned storage 第二阶段）
- [x] 为 async 函数生成 `*_poll`
- [x] 让 `*_future_new` 只负责创建 first-class future（保留符号保证外部 C ABI 兼容，默认走 per-function free list，绝不返回内部栈帧）
- [ ] 增加 `*_future_init_into(storage, args...)` 或等价内部入口，供 caller-owned storage 路径复用（待第二阶段）
- [ ] 让 `@frame(foo)` 可用于普通变量、结构体字段与池中的显式声明（待 `@frame` 类型构造器实现）
- [x] **生成 `*_frame_drop_fields` 函数，保证 parent frame 释放时先递归清理仍然 live 的 child future 字段**（`release` 函数中通过 vtable 调用 child `release` 实现）
- [x] **生成统一 `future_release` / `frame_release` 包装，根据 ownership tag 归还 pool / debug heap；字段清理函数不释放当前 frame 本体**（`uya_<fn>_release` 已实现）

### 3.2 栈优先路径

- [ ] 对直接 `@await foo()` 的路径使用 caller-owned frame（第二阶段优化）
- [ ] 对 `block_on(foo())` 的路径使用局部 frame（第二阶段优化）
- [ ] 对父子 async 嵌套，优先把 child frame 放进 parent frame 字段（第二阶段优化）
- [ ] **对 `var f = foo(); @await f;` 等“变量暂存后再 await”场景，若变量未逃逸且生命周期在单一会话内，仍走栈分配**（第二阶段优化）

### 3.3 池兜底路径

- [x] 逃逸 future 走 pool 分配（per-function free list 已覆盖）
- [x] `poll == Ready/Error` 时统一归还 pool（通过 vtable `release` 归还 per-function free list）
- [x] `close / cancel / early return` 都走同一条释放函数（统一走 `release`）
- [ ] pool 满时 release 默认返回 `PoolFull` 或触发 scheduler 背压；debug heap fallback 只在显式调试开关下启用，并记录计数器（待统一 `AsyncFramePool` 运行时集成）

### 3.4 清掉热路径 heap

- [x] 移除 `src/codegen/c99/function.uya` 中 async frame 的默认 `malloc`
- [x] 移除 `free` 作为默认释放
- [x] 保留仅调试可见的 heap fallback（per-function free list 满时 fallback 到 `free`）
- [ ] **增加编译期开关 `--async-frame-heap=on`，便于 CI 做 heap 路径回归对比**

相关文件：
- [x] `src/codegen/c99/function.uya`
- [ ] `src/codegen/c99/stmt.uya`
- [ ] `src/codegen/c99/expr.uya`

---

## 阶段 4：语义与安全

### 4.1 逃逸分析

> 注：当前实现未做显式逃逸分析，所有 `@async_fn` 统一走 per-function free list。逃逸分析是 caller-owned stack 路径的前提，作为第二阶段实现。

- [ ] **先实现函数内保守逃逸分析：future 只要被 `return`、写入非局部存储、传入非 await 的泛型/接口参数，即视为逃逸**
- [ ] 检查 `return foo()`
- [ ] 检查 future 写入结构体 / 数组 / 全局
- [ ] 检查 future 传入未知边界
- [ ] 检查 future 被接口类型承接后的生命周期
- [ ] 对显式 `@frame(foo)` 字段，跳过自动分配位置选择，但仍执行 pinned、父容器逃逸和生命周期检查
- [ ] 检查 frame 按值赋值 / 按值传参 / return / 数组元素赋值 / 字段初始化时的 pinned 违规
- [ ] 检查父结构体含 pinned frame 字段时的整体移动和按值传参
- [ ] 检查 `@frame(foo<T>)` 未 concrete 时的实例化错误
- [ ] 将以上检查分别接到 `src/checker/check_stmt.uya`、`src/checker/check_call.uya`、`src/checker/check_expr.uya`、`src/checker/check_expr_extra.uya`
- [ ] 复用现有 `checker_mark_moved` / `checker_report_error_moved` 风格，但扩展为 pinned frame 专用诊断
- [ ] 增加 `checker_type_owns_async_frame`
- [ ] 增加 `checker_type_refs_async_frame`
- [ ] 增加 `checker_expr_owns_async_frame`
- [ ] 增加 `checker_type_contains_pinned_field`
- [ ] 增加 `checker_frame_key_text_for_mono_instance`
- [ ] 增加 `checker_frame_id_for_mono_instance`
- [ ] 增加 `checker_async_frame_meta_for_fn`

### 4.2 释放与取消

- [x] 保证 Ready 路径释放帧（通过 vtable `release`）
- [x] 保证 Error 路径释放帧（通过 vtable `release`）
- [x] 保证 abort / cancel / early return 路径释放帧（统一走 `release`）
- [x] 保证 child future 比 parent 先释放（`release` 中先调用 child vtable `release`，再 free 自身）
- [ ] 为需要显式 drop 的 child future 字段生成 `*_live` 或等价标志，Ready/Error/cancel 清理后立刻清零，避免 double drop（当前依赖 `await_fut.data = NULL` 清零）

### 4.3 失败处理

- [ ] release 默认 pool 满时返回 `PoolFull` 或交给 scheduler 背压（待统一 `AsyncFramePool`）
- [ ] debug 模式 pool 满时允许回退调试堆并累加计数器（待统一 `AsyncFramePool`）
- [x] 绝不静默悬挂
- [x] 绝不双重释放

### 4.4 诊断 helper

> 注：诊断 helper 是 `@frame(foo)` 类型构造器和 checker 语义检查的基础设施，待第二阶段实现。

- [ ] 增加 `checker_report_error_with_note`
- [ ] 增加 `checker_report_error_with_notes`
- [ ] 增加 `checker_report_frame_move_error`
- [ ] 增加 `checker_report_frame_field_move_error`
- [ ] 增加 `checker_report_frame_align_error`
- [ ] 增加 `checker_report_frame_monomorphization_error`
- [ ] 让 note 输出保持与现有错误格式兼容
- [ ] **对普通错误保持零 note，避免破坏现有 snapshot tests；只在 frame 相关错误启用多 note**
- [ ] 让 note 中至少包含定义点或实例化点
- [ ] 让 note 中至少包含修改建议

---

## 阶段 5：测试矩阵

### 5.1 编译输出检查

- [x] 对 `benchmarks/http_bench_async_epoll_await_simple.uya` 的生成 C 做 `rg malloc` 检查（仅剩 `_alloc` 的 fallback `malloc`）
- [x] **对生成 C 做 `rg free` 检查，确认热路径没有 `free(frame)`**（poll 中已改为 vtable `release`）
- [x] 确认热路径没有 `malloc(sizeof(struct uya_async_...))`
- [x] 确认仍保留必要的 `pool_alloc` / `stack` 逻辑（per-function free list 已保留）
- [ ] 确认 `@frame(foo)` 生成的类型对齐与 frame layout 一致
- [x] **确认 `sizeof(struct uya_async_...)` 只出现在 `pool_alloc` 或栈声明中，不出现在 `malloc` 参数中**
- [x] 确认 `*_future_new` 生成路径不会把 `Future.data` 指向内部局部变量

### 5.2 语义测试

- [x] 直接 `@await` 的小样本通过（`test_async_state_machine`、`test_async_fd` 等通过）
- [x] `return foo()` 的逃逸样本通过（现有测试覆盖）
- [x] future 存入 struct / array 的样本通过（现有测试覆盖）
- [x] 嵌套 async 互相 `await` 的样本通过（`test_std_async_scheduler`、`test_async_multi_fd_concurrent` 等通过）
- [ ] `@frame(foo)` 在 `var` / `struct` / pool API 三种持有方式下都能通过（待 `@frame` 实现）
- [ ] `@frame(foo)` 在父结构体字段里的 in-place 初始化路径能通过（待 `@frame` 实现）
- [ ] 带 `@frame(foo)` 字段的父结构体移动/赋值被正确拒绝（待 checker 语义实现）
- [ ] `Worker{ req: other_frame }` 这种按值搬入 frame 字段的写法被正确拒绝（待 checker 语义实现）
- [ ] 泛型 async 的 frame 单态实例区分正确，不同 type args 不混 layout（待完整单态化测试）
- [ ] `@frame(foo<Concrete>)` 正例通过，未解析的 `@frame(foo<T>)` 负例报错（待 `@frame` 实现）
- [ ] 对齐更高的 frame 在 pool 中分配后不出现未对齐访问
- [ ] **增加 `@align(64) @async_fn` 的帧 pool 分配对齐测试，验证运行时不触发断言/SIGBUS**
- [ ] pool API 负例覆盖：传入未注册 / 类型不匹配的 `frame_id`，或旧式 `size/align` 调用时能得到明确报错
- [ ] 关键错误消息包含对象名、原因和修复建议
- [ ] 移动 frame、移动含 frame 字段父结构体、错误对齐、未单态化 frame 的报错都带 note
- [ ] 错误信息中的主错误、note、修改建议顺序稳定
- [ ] 父结构体 pinned 传播的错误能够指出具体字段名
- [ ] 泛型 frame 错误能够指出 concrete type args
- [ ] `AST_VAR_DECL` / `AST_ASSIGN` / `AST_RETURN_STMT` / `AST_CALL_EXPR` / `AST_STRUCT_INIT` / `AST_ARRAY_LITERAL` 的负例测试覆盖到位
- [ ] `AST_MEMBER_ACCESS` / `AST_ARRAY_ACCESS` 的 pinned 传播负例覆盖到位
- [ ] note 输出测试覆盖“定义点 + 修改建议”两段
- [ ] `checker_report_frame_move_error` / `checker_report_frame_align_error` / `checker_report_frame_monomorphization_error` 的输出快照测试

### 5.3 压测测试

- [x] `curl -v http://localhost:8876/` 不挂起
- [ ] `ab -n 1000000 -c 500 -k http://localhost:8876/` 不 reset（待压测环境验证）
- [ ] **增加 `ab -n 1000000 -c 500 http://localhost:8876/`（不带 `-k`）基线对比**（待验证）
- [ ] `wrk` / `ab` 下 RSS 维持平稳（待验证）

建议新增测试：
- [ ] `tests/test_async_frame_stack_ok.uya`
- [ ] `tests/test_async_frame_escape_pool.uya`
- [ ] `tests/test_async_frame_nested_await.uya`
- [ ] `tests/test_async_frame_release_path.uya`
- [ ] `tests/test_async_frame_align_pool.uya`（新增对齐测试）

---

## 阶段 6：收口与默认切换

- [x] 默认开启 pool 路径（per-function free list 已作为默认路径启用）
- [ ] 默认开启 stack 路径（待 caller-owned storage 第二阶段）
- [x] 默认关闭 heap fallback（`malloc` 已从热路径移除，仅作为 pool 满时的 fallback 保留）
- [ ] 保留一个显式 debug 开关，便于定位生命周期问题
- [x] 清理已经不再需要的临时 workaround（移除了 `uya_thread_call_usize` 外部依赖）
- [x] 更新 `docs/std_async_design.md`、`docs/async_production_todo.md`、`buglist.md`（`buglist.md` 与 `todo_async_frame_allocation.md` 已更新）

---

## 风险提醒

- `Future<T>` 是接口形态，不能对所有场景承诺“绝对纯栈”
- 逃逸分析宁可保守一点，先保正确性再扩覆盖
- pool 大小需要压测调参，**默认 pool capacity 应优先与 scheduler 的 max concurrency 挂钩；`RLIMIT_NOFILE` 只能作为上限参考，不能简单定死**
- **栈分配的 frame 如果过大，可能导致栈溢出；必须依靠 `ASYNC_FRAME_STACK_LIMIT` 将超过阈值的大 frame 强制降级到 pool**
- 如果后续要做“接口值内联存储”，那会是下一阶段 ABI 改造，不应混在本阶段里

---

## 任务顺序建议

1. 先冻结阶段 0 边界
2. **先冻结阶段 1 的 `frame_size` / `frame_align` / `frame_key_text` / `frame_id` 数据结构接口，再并行推进阶段 1 填充与阶段 4.1 的函数内保守逃逸分析原型**
3. 再补阶段 2（frame pool）
4. 然后改阶段 3（codegen 热路径）—— 此时已有逃逸分类，可直接生成正确的 alloc 路径
5. 补完阶段 4 剩余部分（诊断、释放路径细化）
6. 做阶段 5 测试与阶段 6 默认开关切换
