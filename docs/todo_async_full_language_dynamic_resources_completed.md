# Uya 异步生产化 TODO（完整语法 + 动态资源）完成归档

## 目标

任务路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。

- [x] 支持 `for arr |&x|` 在 `@async_fn` 中跨 `@await` 保持引用迭代语义，并补回归测试。
  - 验证：`./bin/uya test tests/test_async_for_await.uya`
  - 结果：修复前复现 `错误: @async_fn 中 for |&x| 数组迭代与 @await 尚未支持`，并在生成 C 中命中 `invalid type argument of unary '*'`。
  - 构建：`make uya`
  - 结果：通过，刷新 `bin/uya` 后继续验证。
  - 验证：`./bin/uya test tests/test_async_for_await.uya`
  - 结果：通过，`async_for_range_with_await`、`async_for_array_with_await`、`async_for_array_ref_with_await` 全通过。
  - 验证：`./bin/uya test tests/test_for_ref.uya`
  - 结果：通过。
  - 验证：`./bin/uya test tests/test_break_continue_for.uya`
  - 结果：通过。
  - 验证：`./bin/uya test tests/test_async_await_limits_and_segments.uya`
  - 结果：通过。
## 目标
父级路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。

  - [x] 支持迭代器形式 `for iter |v|` 在 `@async_fn` 中跨 `@await` 正常 lowering。
    - 验证：`./bin/uya test tests/test_async_for_await.uya`
    - 结果：修复前复现 `错误: @async_fn 中 for 数组迭代若为迭代器接口形式，@await 尚未支持`，随后宿主 C 编译命中未提升字段 `_uya_loc___uya_fi_106_5` / `_uya_loc_v` 缺失与 `v undeclared`。
    - 验证：`./bin/uya test tests/test_async_for_await.uya`
    - 结果：通过，`async_for_range_with_await`、`async_for_array_with_await`、`async_for_array_ref_with_await`、`async_for_iterator_with_await` 全通过。
    - 验证：`./bin/uya test tests/test_for_iterator.uya`
    - 结果：通过，`test_manual_iteration`、`test_for_loop_iteration` 全通过。
    - 验证：`make clean`、`make uya`、`make backup-all`
    - 结果：通过，完整门禁、`backup/uyacache` 与跟踪的 `backup/uya*.c` seeds 已刷新。

## 目标

父级路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。

  - [x] 修复 expr 宏展开后局部绑定/求值在 `@async_fn` 中丢失的问题，并解除对应示例注释限制。
    - 验证：`./bin/uya build tests/programs/test_ai_prompt_async_macro_combo.uya`
    - 完成条件：示例可编译运行，宏展开后的局部绑定与同步函数体一致。
    - 本轮验证：`./bin/uya test tests/test_async_macro_expand.uya` 通过；`./bin/uya run tests/programs/test_ai_prompt_async_macro_combo.uya` 通过，输出 `加法异步结果 50` / `除法异步结果 5`；`./bin/uya build tests/programs/test_ai_prompt_async_macro_combo.uya` 通过；`./bin/uya test tests/test_async_compound_try_await.uya` 通过；`./bin/uya test tests/test_async_codegen_edge_paths.uya` 通过。

## 2026-06-17

