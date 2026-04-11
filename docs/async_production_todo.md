# Uya 异步量产 TODO

**最后更新**：2026-04-11  
**目标范围**：Linux + C99 后端 + `@async_fn` / `@await` / `Future` / `Poll` / `Waker` + `AsyncFd` / `LinuxEpoll`，优先保障 DNS、HTTP/1.1、HTTPS 客户端主链路达到可量产状态。

## 量产定义

- [ ] `@async_fn` 在常见复杂控制流中稳定：`if/else if`、`while`、`for`、嵌套分支、await 间同步语句、提前返回错误。
- [ ] 异步运行时在 fd 复用、短连接、服务端提前关闭、注册/反注册重复调用等边界下不崩溃、不忙等、不泄漏 fd。
- [ ] DNS、HTTP/1.1、HTTPS 主链路有端到端回归，并能连续多轮通过。
- [ ] release 闸门清晰：`make b`、`make check`、`make release-dirty`、关键网络测试通过或在无网络环境下明确 skip。
- [ ] 已知限制被文档化：跨平台 async 后端、连接池、TLS 会话复用、DNS A/AAAA 并发、完整取消语义可作为量产后二阶段。

## P0：编译器 async lowering 稳定化

- [ ] 修复复杂状态机 lowering 错位导致的运行期 SIGSEGV。
  - 关联：`buglist.md` 中 `@async_fn` 复杂状态机 lowering 后行为错位导致 SIGSEGV。
  - 重点形态：`else if` 分支内 await、分支内修改变量、分支后继续使用变量。
  - 验收：`tests/test_http1_async_client.uya` 中 chunked loopback 路径不再 SIGSEGV。

- [ ] 转正并修复 await 循环间同步语句丢失。
  - 关联：`docs/todo_async_loop_await.md` 的 Bug B。
  - 重点形态：读 header 循环后执行同步 parse/malloc/assign，再进入读 body 循环。
  - 验收：`tests/test_async_bug_b_sync_between.uya.pending` 改为 `.uya` 并通过。

- [ ] 修复分裂点附近局部变量与表达式提升问题。
  - 关联：`docs/todo_async_loop_await.md` 的 Bug D。
  - 覆盖：if 内局部变量、切片表达式、嵌套循环、`break` / `continue` resume 后错位。
  - 验收：新增最小回归，覆盖 `xxx undeclared`、`break not within loop`、切片类型错发射。

- [ ] 修复 `@async_fn fn ... Future<!T>` 内直接 `return error.X` 的类型检查。
  - 关联：`buglist.md` 中 `@async_fn` 中 `return error.X` 报错。
  - 验收：新增 `Future<!usize>` / `Future<!void>` 提前返回错误测试，移除依赖辅助函数包装错误的绕过路径。

## P1：异步运行时硬化

- [ ] 将 `LinuxEpoll` 注册状态显式化。
  - 位置：`lib/std/async_event.uya`。
  - 建议：slot 记录 `registered`、`fd`、`interest`、可选 generation，明确 add / mod / del 状态转移。
  - 验收：重复 register、重复 deregister、fd 关闭后复用、短连接快速创建销毁均不触发 `ENOENT` / `EEXIST` 异常路径失控。

- [ ] 增加 fd 复用与短连接压力回归。
  - 覆盖：socket close 后新 fd 复用旧编号、Pending 后 peer close、register 后立即 deregister。
  - 验收：`test_std_async_event`、`test_async_fd`、`test_std_async_scheduler` 之外新增定向回归。

- [ ] 明确 `Waker` 单 fd 语义，决定是否扩展。
  - 当前可选策略：量产第一版保持单 fd，但文档化“单个 Future 同时只能挂一个 I/O interest”。
  - 若 HTTP/TLS 需要同时关注读写，则扩展为小数组或链表 interest。
  - 验收：`docs/std_async_design.md` 与实际实现一致。

- [ ] 检查状态机堆分配与 fd 生命周期释放。
  - 覆盖：Ready、Error、Pending 后取消/关闭、socket EOF、TLS handshake 失败。
  - 验收：ASan 或等价手段下关键 async 网络测试无明显泄漏和 use-after-free。

## P1：DNS / HTTP / HTTPS 主链路收敛

- [ ] 重新评估 `dns_client_query_all_async` 的手工状态机。
  - 选项 A：lowering 修复后改回更自然的 `@async_fn` 实现。
  - 选项 B：保留手工状态机，但将其视为正式实现，补齐状态字段和错误分支回归。
  - 验收：`TC=1` TCP fallback、默认 `ANY`、A / AAAA 路径连续多轮通过。

- [ ] 恢复并稳定 HTTP/1.1 chunked / read-until-eof 路径。
  - 位置：`lib/std/http/http1_async.uya`。
  - 验收：chunked loopback、content-length、read-until-eof 三条路径均有测试。

- [ ] 给 HTTP/DNS/TLS 主链路增加 timeout 策略。
  - 优先级：connect timeout、read timeout、write timeout、DNS query timeout、TLS handshake timeout。
  - 验收：连接拒绝、服务端不响应、服务端半关闭不导致无限等待或 busy-wait。

- [ ] 完善 HTTPS 生产限制。
  - 证书有效期 ASN.1 时间解析补齐或明确标记为未完成。
  - chunked 响应支持或公开 API 明确返回 `HttpChunkedNotSupported`。
  - 验收：`test_https_production`、`test_https_real_site`、`test_https_loopback` 行为一致。

## P2：量产后二阶段能力

- [ ] DNS A / AAAA 并发聚合，减少高 RTT 下延迟。
- [ ] 通用泛型 TaskQueue，减少 `i32` 专用入口。
- [ ] 完整取消语义：任务取消、I/O deregister、资源释放。
- [ ] HTTP 连接池与 keep-alive 复用。
- [ ] TLS 会话复用。
- [ ] macOS kqueue / Windows IOCP 后端。
- [ ] 更细粒度性能优化，建立每 release 的 async benchmark baseline。

## 验收清单

- [ ] `make b` 自举一致。
- [ ] `make check` 全量通过。
- [ ] `make release-dirty` 通过；无外网环境下网络测试明确 skip。
- [ ] `./tests/run_programs_parallel.sh --uya --c99 test_async_bug_b_sync_between.uya` 通过。
- [ ] `./tests/run_programs_parallel.sh --uya --c99 test_http1_async_client.uya` 通过。
- [ ] `./tests/run_programs_parallel.sh --uya --c99 test_std_dns_async_transport.uya` 连续多轮通过。
- [ ] 关键测试通过：`test_async_fd`、`test_std_async_event`、`test_std_async_scheduler`、`test_std_dns`、`test_http_server`、`test_epoll_server`、`test_https_loopback`、`test_https_real_site`、`test_raw_tls`。
- [ ] HTTP async loopback 稳定性：至少 30 分钟无崩溃、无 busy-wait、RSS 不持续增长、fd 不泄漏。
- [ ] `docs/std_async_design.md`、`docs/todo_async_loop_await.md`、`buglist.md` 与最终状态同步。

## 推进顺序

1. 先关闭 P0 lowering：SIGSEGV、Bug B、Bug D、`return error.X`。
2. 再硬化 `LinuxEpoll` / `Waker` / 生命周期释放。
3. 然后收敛 DNS / HTTP / HTTPS 主链路，移除或正式化绕过方案。
4. 最后做压测、release 闸门、文档同步。

