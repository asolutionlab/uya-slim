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

- [ ] 真 async benchmark 的生成 C 代码中不再出现热路径 `malloc(sizeof(struct uya_async_...))`
- [ ] `benchmarks/http_bench_async_epoll_await_simple.uya` 的内存曲线稳定，不再持续上涨
- [ ] `curl -v http://localhost:8876/` 正常返回
- [ ] `ab -n 1000000 -c 500 -k http://localhost:8876/` 稳定运行
- [ ] `make check`、`make b` 通过
- [ ] 逃逸 future、返回 future、容器中保存 future 的语义仍正确

---

## 阶段 0：定义边界

- [ ] 冻结“什么情况可以 stack / 什么情况必须 pool”的判定规则
- [ ] 明确 `Future<T>` 现有接口 ABI 不做破坏性改动
- [ ] 明确 `HeapDebug` 只是调试开关，不作为默认路径
- [ ] 明确 pool exhaustion 的行为：报错、阻塞、还是回退调试堆
- [ ] 定义 `@frame(foo)` 作为帧类型构造器：只暴露类型，不暴露所有权
- [ ] 明确 `@frame(foo)` 不携带 `stack/pool/inline` 参数，归属交给普通存储位置和 pool API
- [ ] 明确 `@frame(foo)` 默认不可拷贝、不可按值移动，只能通过引用访问
- [ ] 明确含有 `@frame(foo)` 字段的父结构体也必须视为 pinned aggregate，不走普通移动语义
- [ ] 明确泛型 async 的 frame 以单态实例为单位命名与生成，不允许一个泛型名对应唯一 layout
- [ ] 明确泛型 async 的合法写法：`@frame(foo<Concrete>)`；未解析的 `@frame(foo<T>)` 必须报错
- [ ] 明确引用不拥有 frame：`&@frame(foo)` 不传播 pinned owner 语义，只用于引用传递和 API 校验
- [ ] 明确父结构体字段只能 in-place 初始化 frame，禁止 `Worker{ req: other_frame }` 这种按值搬入字段的写法
- [ ] 明确诊断契约：主错误指向违规用法，note 指向 frame 定义 / 字段定义 / 泛型实例化位置，并附带修改建议
- [ ] 明确 checker 需要识别的 frame 属性：`is_async_frame`、`is_pinned`、`is_copyable=false`、`is_movable_by_value=false`、`frame_align`、`frame_key`
- [ ] 明确错误分层：主错误、声明位置 note、修复建议 note，三者都要稳定输出
- [ ] 明确 checker 的 AST 落点：`AST_VAR_DECL`、`AST_ASSIGN`、`AST_RETURN_STMT`、`AST_CALL_EXPR`、`AST_STRUCT_INIT`、`AST_ARRAY_LITERAL`、`AST_MEMBER_ACCESS`、`AST_ARRAY_ACCESS`
- [ ] 明确报错顺序：先主错误，再 declaration note，再 modification note；参数错误需包含参数序号

依赖：
- [ ] 设计文档评审通过
- [ ] buglist 记录与新文档链接对齐

---

## 阶段 1：帧元信息

### 1.1 记录帧大小与对齐

- [ ] 在 `src/codegen/c99/function.uya` 中为每个 async 函数记录 `frame_size` / `frame_align`
- [ ] 把 `await` 绑定、跨 await locals、参数字段计入最终帧布局
- [ ] 让 `frame_size` 可在生成 C 前被查询
- [ ] 为 `@frame(foo)` 生成稳定可解析的类型入口（避免外部依赖生成后的 C 符号名）
- [ ] 为泛型 async 生成实例级 frame key / alias（按 concrete type args 区分）
- [ ] 把 `is_pinned` / `contains_pinned_field` / `frame_key` 传给 checker 侧元信息
- [ ] 给 `frame_key` 绑定定义点与实例化点，便于 note 精确定位

### 1.2 记录逃逸分类

- [ ] 增加 `escape_class` 枚举
- [ ] 至少区分：
  - `StackCandidate`
  - `InlineCandidate`
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