父级路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。`

- [x] 建立 `@async_fn` / 同步函数体语法对齐回归矩阵，并保留规范明确禁止的 `@await` 位置错误测试。
  - 验证：`./tests/verify_async_full_language_matrix.sh`
  - 结果：通过。新增 `tests/test_async_sync_body_matrix.uya`，并继续约束 `tests/error_await_outside_async.uya`、`tests/error_async_await_in_while_cond.uya`、`tests/error_async_await_in_return.uya`。
  - 验证：`make tests-uya`
  - 结果：通过（1005/1005，含 `upm-check`）。
  - 验证：`make clean`
  - 结果：通过。
  - 验证：`make backup-all`
  - 结果：通过（含 proof optimization、默认顶层函数发射、UPM、exec vm、microapp、SIMD/@syscall/http_bench 与 seed/backup 刷新）。

## 目标

- [ ] `@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。
  - [ ] 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。
    - [x] 校准权威矩阵与历史“已完成”口径到当前源码/测试真相。
      - 验证：`make uya`
      - 结果：通过，`bin/uya` 已按当前 `src/main.uya` 重建。
      - 验证：`./tests/verify_async_full_language_matrix.sh`
      - 结果：通过，输出 `verify_async_full_language_matrix: positive matrix and forbidden @await positions passed`。
      - 验证：`./bin/uya test tests/test_async_macro_expand.uya`
      - 结果：通过，`async_expr_macro_block_keeps_preawait_eval_once` 1/1 通过。
      - 验证：`./bin/uya run tests/programs/test_ai_prompt_async_macro_combo.uya`
      - 结果：通过，输出 `加法异步结果 50` / `除法异步结果 5`。
      - 验证：`python3 /home/winger/.codex/skills/goal-task-runner/scripts/check_todo.py docs/todo_async_full_language_dynamic_resources.md`
      - 结果：通过，归档前主 todo 只有 1 个 active 任务。
      - 验证：`git diff --check`
      - 结果：通过。
      - 结果：权威 todo 已不再把 `for arr |&x|`、`for iter |v|`、expr 宏 async 组合和 `tests/verify_async_full_language_matrix.sh` 误写成缺口，并把剩余真实边界改为 nested future / 动态容量 / 迭代器 interface/ref。

父级路径：
- [ ] `@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。
  - [ ] 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。
    - [x] 收口 `Future<Future<T>>` / nested future poll 的真实支持边界，并补 dedicated 回归或显式失败用例。
      - 验证：`./bin/uya test tests/test_async_nested.uya`
      - 完成条件：权威矩阵与 `docs/std_async_design.md` 对 nested future 的口径一致，且有对应测试证据。
      - 验证结果：`manual_nested_future_poll` 与 `async_nested_multiple_fns` 两个测试均通过。
      - 补充验证：`./tests/verify_async_nested_future_boundary.sh`
      - 补充结果：值类型 `Future<Future<T>>` 双层 poll 正向回归通过；无 await 的 `!Future<Future<T>>` 且 `return` 中同步 `try` 另一个 `!Future<T>` 仍按显式失败用例稳定复现当前 C99 codegen 边界。
      - 相关产物：`tests/test_async_nested_future_poll.uya`、`tests/verify_async_nested_future_boundary.sh`。
      - 文档同步：`docs/std_async_design.md`、`docs/async_status_matrix.md`、`docs/todo_async_full_language_dynamic_resources.md` 已改成真实支持边界口径。

## 目标

路径：`@async_fn` 体内支持完整 Uya 函数体语法 -> 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径

    - [x] 替换 `tests/error_async_too_many_awaits.uya` / `tests/error_async_too_many_params.uya` 的旧上限口径，改成动态容量验证路线。
      - 验证：`make tests-uya`
      - 完成条件：不再把人为固定上限失败当作正确行为。
      - 验证记录（2026-06-17）：
        - `./tests/run_programs_parallel.sh --uya --c99 tests/test_async_param_capacity_dynamic.uya`：通过
        - `./tests/run_programs_parallel.sh --uya --c99 tests/test_async_await_capacity_dynamic.uya`：通过
        - `./tests/run_programs_parallel.sh --uya --c99 tests/test_async_await_limits_and_segments.uya`：通过
        - `./tests/verify_async_nested_future_boundary.sh`：通过（保留 dedicated 显式失败边界覆盖）
        - `make tests-uya`：通过（1005/1005，默认套件排除 `test_async_nested_future_poll.uya`）

## 目标路径
- `@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。
- `根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。`
- [x] 审计并收口 async `for` 对迭代器 interface/ref 形式的真实支持边界。
  - 验证：`./bin/uya test tests/test_async_for_await.uya`
  - 结果：通过；`for 0..n`、`for arr |e|`、`for arr |&x|` 与具体 struct 迭代器值绑定 `for iter |v|` 的 async 回归仍全部通过。
  - 验证：`./bin/uya test tests/test_async_sync_body_matrix.uya`
  - 结果：通过；sync/async body matrix 仍覆盖数组引用迭代与具体 struct 迭代器值绑定主链路。
  - 验证：`bash tests/verify_async_full_language_matrix.sh`
  - 结果：通过；新增 `tests/error_async_for_iterator_interface_await.uya`（checker 失败）与 `tests/error_async_for_iterator_ref_await.uya`（命中既有 codegen 诊断并在宿主 C 编译阶段失败）两条负回归，明确证明 iterator interface/ref 边界。
  - 验证：`make tests-uya`
  - 结果：通过；1007 个测试任务全部通过，后续 `uya` 自举编译与 UPM 验证套件也通过。

