# UyaGin / Async 编译器边界报告（2026-04-25）

本文档记录这轮为 `std.http.uyagin` P5 收口时实际撞到的编译器边界，以及当前已经修复/仍保留的项。

## 已修复

### Bug 1：direct err-union await bind 漏切状态机

现象：

```uya
@async_fn
fn f() Future<!i32> {
    const r: !i32 = @await ready_i32();
    const v: i32 = r catch { 0 - 10; };
    return v + 5;
}
```

旧行为：

- await 点未被 async state machine 收集；
- 生成的 C 会把 `Future<!T>` 当成 `!T` 直接赋值，或恢复后把绑定变量当普通标量处理；
- 典型表现是错误联合绑定变量在后续 `catch` / 访问中退化为默认值。

修复：

- `src/codegen/c99/function.uya`
  - await 点收集从“仅 `try @await`”扩展到“直接 `@await` 绑定到变量 / `return`”；
  - 恢复阶段对 `!T` 绑定变量写回整个错误联合，而不是只写 `.value`。
- `src/codegen/c99/types.uya`
  - async bind 变量参与 identifier type lookup。
- `src/codegen/c99/expr.uya`
  - async bind 变量参与 type node lookup，保证 `catch` / 其它表达式重发时类型仍正确。

回归：

- `tests/test_async_await_direct_err_union.uya`

### Bug 2：UyaGin 文件发送路径触发 `@await` lowering 误用 future 值

现象：

- `uyagin_send_file_body_async` 最初通过多层 `@await` 组合 `sendfile` / fallback future；
- 旧 C99 lowering 会把 `Future<!usize>` 本体误塞进 `!usize` 临时变量。

修复：

- 文件发送路径改成手写 `Future<!usize>`（`UyaginSendFileBodyFuture`）；
- 主逻辑仍保留 Linux x86_64 `sendfile` 优先、其它路径 fallback 的语义；
- 避开当前 `@async_fn` 内嵌 future 组合的 codegen 脆弱点。

回归覆盖：

- `tests/test_http_uyagin.uya`
- `tests/test_https_loopback.uya`

### Bug 3：手工构造 `Request.headers` 时依赖缓存元数据

现象：

- 为 parser 热路径引入 `name_hash` / `name_kind` 后，测试或调用方若手工写 `Request.headers[i].name/value`，但不补这些缓存字段，`request_get_header` / limit 校验会错误失配。

修复：

- `lib/std/http/types.uya`
  - `request_get_header` 优先走缓存，但若缓存缺失会自动回退到逐字节大小写不敏感比较；
  - `request_has_content_length` 也保留了无缓存的回退路径。

这不是 compiler bug，但属于“优化引入的新 API 契约边界”，在这里一并记录。

## 仍保留

### Bug 4：parser 对 `catch { ... }` 某些写法打印假性语法错误

典型现象：

```uya
const x: i32 = foo() catch { 0 - 1 };
```

当前可能打印：

- `意外的 token '}'`

但后续：

- AST 合并继续成功；
- 类型检查继续成功；
- C99 代码生成与程序运行也可正常通过。

结论：

- 这是 parser/diagnostic 噪音，而不是实际 blocking compile error。
- 当前对 `tests/test_http_server.uya` 等文件仍可见这类误报。

处理策略：

- 保留为后续 parser 诊断修正项；
- 不再把它视为 P5 主链路 blocker。

## 当前结论

- UyaGin P5 所需的主 blocker 已从“编译器导致功能不可达”收缩到“个别 parser 诊断噪音”。
- 当前 HTTP/1.1 chunked / `writev` / `sendfile` / TLS -> UyaGin 桥接链路都已经可以通过真实回归验证。
