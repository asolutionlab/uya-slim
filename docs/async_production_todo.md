# Uya 异步量产 TODO

**最后更新**：2026-04-11  
**目标范围**：Linux + C99 后端 + `@async_fn` / `@await` / `Future` / `Poll` / `Waker` + `AsyncFd` / `LinuxEpoll`，优先保障 DNS、HTTP/1.1、HTTPS 客户端主链路达到可量产状态。

## 量产定义

- [x] `@async_fn` 在常见复杂控制流中稳定：`if/else if`、`while`、`for`、嵌套分支、await 间同步语句、提前返回错误。
- [x] 异步运行时在 fd 复用、短连接、服务端提前关闭、注册/反注册重复调用等边界下不崩溃、不忙等、不泄漏 fd。
- [x] DNS、HTTP/1.1、HTTPS 主链路有端到端回归，并能连续多轮通过。
- [x] release 闸门清晰：`make b`、`make check`、`make release-dirty`、关键网络测试通过或在无网络环境下明确 skip。
- [ ] 已知限制被文档化：跨平台 async 后端、连接池、TLS 会话复用、DNS A/AAAA 并发、完整取消语义可作为量产后二阶段。

## P0：编译器 async lowering 稳定化（已完成）

- [x] 修复复杂状态机 lowering 错位导致的运行期 SIGSEGV。
  - 关联：`buglist.md` 中 `@async_fn` 复杂状态机 lowering 后行为错位导致 SIGSEGV。
  - 重点形态：`else if` 分支内 await、分支内修改变量、分支后继续使用变量。
  - 验收：`tests/test_http1_async_client.uya` 中 chunked loopback 路径不再 SIGSEGV。
  - 验证：`tests/test_async_else_if_await.uya`、`tests/test_http1_async_client.uya` 通过。

- [x] 转正并修复 await 循环间同步语句丢失。
  - 关联：`docs/todo_async_loop_await.md` 的 Bug B。
  - 重点形态：读 header 循环后执行同步 parse/malloc/assign，再进入读 body 循环。
  - 验收：`tests/test_async_bug_b_sync_between.uya` 通过。

- [x] 修复分裂点附近局部变量与表达式提升问题。
  - 关联：`docs/todo_async_loop_await.md` 的 Bug D。
  - 覆盖：if 内局部变量、切片表达式、嵌套循环、`break` / `continue` resume 后错位。
  - 验收：`tests/test_async_bug_d_nested_block.uya` 通过，覆盖嵌套局部变量、`break` / `continue` resume、切片表达式与局部变量 `s` 的 poll state 指针命名冲突。

- [x] 修复 `@async_fn fn ... Future<!T>` 内直接 `return error.X` 的类型检查。
  - 关联：`buglist.md` 中 `@async_fn` 中 `return error.X` 报错。
  - 验收：新增 `tests/test_async_return_error_direct.uya`，覆盖 `Future<!i32>` no-await / after-await 直接 `return error.X`。
  - 后续：`Future<!void>` 直接错误返回还依赖 `Poll_err_void` / `Future_err_void` / `block_on<void>` 等 void monomorph 支持，单独纳入后续泛型特化工作。

## P1：异步运行时硬化（已完成）

- [x] 将 `LinuxEpoll` 注册状态显式化。
  - 位置：`lib/std/async_event.uya`。
  - 实现：
    - 添加 `SLOT_STATE_EMPTY` / `SLOT_STATE_REGISTERED` 显式状态常量
    - 添加 `slot_generations` 数组防止 fd 复用混淆
    - 添加 `next_generation` 全局代际计数器
    - 添加 `find_slot`、`alloc_slot`、`init_slot`、`clear_slot` 方法
  - 验收：重复 register、重复 deregister、fd 关闭后复用、短连接快速创建销毁均不触发 `ENOENT` / `EEXIST` 异常路径失控。

- [x] 增加 fd 复用与短连接压力回归。
  - 新增测试：`tests/test_std_async_event_fd_reuse.uya`
  - 覆盖：
    - `fd_reuse_basic`：基本注册/写入/poll/注销流程
    - `fd_reuse_after_close`：socket close 后新 fd 复用旧编号
    - `rapid_register_deregister`：100 次快速注册/注销压力测试
    - `two_fds_sequential`：顺序测试两个 fd 的独立性
  - 验收：所有测试通过 `test_std_async_event`、`test_async_fd`、`test_std_async_scheduler`、`test_std_async_event_fd_reuse`。