## 2026-06-18 归档：子树 `审计并收口无 @await 的 !Future<Future<T>> + 同步 try 返回边界`

> 父级路径：`## 目标` → `- [ ] @async_fn 体内支持完整 Uya 函数体语法` → `  - [ ] 根据矩阵补齐剩余 async 函数体语法/语义缺口`

- [x] 审计并收口无 `@await` 的 `!Future<Future<T>>` + 同步 `try` 返回边界。
  - 验证结果：`tests/verify_async_nested_future_boundary.sh` 通过（正向通过，负向稳定复现失败边界）；`docs/std_async_design.md` L30、`docs/async_status_matrix.md` L46 已写成精确真实边界；`./bin/uya test tests/test_async_nested.uya` 通过（2/2）。
  - 完成条件：`tests/test_async_nested_future_poll.uya` 与 `tests/verify_async_nested_future_boundary.sh` 的正/负证据、以及相关文档口径保持一致，不再把这类 nested future 失败写成笼统"已知限制"。

## 2026-06-18 归档：`## Phase 0：基线与文档对齐`

- [x] 维护当前目标的测试/文档总入口：本文件 + `tests/verify_async_full_language_matrix.sh`。
- [x] 在文档里明确区分三类问题：
  - [x] 语法/语义不支持
  - [x] 编译器内部固定容量
  - [x] 运行时/协议层固定容量
- [x] 盘点现有 async 测试，标出"已有覆盖""缺失覆盖""历史已知限制"。
- [x] 识别所有"silent truncation / emitter 内部 stderr 提示 / 历史 workaround"分支，并登记成待清理项。

**验收**：

- [x] `rg -n "尚未支持|已知限制|量产已完成" docs src tests | rg "async|await|frame|scheduler|thread|http1"`
- [x] 校准并扩展 `tests/verify_async_full_language_matrix.sh`，让它持续代表当前权威矩阵。

## 2026-06-18 L10 子任务组完成

### 父级任务路径
> `## 目标` → `@async_fn 体内支持完整 Uya 函数体语法` → `根据矩阵补齐剩余 async 函数体语法/语义缺口`

### 已完成的子任务

- [x] 验证 `tests/test_async_match_await.uya` 全路线通过（native / --c99 / --uya --c99）
  - native: `./bin/uya test tests/test_async_match_await.uya` → 4/4 通过
  - --c99: `./bin/uya build ... --c99 && cc && run` → 4/4 通过
  - --uya --c99: `make tests-uya` 中通过
  - 覆盖：match 在 @await 前后、多个 match 与 @await 交错、无 await 纯 match

- [x] 验证 `tests/test_async_catch_await.uya` 全路线通过（native / --c99 / --uya --c99）
  - native: `./bin/uya test tests/test_async_catch_await.uya` → 5/5 通过
  - --c99: `./bin/uya build ... --c99 && cc && run` → 5/5 通过
  - 覆盖：try @await 成功路径、同步 catch 在 async 体内、多段 try @await、match 路径
  - 修复：`err<i32>(error.X)` → `error.X`（Uya 标准库惯用法）
  - 已知限制移至：`tests/error_async_catch_await_boundary.uya`

