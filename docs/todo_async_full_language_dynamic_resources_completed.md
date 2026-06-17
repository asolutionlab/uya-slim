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