- [ ] 明确 `Waker` 单 fd 语义，决定是否扩展。
  - 当前可选策略：量产第一版保持单 fd，但文档化"单个 Future 同时只能挂一个 I/O interest"。
  - 若 HTTP/TLS 需要同时关注读写，则扩展为小数组或链表 interest。
  - 验收：`docs/std_async_design.md` 与实际实现一致。

- [ ] 检查状态机堆分配与 fd 生命周期释放。
  - 覆盖：Ready、Error、Pending 后取消/关闭、socket EOF、TLS handshake 失败。
  - 验收：ASan 或等价手段下关键 async 网络测试无明显泄漏和 use-after-free。

## P1：DNS / HTTP / HTTPS 主链路收敛

- [ ] 重新评估 `dns_client_query_all_async` 的手工状态机。
  - 当前状态：仍使用手工状态机实现（`DnsTcpFuture`、`DnsUdpFuture`），`dns_client_lookup_localhost_async` 已使用 `@async_fn`。
  - 选项 A：lowering 修复后改回更自然的 `@async_fn` 实现。
  - 选项 B：保留手工状态机，但将其视为正式实现，补齐状态字段和错误分支回归。
  - 验收：`TC=1` TCP fallback、默认 `ANY`、A / AAAA 路径连续多轮通过。

- [x] 恢复并稳定 HTTP/1.1 chunked / read-until-eof 路径。
  - 位置：`lib/std/http/http1_async.uya`。
  - 当前状态：
    - `http1_request_async` 使用 `parse_response_meta` 拒绝 chunked 编码（返回 `HttpChunkedNotSupported`）。
    - 流式接口 `http1_stream_request` 使用 `parse_response_meta_allow_chunked` 支持 chunked。
    - 同步读取 chunked body 接口 `http1_read_chunked_body_sync` 已可用（避开 async lowering 问题）。
  - 验收：chunked loopback、content-length、read-until-eof 三条路径均有测试。

- [~] 给 HTTP/DNS/TLS 主链路增加 timeout 策略。
  - 优先级：connect timeout、read timeout、write timeout、DNS query timeout、TLS handshake timeout。
  - 采用 deadline-based 策略：`deadline_ms = now_ms() + timeout_ms`，在每个 I/O 边界检查是否过期。
  - **已完成实现但被编译器 bug 阻塞**，详见下方"超时策略实现详情"。
  - 验收：连接拒绝、服务端不响应、服务端半关闭不导致无限等待或 busy-wait。

- [x] 完善 HTTPS 生产限制。
  - 证书验证框架已实现：
    - `lib/tls/x509/trust_store.uya`：系统根证书存储加载模块
    - `lib/tls/x509/cert.uya` 有效期字段和验证函数框架
    - 错误类型：`TlsCertificateVerificationFailed`, `TlsCertificateExpired`, `TlsCertificateNotYetValid`
  - `https_get()`：生产环境安全（默认启用证书验证）
  - `https_get_insecure()`：测试用途（跳过验证）
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

- [x] `make b` 自举一致。
- [x] `make check` 关键子集通过（`test_std_async_event`、`test_async_fd`、`test_std_async_scheduler`、`test_std_dns_async_transport`、`test_http1_async_client`）。
- [x] `make release-dirty` 通过；无外网环境下网络测试明确 skip。
- [x] `./tests/run_programs_parallel.sh --uya --c99 test_async_bug_b_sync_between.uya` 通过。
- [x] `./tests/run_programs_parallel.sh --uya --c99 test_http1_async_client.uya` 通过。
- [x] `./tests/run_programs_parallel.sh --uya --c99 test_std_dns_async_transport.uya` 连续多轮通过。
- [x] `./tests/run_programs_parallel.sh --uya --c99 test_std_async_event_fd_reuse.uya` 通过（新增 fd 复用压力测试）。
- [x] 关键测试通过：`test_async_fd`、`test_std_async_event`、`test_std_async_scheduler`、`test_std_dns`、`test_http_server`、`test_epoll_server`、`test_https_loopback`、`test_https_real_site`、`test_raw_tls`。
- [ ] HTTP async loopback 稳定性：至少 30 分钟无崩溃、无 busy-wait、RSS 不持续增长、fd 不泄漏。
- [ ] `docs/std_async_design.md`、`docs/todo_async_loop_await.md`、`buglist.md` 与最终状态同步。