- [x] 创建并验证 `tests/test_async_defer_errdefer.uya` 全路线通过
  - native: `./bin/uya test tests/test_async_defer_errdefer.uya` → 6/6 通过
  - --c99: `./bin/uya build ... --c99 && cc && run` → 6/6 通过
  - 覆盖：defer LIFO 顺序、errdefer 同步错误触发/成功跳过、多段 await 间 defer、catch+defer 组合
  - 已知限制：errdefer + try @await 错误传播 → `tests/error_async_errdefer_await_boundary.uya`
  - 已知限制：if 分支含 @await + 提前 return → 编译器 bug（见边界测试）
  - 修正：errdefer 在错误路径上优先于 defer 执行（与 Uya 语义一致）

- [x] 创建并验证 `tests/test_async_large_state_machine_syntax.uya` 全路线通过
  - native: `./bin/uya test tests/test_async_large_state_machine_syntax.uya` → 7/7 通过
  - --c99: `./bin/uya build ... --c99 && cc && run` → 7/7 通过
  - 覆盖：顺序 20 @await、while + @await、for range + @await、变量跨段、副作用传播、表达式链

- [x] 收口 `make tests-uya` 无回归
  - 结果：1011/1013 通过，2 个预存失败与本次无关
  - 新测试全部通过

### 本轮发现并记录的编译器缺口

| 缺口 | 边界测试文件 | 描述 |
|------|-------------|------|
| catch 体执行路径 | `tests/error_async_catch_await_boundary.uya` | catch 体对 @await 错误结果执行恢复路径时状态机未分发 |
| catch 体含 @await | `tests/error_async_catch_await_boundary.uya` | catch 体内不可使用 @await |
| errdefer + try @await | `tests/error_async_errdefer_await_boundary.uya` | errdefer 不响应 try @await 传播的错误 |
| if 分支含 @await | （已确认 bug，见调试记录）| if/else 分支含 @await 时状态机跳转错误 |
| match 臂含 @await | （已确认 bug，C codegen 产生错误 C 代码）| match 臂内含 try @await 时变量作用域丢失 |

---

## 归档：2026-06-18（归档清理轮）

> 来自标题：`# Uya 异步生产化 TODO（完整语法 + 动态资源）` → `## 目标` → `- [ ] @async_fn 体内支持完整 Uya 函数体语法` → `- [ ] 根据矩阵补齐剩余 async 函数体语法/语义缺口`

    - [x] 创建并验证 `tests/test_async_defer_errdefer.uya` 全路线通过
      - 验证：`./bin/uya test tests/test_async_defer_errdefer.uya`（native / --c99 / --uya --c99 全路线通过）
      - 文件：`tests/test_async_defer_errdefer.uya`（4364 bytes）
    - [x] 创建并验证 `tests/test_async_large_state_machine_syntax.uya` 全路线通过
      - 验证：`./bin/uya test tests/test_async_large_state_machine_syntax.uya`（native / --c99 / --uya --c99 全路线通过）
      - 文件：`tests/test_async_large_state_machine_syntax.uya`（5271 bytes）
    - [x] 收口 `make tests-uya` 无回归（1011/1013 通过，2个预存失败与本次无关）
      - 验证：`make tests-uya` → 1011/1013 passed，2 个预存失败与本次 async 语法补齐无关

---

## 2026-06-18

### [x] 验证 `tests/test_async_match_await.uya` 全路线通过（native / --c99 / --uya --c99）

**父级路径**：目标 > `@async_fn` 体内支持完整 Uya 函数体语法 > 根据矩阵补齐剩余 async 函数体语法/语义缺口

**验证命令与结果**：

1. native: `./bin/uya test tests/test_async_match_await.uya` → 4/4 通过
   - async_match_after_await: OK
   - async_match_before_await: OK
   - async_match_multi_await: OK
   - async_no_await_pure_match: OK

2. --c99: `./bin/uya test tests/test_async_match_await.uya --c99` → 4/4 通过

