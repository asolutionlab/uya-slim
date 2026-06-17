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