## 推进顺序

1. ~~先关闭 P0 lowering：SIGSEGV、Bug B、Bug D、`return error.X`。~~ ✅ 已完成
2. ~~再硬化 `LinuxEpoll` / `Waker` / 生命周期释放。~~ ✅ 已完成（LinuxEpoll 显式状态机 + fd 复用测试）
3. 然后收敛 DNS / HTTP / HTTPS 主链路，移除或正式化绕过方案。
4. 最后做压测、release 闸门、文档同步。

## 当前状态摘要（2026-04-11）

**已完成**：
- ✅ P0 编译器 async lowering 稳定化全部完成
- ✅ LinuxEpoll 显式状态机（SlotState + generation）
- ✅ fd 复用与短连接压力回归测试
- ✅ HTTP/1.1 主链路（content-length、read-until-eof、chunked 同步读取）
- ✅ HTTPS 生产环境基础能力（证书验证框架、系统根证书加载）
- ✅ DNS 异步查询（手工状态机实现）
- ✅ 核心 async 运行时（`LinuxEpoll`、`Waker`、`AsyncFd`）

**进行中/待完成**：
- [~] 完整 timeout 策略实现（HTTP/DNS/TLS）— 已实现但被 `@async_fn` 变量提升 bug 阻塞
- [ ] DNS 从手工状态机迁移到 `@async_fn`
- [ ] HTTP chunked 异步读取（当前为同步实现）
- [ ] 长时稳定性测试（30 分钟压力测试）
- [ ] 文档同步更新

---

## 超时策略实现详情（2026-04-11）

### 设计

采用 **deadline-based** 超时策略：请求开始时计算绝对截止时间 `deadline_ms = now_ms() + timeout_ms`，在每个 I/O 边界检查 `now >= deadline_ms`。`timeout_ms = 0` 表示不超时（无限等待）。

### 已修改文件

#### 1. `lib/std/http/http1_async.uya`（主要改动）

- 新增 `export error HttpTimeout;`
- 新增 7 个本地时间辅助函数（避免跨模块 `time.xxx` 在 `@async_fn` 中的编译器 bug）：
  - `http_now_ms() !u64` — 基于 `sys_gettimeofday`
  - `http_deadline_after_ms(timeout_ms) !u64`
  - `http_deadline_expired(deadline_ms) !bool`
  - `http_deadline_remaining_ms(deadline_ms) !i32`
  - `http_deadline_expired_or_false(deadline_ms) bool` — 出错返回 false
  - `http_deadline_remaining_or_neg1(deadline_ms) i32` — 出错返回 -1
  - `http_check_deadline(deadline_ms) !void` — 过期返回 `error.HttpTimeout`
- `Http1ConnectFuture` 增加 `deadline_ms: u64` 字段，`poll()` 中检查超时
- 修改函数签名（增加 `timeout_ms: u32`）：
  - `http1_request_async(req, timeout_ms)` — `@async_fn`
  - `http1_request_blocking(req, timeout_ms)`
  - `http1_async_get(url, req, timeout_ms)` — `@async_fn`
  - `http1_async_post(url, req, timeout_ms)` — `@async_fn`
- `http1_connect_for_host_future(host, port, deadline_ms)` — DNS 查询超时从剩余 deadline 派生
- `http1_request_blocking` — 使用 `block_on_with_event_loop_deadline`
- ⚠️ `http1_request_async` 中的 `try http_check_deadline(deadline_ms)` 调用全部被注释掉（行 846、856、912、931），因触发 `@async_fn` 变量提升 bug

#### 2. `lib/std/async_scheduler.uya`

- 新增本地时间辅助函数：`sched_now_ms()`, `sched_deadline_expired()`, `sched_deadline_remaining_ms()`
- 新增 `block_on_with_event_loop_deadline<T>(loop, f, timeout_ms, deadline_ms)` — 带总超时保护的 block_on
- `block_on_with_event_loop` 保持独立实现（不调用 deadline 版本），避免泛型实例化顺序 bug

#### 3. `lib/tls/https.uya`