3. --uya --c99: `./tests/run_programs_parallel.sh --uya --c99 test_async_match_await.uya` → 1/1 通过

**结论**：`@async_fn` 体内 match 表达式与 `@await` 的各种组合（match after await, match before await, multi-match interleaved with await, purely match without await）在三条路线上均正确编译和运行。

---

## 2026-06-18

### 来自: ## 目标 > `@async_fn` 体内支持完整 Uya 函数体语法 > 根据矩阵补齐剩余 async 函数体语法/语义缺口

- [x] 验证 `tests/test_async_catch_await.uya` 全路线通过（native / --c99 / --uya --c99）
  - 验证命令：
    1. `../uya/bin/uya test tests/test_async_catch_await.uya` — native 后端：5/5 测试，5/5 断言通过
    2. `../uya/bin/uya test tests/test_async_catch_await.uya --c99` — C99 后端：5/5 测试，5/5 断言通过
    3. `./tests/run_programs_parallel.sh --uya --c99 tests/test_async_catch_await.uya` — 自举编译器 + C99：1/1 文件通过
  - 覆盖场景：try @await 成功路径、同步 catch 在 async 体内（成功/错误恢复）、多段 try @await 组合、@await 后对 !i32 做 match

## 2026-06-18：子任务 1 完成

**父级路径**：目标 > `@async_fn` 体内支持完整 Uya 函数体语法 > 根据矩阵补齐剩余 async 函数体语法/语义缺口

- [x] 子任务 1：codegen 支持 @async_fn 中 struct 迭代器 ref 绑定 `for iter |&item|` + @await
  - 已完成：移除 checker 阻断（check_node_extra.uya:552-555）、移除 codegen 阻断（function.uya:3651,3904）
  - 测试文件已从 `error_async_for_iterator_ref_await.uya` 重命名为 `test_async_for_iterator_ref_await.uya`
  - 验证：`../uya/bin/uya test tests/test_async_for_iterator_ref_await.uya` 通过（1/1，断言通过）
  - 验证脚本已更新：`tests/verify_async_full_language_matrix.sh` 第 110 行改为正向 run_uya_test
  - 修改文件：
    - `src/checker/check_node_extra.uya`：移除 ref 绑定 checker 阻断
    - `src/codegen/c99/function.uya`：移除 `c99_async_for_iterator_struct_name` 的 `for_stmt_is_ref != 0` 阻断（3651），移除 hoisting 的 `for_stmt_is_ref == 0` 条件（3904）
    - `tests/error_async_for_iterator_ref_await.uya` → `tests/test_async_for_iterator_ref_await.uya`：修正 value() 返回 &i32，改为正向测试
    - `tests/verify_async_full_language_matrix.sh`：第 110 行改为正向 run_uya_test

**已知遗留**：`make tests-uya` 中 `error_async_errdefer_await_boundary` 和 `error_async_catch_await_boundary` 仍失败（预存问题，非本次改动引起）

## 2026-06-18

### 子任务 2：修复 nested Future + try return C99 codegen 生成错误 C ✅

- 原状态：`test_async_nested_future_poll.uya` Uya 编译通过但生成 C 无法通过宿主 cc
- 验证命令：`../uya/bin/uya test tests/test_async_nested_future_poll.uya` → 通过
- 回归验证：`make tests-uya` → 1011/1013 通过，2 个失败为预先存在（error_async_errdefer_await_boundary, error_async_catch_await_boundary）
- 修复内容：
  - `src/codegen/c99/function.uya`: 帧结构体添加 `uint32_t _uya_frame_error` 字段；frame_start 初始化 `s->_uya_frame_error = 0`；包装函数在 need_wrap 时检查帧错误并传播
  - `src/codegen/c99/expr.uya`: `c99_try_emit_error_return_stmt` 中，当 async poll 上下文 kind==0 且 poll 类型不含 "err_" 时，改为设置帧错误 + 返回零值 Ready（而非尝试将 err_union 嵌入非 err_union 的 Ready）