- [ ] 定义 `AsyncFrameFieldMeta`
- [ ] 定义 `AsyncFrameMeta`
- [ ] 在 `TypeChecker` 中新增 `async_frame_metas` / `async_frame_meta_count`
- [ ] 让 `frame_key`、`decl_node`、`instance_node`、`field meta` 都可被 checker 访问
- [ ] 给 `frame_key` 提供从 `MonoInstance` 推导的 concrete instance key
- [ ] 保证 frame 元数据与 `mono_instances` 使用一致的单态化入口

相关文件：
- [ ] `src/codegen/c99/function.uya`
- [ ] `src/codegen/c99/internal.uya`

---

## 阶段 2：运行时帧池

### 2.1 新建帧池模块

- [ ] 新增 `lib/std/async_frame.uya`
- [ ] 定义 `AsyncFramePool`
- [ ] 定义 `async_frame_pool_init`
- [ ] 定义 `async_frame_pool_alloc(pool, size, align)`
- [ ] 定义 `async_frame_pool_free(pool, ptr, size, align)`
- [ ] 定义 `async_frame_pool_reset`

### 2.2 选择池策略

- [ ] 先做固定容量 free list
- [ ] 可选按线程切分
- [ ] 可选按 scheduler / event loop 切分
- [ ] 预留统计字段：alloc 次数、free 次数、pool 满次数

### 2.3 调试开关

- [ ] 增加 `ASYNC_FRAME_DEBUG_HEAP`
- [ ] 增加 `ASYNC_FRAME_POOL_CAP`
- [ ] 增加 `ASYNC_FRAME_STACK_LIMIT`

说明：
- 热路径目标不是“更快的 heap”
- 热路径目标是“可回收、可预测、可去碎片化”

---

## 阶段 3：代码生成改造

### 3.1 拆出帧初始化入口

- [ ] 为 async 函数生成 `*_frame_init`
- [ ] 为 async 函数生成 `*_poll`
- [ ] 让 `*_future_new` 只负责把帧放到正确位置
- [ ] 让 `@frame(foo)` 可用于普通变量、结构体字段与池中的显式声明

### 3.2 栈优先路径

- [ ] 对直接 `@await foo()` 的路径使用 caller-owned frame
- [ ] 对 `block_on(foo())` 的路径使用局部 frame
- [ ] 对父子 async 嵌套，优先把 child frame 放进 parent frame 字段

### 3.3 池兜底路径

- [ ] 逃逸 future 走 pool 分配
- [ ] `poll == Ready/Error` 时统一归还 pool
- [ ] `close / cancel / early return` 都走同一条释放函数

### 3.4 清掉热路径 heap

- [ ] 移除 `src/codegen/c99/function.uya` 中 async frame 的默认 `malloc`
- [ ] 移除 `free` 作为默认释放
- [ ] 保留仅调试可见的 heap fallback

相关文件：
- [ ] `src/codegen/c99/function.uya`
- [ ] `src/codegen/c99/stmt.uya`
- [ ] `src/codegen/c99/expr.uya`

---

## 阶段 4：语义与安全

### 4.1 逃逸分析

- [ ] 检查 `return foo()`
- [ ] 检查 future 写入结构体 / 数组 / 全局
- [ ] 检查 future 传入未知边界
- [ ] 检查 future 被接口类型承接后的生命周期
- [ ] 检查 frame 按值赋值 / 按值传参 / return / 数组元素赋值 / 字段初始化时的 pinned 违规
- [ ] 检查父结构体含 pinned frame 字段时的整体移动和按值传参
- [ ] 检查 `@frame(foo<T>)` 未 concrete 时的实例化错误
- [ ] 将以上检查分别接到 `src/checker/check_stmt.uya`、`src/checker/check_call.uya`、`src/checker/check_expr.uya`、`src/checker/check_expr_extra.uya`
- [ ] 复用现有 `checker_mark_moved` / `checker_report_error_moved` 风格，但扩展为 pinned frame 专用诊断
- [ ] 增加 `checker_type_owns_async_frame`
- [ ] 增加 `checker_type_refs_async_frame`
- [ ] 增加 `checker_expr_owns_async_frame`
- [ ] 增加 `checker_type_contains_pinned_field`
- [ ] 增加 `checker_frame_key_for_mono_instance`
- [ ] 增加 `checker_async_frame_meta_for_fn`

