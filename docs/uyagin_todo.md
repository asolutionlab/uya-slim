# UyaGin TODO / 路线图

本 TODO 以“先稳定、再压测、最后超过 Gin”为主线。所有性能结论必须用同机、同业务、同连接模型的 benchmark 证明，不能只凭设计假设宣称达标。

## P0：核心切片（已完成）

- [x] 新增 `std.http.uyagin` 模块。
- [x] 定义 `Engine`、`GinContext`、`AsyncHandler`、`AsyncMiddleware`。
- [x] 支持 `GET/POST/PUT/PATCH/DELETE/OPTIONS/HEAD` 注册。
- [x] 支持 path 参数：`/users/:id` + `ctx.param("id")`。
- [x] 支持 `ctx.string`、`ctx.json_raw`、`ctx.no_content`。
- [x] 支持异步响应写入与小响应合并写。
- [x] 支持异步 read + parse 与单连接 keep-alive loop。
- [x] 增加核心单测：200、path param、404。

## P1：框架语义补齐

- [x] 增加 middleware chain：`Use(...)`、route group、`Abort()` 后停止链。
- [x] 增加统一错误映射：协议错误→4xx，业务未处理错误→500。
- [x] 增加 recovery middleware：记录错误、写 500、防止连接状态污染。
- [x] 增加 `ctx.status`、`ctx.header_set`、`ctx.redirect`、`ctx.bytes`。
- [x] 增加 query/form helpers：`DefaultQuery`、`PostForm`、multipart file view。
- [x] 增加 HEAD 自动去 body、OPTIONS 自动 Allow。

## P2：高性能路由

- [x] 将线性 `Router` 替换为方法分表 radix tree。
- [x] 静态路由优先，参数路由次之，通配路由最后。
- [x] 启动期预计算 pattern segment、param name offset、literal hash。
- [~] 提供 `GET_T<H: AsyncHandler>` 泛型注册，减少 vtable dispatch。
  当前已落地兼容入口 `GET_T(engine, pattern, handler)`；受当前编译器对泛型 thunk / `sizeof(H)` codegen 限制，仍走 `AsyncHandler` 接口派发。
- [x] 增加路由冲突检测：重复路径、参数名冲突、wildcard 非尾部。
- [x] Benchmark 路由：1、16、128、1024 条路由的 ns/match 与 Gin 对比。
  2026-04-24 本机实测：已新增 `benchmarks/uyagin_route_bench.uya`、`benchmarks/gin_route_bench/uyagin_route_gin_bench_test.go` 与 `benchmarks/run_uyagin_route_bench.sh`，并完成 Uya/Gin 对照。

## P3：连接与调度

- [x] 实现 `Engine.run(listener, loop, scheduler)` accept loop。
- [x] 支持单 EventLoop 多连接任务队列，连接 future 完成后回收 slot。
- [x] 支持多 reactor shard：按 CPU 数启动 N 个 loop。
- [x] 支持 `SO_REUSEPORT` 或 accept 后 fd 分发。
- [x] 增加连接限流、read timeout、write timeout、idle timeout。
- [x] 增加优雅关闭：停止 accept、drain keep-alive、deadline 强关。

## P4：内存与 allocator

- [ ] 为每请求增加 `Arena`，通过 `GinContext.allocator` 注入。
- [ ] `RequestArena.drop` 自动 reset/归还，错误路径用同步 helper + `errdefer` rollback。
- [ ] async frame pool 与 scheduler 绑定，避免热路径 malloc。
- [ ] 增加响应 body trait：static slice、arena bytes、file/sendfile。
- [ ] 增加最大 header/body/form 限额并暴露配置。
- [ ] 增加内存指标：arena used、frame alloc/free、heap fallback 次数。

## P5：HTTP 协议与 I/O 优化

- [ ] 解析器 SIMD/word-at-a-time 扫描 CRLF、冒号、空格。
- [ ] Header name 小写/哈希缓存，常见 header 快速路径。
- [ ] 响应使用 `writev` 合并 header/body，避免大 body 复制。
- [ ] 静态文件使用 `sendfile` / `splice`。
- [ ] 支持 chunked request/response。
- [ ] 支持 TLS accept/serve，复用现有 `tls` 模块。
- [ ] 评估 HTTP/2：优先 h2c/TLS ALPN 设计，不影响 HTTP/1 热路径。

## P6：可观测性与生产配置

- [ ] Access log middleware：可关闭、可采样、零分配格式化。
- [ ] Metrics middleware：请求数、状态码、延迟直方图、连接数。
- [ ] Panic/error trace：结合 Uya 源码位置 builtin 输出。
- [ ] 配置结构：backlog、max connections、buffer cap、timeouts、allocator。
- [ ] 运行模式：debug/release，debug 开启更多边界检查和日志。

## P7：Benchmark 达标计划

### 基准场景

- [ ] `hello plaintext`：固定 12B body，keep-alive。
- [ ] `json small`：100B JSON。
- [ ] `path param`：`/users/:id`。
- [ ] `middleware x3`：logger disabled + recovery + auth stub。
- [ ] `large body`：64KiB 响应。

### 对照条件

- [ ] 同一台 Linux x86_64 机器。
- [ ] 同一编译级别：Uya `-O2/-O3`，Gin 使用 `go build -ldflags="-s -w"`。
- [ ] 同一工具：`wrk` 或 `wrk2`，固定线程/连接/持续时间。
- [ ] 记录 CPU governor、内核版本、ulimit、somaxconn。
- [ ] 每项至少 5 次，取 median 与 p99。

### 达标指标

- [ ] RPS：UyaGin median ≥ Gin median * 1.20。
- [ ] p99：UyaGin p99 ≤ Gin p99 * 0.85。
- [ ] alloc/op：热路径 0 heap allocation。
- [ ] syscall/req：hello keep-alive 接近 1 write + 摊销 read/epoll。
- [ ] CPU：同 RPS 下 user+sys CPU 低于 Gin。

## P8：兼容性与文档

- [ ] 完整 API 文档：注册、上下文、错误、响应、生命周期。
- [ ] 迁移指南：Gin handler → UyaGin handler。
- [ ] 示例：hello、JSON、JWT、multipart、static file、middleware。
- [ ] 压测报告：包含命令、硬件、原始数据、火焰图。
- [ ] 编译器边界清理：继续随着 Uya C 后端修复删除 UyaGin 中的兼容层 / workaround；当前状态见 `docs/compiler_bug_report_2026-04-24_uyagin_async.md`。
  当前报告已同步到：Bug 1 / 2 / 4 已修复，Bug 3 仍建议保留防御性拆分并补专门回归。