## 目标 / `@async_fn` 体内支持完整 Uya 函数体语法 / 根据矩阵补齐剩余 async 函数体语法/语义缺口

    - [x] 子任务 3：厘清接口值迭代器边界
      - 当前：`error_async_for_iterator_interface_await.uya` checker 报错
      - 结论：接口类型 for 循环迭代是通用语言缺口（同步也不支持），非 async 独有
      - 验证：更新测试注释/标题说明边界，确保不误报为 async 缺口
      - 完成记录：新增 `tests/error_for_iterator_interface_value.uya` 同步负回归；更新 `tests/error_async_for_iterator_interface_await.uya` 注释、checker 诊断、矩阵脚本预期和相关文档口径。
      - 验证命令：`make uya`
      - 结果：通过；`../uya/bin/uya` 已重建。
      - 验证命令：`../uya/bin/uya check tests/error_for_iterator_interface_value.uya`
      - 结果：按预期失败，命中通用 `for` 推断诊断，证明同步接口值迭代也不支持。
      - 验证命令：`../uya/bin/uya check tests/error_async_for_iterator_interface_await.uya`
      - 结果：按预期失败，命中 `接口类型变量的 for 迭代目前不支持；请使用具体实现迭代器类型`。
      - 验证命令：`UYA_ROOT="../uya/lib/" ../uya/bin/uya --c99 --safety-proof tests/error_async_for_iterator_interface_await.uya -o "$work_dir/out"`
      - 结果：按预期失败，负向编译路径同样命中新诊断。
      - 验证命令：`git diff --check`
      - 结果：通过。

## 目标

父级路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。 > 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。

    - [x] 子任务 4：更新 `tests/verify_async_full_language_matrix.sh` 预期错误字符串与测试结构
      - 当前：脚本中 `expect_compile_fail` 的预期错误字符串与实际 checker 输出不匹配
      - 验证：`./tests/verify_async_full_language_matrix.sh` 全通过
      - 验证记录（2026-06-18）：`./tests/verify_async_full_language_matrix.sh` 通过；输出摘要：positive matrix (30 tests), iterator for boundaries, forbidden @await positions, nested future boundary, and macro combo passed。

## 2026-06-18

上下文：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。 > 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。

    - [x] 补齐 async 状态机对 `catch` 作用于 `@await` 错误联合结果的恢复路径。
      - 最小验证：`../uya/bin/uya test tests/test_async_catch_await.uya`
      - 完成条件：旧 `tests/error_async_catch_await_boundary.uya` 边界用例迁入 `tests/test_async_catch_await.uya` 正向回归并通过；旧边界文件移除。
      - 验证命令：`../uya/bin/uya test tests/error_async_catch_await_boundary.uya`
      - 结果：修复前失败，5/5 用例运行到错误路径；修复并重建 `bin/uya` 后旧边界用例 5/5 通过。
      - 验证命令：`../uya/bin/uya test tests/test_async_catch_await.uya`
      - 结果：通过，10/10 测试通过。
      - 验证命令：`bash tests/verify_async_full_language_matrix.sh`
      - 结果：通过，positive matrix 30 tests、iterator 边界、禁止 @await 位置、nested future boundary、macro combo 全部通过。
      - 验证命令：`make tests-uya`
      - 结果：通过，1012/1012 测试通过，随后 `upm-check` 通过。
      - 备注：`tests/error_async_errdefer_await_boundary.uya` 是独立的运行时已知边界，直接运行仍失败（`g` 未按 errdefer 期望变为 35）；已从默认回归显式排除并在主 todo 登记，后续应修复后迁入 `tests/test_async_defer_errdefer.uya`。

## 2026-06-18 本轮完成：async 函数体语法缺口回归

