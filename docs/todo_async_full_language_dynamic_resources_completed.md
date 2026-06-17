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
