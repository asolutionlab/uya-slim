# 编译器 / 标准库 Bug 待办清单

**最后更新：** 2026-04-11

本文档用于跟踪 release 验证中发现的问题，便于逐项修复、验证和关闭。

## 分类规则

- **编译器 bug**：语法分析、类型检查、代码生成、优化、lowering 等问题。
- **标准库 bug**：`lib/std/**` 里的实现问题。
- **运行时 bug**：异步调度、事件循环、waker/future 状态机等问题。
- **网络 / TLS 回归**：TCP、HTTP、HTTPS、DNS、TLS 链路问题。

## 标准库 bug

- [ ] **P0 / 严重：`dns_client_query_all_async` 仍依赖手工状态机绕过 lowering 问题**
  - 状态：部分缓解，未根治
  - 验证状态：已用 `tests/test_std_dns_async_transport.uya` 复现并通过当前回归
  - 归属：`lib/std/net/dns.uya`
  - 现象：`dns_client_query_all_async` 已改成共享 async transport，但之前在 `catch`/`Ready` 分支里做状态切换时，生成代码曾丢失副作用，导致 `TC=1` 不能稳定切到 TCP fallback。
  - 影响：异步 DNS 的 TCP fallback 依赖当前写法和补丁后的 event loop 行为，后续如果编译器 lowering 变化，可能再次回归。
  - 可能位置：`lib/std/net/dns.uya`
  - 备注：建议继续把 future 内部的错误分支收敛成更明确的状态字段，尽量减少对 `catch` 副作用的依赖。

- [ ] **P3 / 低：`DNS_PREFER_ANY` 的异步聚合路径仍是顺序查询**
  - 状态：未优化
  - 验证状态：当前行为已确认，未做并发化改造
  - 归属：`lib/std/net/dns.uya`
  - 现象：`dns_client_query_all_async` 目前先查 A 再查 AAAA，再汇总结果，并不是并发竞争。
  - 影响：功能正确，但延迟仍然偏高，尤其在高 RTT 或 nameserver 慢响应时会放大等待时间。
  - 可能位置：`lib/std/net/dns.uya`
  - 备注：这不是阻塞性 bug，但属于后续可优化项。

## 运行时 bug

- [ ] **P1 / 高：`LinuxEpoll` 的注册/反注册语义仍偏脆弱**
  - 状态：部分缓解，未根治
  - 验证状态：`tests/test_std_dns_async_transport.uya`、`tests/test_http1_async_client.uya` 已通过
  - 归属：`lib/std/async_event.uya`
  - 现象：`block_on_with_event_loop` / `LinuxEpoll` 在 fd 复用、slot 清理和 epoll interest 重建时出现过 `ENOENT`、`EEXIST` 一类边界错误。
  - 影响：异步网络 future 在短生命周期 fd 或复用 fd 场景下更容易触发 event loop 边界问题。
  - 可能位置：`lib/std/async_event.uya`
  - 备注：当前已补了幂等清理和失败回退，但这块还建议继续做成更明确的“已注册 / 未注册”状态机。

## 网络 / TLS 回归

- [ ] **P0 / 严重：`make release-dirty` 还需要重新跑一轮做最终验收**
  - 状态：待验证
  - 验证状态：局部回归已通过，release 级全量验证未重新执行
  - 归属：整体验收
  - 现象：这次已经把 async DNS transport 和 epoll 回归单测跑通，但还没有在当前修改后重新确认整套 `make release-dirty`。
  - 影响：目前只能说局部回归已收敛，不能算 release 验证最终关闭。
  - 可能位置：网络栈、TLS 握手、异步 / 事件循环集成
  - 备注：建议在 release 级别再补一次全量验证，再决定是否从 buglist 中移除相关条目。

## 编译器 bug

- [ ] **P0 / 严重：`catch` 在复杂 future lowering 场景下仍值得继续关注**
  - 状态：已绕开，未确认根治
  - 验证状态：已在 DNS async transport 中复现过 lowering 丢副作用问题
  - 归属：编译器 lowering / 代码生成
  - 现象：在 `Future<!T>` 的 `poll` 实现里，`catch` 分支有过副作用丢失、状态转移不稳定的情况。
  - 影响：这类问题容易在 async lowering 和生成 C 时表现为“看起来编译通过，运行时却进入错误分支”。
  - 可能位置：代码生成 / lowering，尤其是 `Future<!T>`、`catch`、`Ready` 组合路径。
  - 备注：目前靠重写状态机规避了问题，但这类模式后续仍建议单独做编译器回归。

## 修复验收

修复完成后，请至少确认以下内容：

- `make release-dirty` 重新通过，或明确缩小失败范围。
- 相关单测通过：
  - `test_std_dns`
  - `test_std_dns_async_transport`
  - `test_epoll_server`
  - `test_tcp_basic`
  - `test_http_server`
  - `test_https_debug`
  - `test_https_loopback`
  - `test_https_real_site`
  - `test_raw_tls`
- 若问题涉及新行为，补充对应测试或回归用例。

## 相关文件

- `lib/std/async_event.uya`
- `lib/std/net/dns.uya`
- `tests/test_std_dns_async_transport.uya`
- `tests/test_std_dns.uya`
- `tests/test_epoll_server.uya`
- `tests/test_http_server.uya`
- `tests/test_https_debug.uya`
- `tests/test_https_loopback.uya`
- `tests/test_https_real_site.uya`
- `tests/test_raw_tls.uya`
- `tests/test_tcp_basic.uya`