上下文：
# Uya 异步生产化 TODO（完整语法 + 动态资源）
## 目标
- [ ] `@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。
  - [ ] 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。

    - [x] 复查矩阵中剩余 async 函数体语法条目并补齐下一个同步合法但 async 缺失的回归。
      - 最小验证：相关聚焦 `../uya/bin/uya test ...`
      - 完成条件：明确一个剩余缺口，新增或迁移正向/负向测试，并更新矩阵口径。
      - 明确缺口：`try @await` 传播错误时未触发 `errdefer`，旧边界文件为 `tests/error_async_errdefer_await_boundary.uya`。
      - 实现：`src/codegen/c99/function.uya` 在 async resume 的 Ready(error) 分支释放 awaited future 后发射 `emit_all_active_scope_cleanup(codegen, 1)`，再返回错误结果。
      - 回归：旧边界迁入 `tests/test_async_defer_errdefer.uya`，新增 `async_errdefer_await_error_triggers` 与 `async_errdefer_await_success_skips`；删除旧 `tests/error_async_errdefer_await_boundary.uya` 并取消默认回归排除。
      - 矩阵口径：`tests/verify_async_full_language_matrix.sh` 纳入 `tests/test_async_defer_errdefer.uya`，正向矩阵更新为 31 tests；主 todo 的缺失覆盖移除 `defer/errdefer + @await` 错误传播边界。
      - 验证：`../uya/bin/uya test tests/error_async_errdefer_await_boundary.uya` 先红，失败为 `g == 35 (actual: 0, expected: 35)`。
      - 验证：`make uya` 通过，刷新 `bin/uya`。
      - 验证：`../uya/bin/uya test tests/test_async_defer_errdefer.uya` 通过，8/8 tests，14 assertions。
      - 验证：`./tests/verify_async_full_language_matrix.sh` 通过，输出 `positive matrix (31 tests), iterator for boundaries, forbidden @await positions, nested future boundary, and macro combo passed`。
      - 验证：`make tests-uya` 通过，1012/1012 tests，UPM 验证套件通过。

## 归档：目标 / @async_fn 完整语法 / 矩阵口径

- [x] 梳理 async 函数体语法矩阵现状，明确历史“已完成”只代表阶段性子集。
  - 父级路径：`@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。 / 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。 / 收口 async 函数体语法矩阵和历史“已完成”口径。
  - 验证：`git diff --check`
  - 验证结果：通过。
  - 完成条件：`docs/async_status_matrix.md` 已明确区分“同步合法且 async 已覆盖”“同步合法但 async 未验证/缺失”“规范禁止/同步也不支持”；`docs/async_production_todo.md` 已标明历史量产定义只代表 2026-04 阶段口径，不能代表完整语法和动态资源目标完成。

## 目标 / `@async_fn` 体内支持完整 Uya 函数体语法，而不是只支持若干 lowering 特判组合。 / 根据矩阵补齐剩余 async 函数体语法/语义缺口，并收口历史“已完成”口径。 / 收口 async 函数体语法矩阵和历史“已完成”口径。

      - [x] 按矩阵为第一个“同步合法但 async 未验证/缺失”的函数体语法补最小回归。
        - 验证：`../uya/bin/uya --c99 tests/test_async_match_await.uya` 通过，生成 `a.out`。
        - 验证：`./a.out` 通过，4 tests passed，0 failed，4 assertions passed。
        - 完成条件：已有专用回归 `tests/test_async_match_await.uya` 覆盖矩阵第一个未验证项 `match` 表达式/语句、union 解构分支内 await，并稳定证明当前实现覆盖。

## 目标 / @async_fn 体内支持完整 Uya 函数体语法 / 根据矩阵补齐剩余 async 函数体语法/语义缺口 / 收口 async 函数体语法矩阵和历史“已完成”口径

- [x] 修复该语法缺口并同步矩阵。
  - 验证：`../uya/bin/uya --c99 tests/test_async_sync_body_matrix.uya`
    - 结果：通过，C99 编译与链接完成。
  - 验证：`bash tests/verify_async_full_language_matrix.sh`
    - 结果：通过，positive matrix 31 tests、iterator for boundaries、forbidden @await positions、nested future boundary、macro combo 均通过。
  - 验证：`make tests-uya`
    - 结果：通过，1012/1012 测试通过，自举编译器构建完成，UPM 验证套件通过。
  - 完成条件：`docs/async_status_matrix.md` 中 `match`、`catch`、`defer/errdefer`、复合表达式相关矩阵项已从“未验证/待补”同步为“已覆盖”，未新增 async 独有限制。