### 4.2 释放与取消

- [ ] 保证 Ready 路径释放帧
- [ ] 保证 Error 路径释放帧
- [ ] 保证 abort / cancel / early return 路径释放帧
- [ ] 保证 child future 比 parent 先释放

### 4.3 失败处理

- [ ] pool 满时返回明确错误或切换调试策略
- [ ] 绝不静默悬挂
- [ ] 绝不双重释放

### 4.4 诊断 helper

- [ ] 增加 `checker_report_error_with_note`
- [ ] 增加 `checker_report_error_with_notes`
- [ ] 增加 `checker_report_frame_move_error`
- [ ] 增加 `checker_report_frame_field_move_error`
- [ ] 增加 `checker_report_frame_align_error`
- [ ] 增加 `checker_report_frame_monomorphization_error`
- [ ] 让 note 输出保持与现有错误格式兼容
- [ ] 让 note 中至少包含定义点或实例化点
- [ ] 让 note 中至少包含修改建议

---

## 阶段 5：测试矩阵

### 5.1 编译输出检查

- [ ] 对 `benchmarks/http_bench_async_epoll_await_simple.uya` 的生成 C 做 `rg malloc` 检查
- [ ] 确认热路径没有 `malloc(sizeof(struct uya_async_...))`
- [ ] 确认仍保留必要的 `pool_alloc` / `stack` 逻辑
- [ ] 确认 `@frame(foo)` 生成的类型对齐与 frame layout 一致

### 5.2 语义测试

- [ ] 直接 `@await` 的小样本通过
- [ ] `return foo()` 的逃逸样本通过
- [ ] future 存入 struct / array 的样本通过
- [ ] 嵌套 async 互相 `await` 的样本通过
- [ ] `@frame(foo)` 在 `var` / `struct` / pool API 三种持有方式下都能通过
- [ ] `@frame(foo)` 在父结构体字段里的 in-place 初始化路径能通过
- [ ] 带 `@frame(foo)` 字段的父结构体移动/赋值被正确拒绝
- [ ] `Worker{ req: other_frame }` 这种按值搬入 frame 字段的写法被正确拒绝
- [ ] 泛型 async 的 frame 单态实例区分正确，不同 type args 不混 layout
- [ ] `@frame(foo<Concrete>)` 正例通过，未解析的 `@frame(foo<T>)` 负例报错
- [ ] 对齐更高的 frame 在 pool 中分配后不出现未对齐访问
- [ ] pool API 负例覆盖：只传 `size` 或传错 `align` 时能得到明确报错
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

- [ ] `curl -v http://localhost:8876/` 不挂起
- [ ] `ab -n 1000000 -c 500 -k http://localhost:8876/` 不 reset
- [ ] `wrk` / `ab` 下 RSS 维持平稳

建议新增测试：
- [ ] `tests/test_async_frame_stack_ok.uya`
- [ ] `tests/test_async_frame_escape_pool.uya`
- [ ] `tests/test_async_frame_nested_await.uya`
- [ ] `tests/test_async_frame_release_path.uya`

---

## 阶段 6：收口与默认切换

- [ ] 默认开启 stack / pool 路径
- [ ] 默认关闭 heap fallback
- [ ] 保留一个显式 debug 开关，便于定位生命周期问题
- [ ] 清理已经不再需要的临时 workaround
- [ ] 更新 `docs/std_async_design.md`、`docs/async_production_todo.md`、`buglist.md`

---

## 风险提醒

- `Future<T>` 是接口形态，不能对所有场景承诺“绝对纯栈”
- 逃逸分析宁可保守一点，先保正确性再扩覆盖
- pool 大小需要压测调参，不能拍脑袋定死
- 如果后续要做“接口值内联存储”，那会是下一阶段 ABI 改造，不应混在本阶段里

---

## 任务顺序建议

1. 先做帧元信息与逃逸分类
2. 再补 frame pool
3. 然后改 codegen 热路径
4. 最后做测试和默认开关切换