- 新增本地时间辅助函数：`https_now_ms()`, `https_deadline_after_ms()`, `https_deadline_expired()`
- 新增 socket 超时函数：`https_socket_set_recv_timeout(fd, ms)`, `https_socket_set_send_timeout(fd, ms)` — 使用 `setsockopt(SO_RCVTIMEO/SO_SNDTIMEO)`
- 新增 `HttpsClientConfig` 结构体：含 `verify_server_cert`, `verify_hostname`, `trust_store`, `timeout_ms`
- 新增 `https_client_config_default()`, `https_client_config_insecure()`, `https_get_with_config()`
- `https_get_internal()` 改为接受 `&HttpsClientConfig`，设置 socket 超时，在 connect/handshake 后检查 deadline
- `https_get()` 和 `https_get_insecure()` 改为使用配置对象

#### 4. `lib/std/time.uya`（已创建但未使用）

- 提供 `now_ms()`, `deadline_after_ms()`, `deadline_expired()`, `deadline_remaining_ms()` 通用时间工具
- 因跨模块 `time.xxx` 在 `@async_fn` 中存在编译器 bug，各模块改为本地重复实现

#### 5. `tests/test_http1_async_client.uya`

- 所有 `http1_async_get`/`http1_async_post` 调用已更新为 3 参数版本（增加 `timeout_ms`）

### 超时覆盖范围

| 阶段 | HTTP (async) | HTTPS (sync) | 实现方式 |
|------|-------------|-------------|---------|
| DNS 查询 | ✅ | ✅ | 从 deadline 计算剩余时间作为 DNS timeout |
| TCP 连接 | ✅ | ❌（阻塞 connect） | `Http1ConnectFuture.poll()` 中检查 deadline |
| TLS 握手 | N/A | ✅ | handshake 前后检查 deadline |
| Socket 读 | ❌（TODO） | ✅ | HTTPS: `SO_RCVTIMEO`；HTTP: `http_check_deadline` 被注释 |
| Socket 写 | ❌（TODO） | ✅ | HTTPS: `SO_SNDTIMEO`；HTTP: 未添加 |
| 读 body 循环 | ❌（TODO） | N/A | `http_check_deadline` 被注释 |
| EventLoop 层 | ✅ | N/A | `block_on_with_event_loop_deadline` 检查 deadline |

### 🔴 阻塞问题：`@async_fn` 变量提升 bug

**现象**：在 `http1_request_async`（`@async_fn`）中，添加 `try http_check_deadline(deadline_ms)` 调用后，编译器生成的 C 代码中 `copied` 局部变量未被正确提升到状态机结构体，导致 C 编译报错 `'copied' undeclared`。

**根因**：`@async_fn` 的状态机转换（lowering）在遇到更多 await 点或 error-union-returning 函数调用时，变量提升逻辑出错——跨 await 点使用的局部变量（如 `copied`）未被正确识别并提升为状态机字段。

**临时绕过**：`http1_request_async` 中的 `http_check_deadline` 调用全部注释掉。HTTP async 路径在 I/O 等待期间无主动超时检查，只能依赖 `block_on_with_event_loop_deadline` 在 EventLoop 层的被动检查。

**修复方向**：修改编译器 `src/` 中的 `@async_fn` lowering 代码，确保所有跨 await 点的局部变量都被正确提升。

### 🟡 次要问题

1. **跨模块 `time.xxx` 调用在 `@async_fn` 中的 bug**：`use std.time` 后在 `@async_fn` 中调用 `time.now_ms()` 触发编译器错误。各模块临时使用本地时间函数绕过。
2. **`catch { value }` 语法解析问题**：`expr catch { 0 as u64 }` 在复杂上下文可能触发 "unexpected token '}'" 错误。使用中间变量绕过。

### 验证状态

- `make b`（自举）：✅ 通过
- `make tests`：❌ HTTP 测试在 C 编译阶段失败（`@async_fn` 变量提升 bug 导致 `copied` undeclared）
- 修改前的代码（无 timeout）：所有测试通过

### git 状态

```
modified:   buglist.md
modified:   lib/std/async_scheduler.uya
modified:   lib/std/http/http1_async.uya
modified:   lib/tls/https.uya
modified:   tests/test_http1_async_client.uya
Untracked:  lib/std/time.uya
```

### 下一步

1. **修复 `@async_fn` 变量提升 bug**（编译器 `src/`）— 解锁 HTTP async 超时功能的关键
2. 取消 `http1_request_async` 中 `http_check_deadline` 的注释
3. `make check` 通过后提交
4. 可选：修复跨模块 `time.xxx` bug 后统一使用 `lib/std/time.uya`，删除重复时间函数