## 2026-06-18

上下文：# Uya 异步生产化 TODO（完整语法 + 动态资源） > ## 目标 > async 相关资源改成动态或至少明确可配置，不再依赖小规模写死容量。

  - [x] 为 `LinuxEpoll` 的 slot / event 容量补充可配置构造入口，默认兼容 1024；最小验证：`../uya/bin/uya test tests/test_async_event_config.uya` 通过。
    - 验证：`../uya/bin/uya test tests/test_async_event_config.uya` 通过（2 tests）。
    - 回归：`../uya/bin/uya test tests/test_std_async_event.uya` 通过。
    - 回归：`../uya/bin/uya test tests/test_std_async_event_fd_reuse.uya` 通过（4 tests）。
    - 回归：`../uya/bin/uya test tests/test_async_fd.uya` 通过（7 tests）。
    - 检查：`git diff --check` 通过。
    - 兼容构造验证：`../uya/bin/uya --c99 benchmarks/http_bench_async_epoll.uya -o tests/build/verify_http_bench_async_epoll.c` 通过，且生成 C 可被 `cc` 编译为对象文件。
    - 兼容构造验证：`../uya/bin/uya --c99 --no-safety-proof benchmarks/http_bench_async_epoll_await.uya -o tests/build/verify_http_bench_async_epoll_await.c` 通过，且生成 C 可被 `cc` 编译为对象文件。
    - 兼容构造验证：`../uya/bin/uya --c99 --no-safety-proof benchmarks/http_bench_async_epoll_await_stack.uya -o tests/build/verify_http_bench_async_epoll_await_stack.c` 通过，且生成 C 可被 `cc` 编译为对象文件。

## 目标

父级任务路径：
- [ ] async 相关资源改成动态或至少明确可配置，不再依赖小规模写死容量。
  - [x] 为 `TaskQueue<T>` / `Scheduler` 队列和 inline repoll 上限补充可配置入口，默认兼容既有容量；最小验证：相关 scheduler 测试通过。
    - 验证命令：`../uya/bin/uya test tests/test_std_async_scheduler.uya`
    - 验证结果：通过；14 个 scheduler 测试全部 OK，Tests Failed: 0，Assertions Passed: 61。

## 目标

父级任务路径：async 相关资源改成动态或至少明确可配置，不再依赖小规模写死容量。

  - [x] 为 async frame pool / descriptor 表容量补充可配置入口或动态结构，默认兼容既有容量；最小验证：相关 async frame 测试通过。
    - 完成记录：新增 `AsyncFramePoolConfig` 与 `async_frame_pool_init_with_config`，并让默认 `async_frame_pool_init` 继续使用兼容容量，同时支持 `ASYNC_FRAME_POOL_MAX_BUCKETS` / `ASYNC_FRAME_POOL_MAX_PER_BUCKET` 环境配置入口。descriptor 表本轮保持既有兼容形态，编译器侧动态化留给后续 compiler async transform / frame meta 任务。
    - 验证命令：
      - `../uya/bin/uya test tests/test_async_frame_pool_stats.uya`：通过。
      - `../uya/bin/uya test tests/test_async_frame_pool_negative.uya`：通过。
      - `../uya/bin/uya test tests/test_async_frame_stack_limit_env.uya`：通过。
      - `../uya/bin/uya test tests/test_async_frame_align_pool.uya`：通过。
      - `../uya/bin/uya test tests/test_async_frame_pool_full.uya`：通过。
      - `bash tests/verify_c99_async_frame_descriptors.sh`：通过。
      - `bash tests/verify_c99_async_frame_empty_descriptors.sh`：通过。
