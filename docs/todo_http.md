# Uya HTTP 框架实现待办

**参考**：[http_framework_design.md](http_framework_design.md)、[.cursor/plans/uya_高性能_http_框架_09efdaaa.plan.md](.cursor/plans/uya_高性能_http_框架_09efdaaa.plan.md)

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。新增测试需同时通过 `--c99` 与 `--uya --c99`。

---

## Phase 1：TCP 基础设施

### 1.1 前置

- [ ] 确认 Uya 可用的 socket/syscall 封装（若尚无，在 **lib/libc/** 如 syscall.uya 或 socket.uya 增加 socket 相关系统调用封装；若需更高级 API 再在 lib/std/net 或 lib/std/sys 提供）
- [ ] 确认 fd 类型（i32 或等效）与 close 语义

### 1.2 测试

- [ ] `tests/test_tcp_*.uya` 或 `tests/programs/test_tcp_*.uya`：建立 listen、accept 一次、读写字节、关闭

---

## Phase 2：http.types

### 2.1 目录与错误

- [ ] 创建 `lib/std/http/` 目录
- [ ] `types.uya`：预定义错误 InvalidRequest、MethodNotAllowed、URITooLong、HeaderTooLarge、PayloadTooLarge、TooManyParams、ValueTooLong、InvalidToken、InvalidBoundary、TooManyParts

### 2.2 枚举与常量

- [ ] Method 枚举：GET、POST、PUT、PATCH、DELETE、OPTIONS、HEAD
- [ ] Status 枚举：OK、Created、NoContent、BadRequest、NotFound、MethodNotAllowed、Conflict、InternalServerError 等
- [ ] ServerMode 枚举：Blocking、Epoll、ThreadPool
- [ ] 常量 P=8、Q=16、L=256、MAX_MULTIPART_PARTS（path_params/query 条数、单 key/value 最大字节、multipart part 数量上限）

### 2.3 结构体

- [ ] Request：method、path、path_params、query、headers、body（借用 &[byte]，buffer 归 Server/Conn）；multipart 时提供 Part 类型与 parse_multipart / req.multipart()
- [ ] path_params/query 为固定容量线性数组（P、Q、L）
- [ ] Response：status、headers、body
- [ ] Context：request、response、conn
- [ ] Conn：fd；实现 `fn drop(self: Conn) void`（按值关闭 fd）

### 2.4 接口与辅助

- [ ] Handler 接口：`fn serve(self: &Self, ctx: &Context) !void`
- [ ] Middleware 接口：`fn process(self: &Self, ctx: &Context, next: Handler) !void`（首版仅类型）
- [x] `request_get_header(req, name)` / `get_bearer_token(req)`（`lib/std/http/types.uya`；头名大小写不敏感；Bearer 前缀大小写不敏感；测试见 `test_http_types.uya`、`parse_then_request_get_header`）
- [ ] ServerConfig：mode、max_connections

### 2.5 测试

- [x] `tests/test_http_types.uya`：枚举、常量、`parse_method_bytes` 失败、`request_get_header` / `get_bearer_token` 成功与错误路径

---

## Phase 3：http.parse

### 3.1 解析器

- [ ] `parse.uya`：`parse(buf: &[byte]) !Request` 或 `!ParseResult`；若单请求则仅返回 Request，若支持 Keep-alive 则返回 consumed（或 ParseResult 含 request + consumed），供下一轮 parse 使用剩余数据
- [ ] 请求行：METHOD SP URI SP VERSION；URI 含 path + query
- [ ] 头部解析：Content-Type、Content-Length 等；单 header 与总 header 受 L/常量限制
- [ ] Body：按 Content-Length，首版 body 上限（如 64KB）；Content-Type 为 multipart/form-data 时按 boundary 解析 part
- [ ] Multipart：parse_multipart(body, boundary) 或 Request.multipart()；Part 含 name、filename、content_type、body；常量 MAX_MULTIPART_PARTS 限定 part 数；InvalidBoundary/TooManyParts
- [ ] 所有下标访问在当前函数内证明安全（循环条件/边界检查），失败返回 error.XXX

### 3.2 Keep-alive

- [ ] 单请求边界：请求行 + 头部 + Content-Length body；多请求时根据 parse 返回的 consumed 或 remaining 将剩余数据作为下一轮 parse 输入

### 3.3 测试

- [x] `tests/test_http_parse.uya`：GET/POST、path、query、headers、body、Keep-alive；多种错误（`InvalidRequest`、`URITooLong`、`HeaderTooLarge`、`PayloadTooLarge`、`IncompleteRequest`）
- [x] `tests/test_http_multipart.uya`：`extract_multipart_boundary`（含引号）、缺失 boundary、`parse_multipart` 单段、boundary 过长

---

## Phase 4：http.router

### 4.1 Router

- [x] `router.uya`：路由表 `(method, path_pattern)` 条目 + `router_find_route` 返回命中下标；容量由 `MAX_ROUTES` 限定；首版不存 `Handler`（由调用方按下标映射）
- [x] 路径参数：`/users/:id` 等；`router_apply_path_params` 写入 `Request.path_params`
- [x] 404：`router_find_route` 返回 `-1`；405：返回 `-2`（存在同路径模式但方法不符）

### 4.2 资源组（可选）

- [ ] ResourceHandlers 结构体字面量：get、post、get_by_id、put、delete 等；router.resource("/users", handlers)

### 4.3 测试

- [x] `tests/test_http_router.uya`：注册、匹配、path_params 提取、404/405

---

## Phase 5：http.server

### 5.1 Server

- [x] `server.uya`：`HttpServer`、`ServerConfig`；`http_server_listen` / `http_server_accept` / `http_server_close`（`ServerMode.Blocking` + 127.0.0.1；`port==0` 时 `getsockname` 填端口）
- [x] `http_recv_parse_request`（内部多 `recv` + `parse`）、`http_send_response`（`text/plain` + `Content-Length`；状态行含 200/201/204/400/404/405/500）、`http_tcp_connect_loopback`（测试用）
- [ ] 首版路线图：阻塞 accept + 每连接一线程；当前标准库为原语级 API，无自动「每连接一线程」封装
- [x] 每连接：读 buffer -> parse -> `router`/Handler -> 写 Response；Keep-alive 多轮 parse（`http_conn_read_parse` + `http_connbuf_shift` + `IncompleteRequest` / 多次 `recv`）
- [x] 错误路径（解析）：非法方法等导致 `!ParseResult` 时服务端可回 `400`（`http_parse_error_returns_400`）；Handler 层统一 5xx 仍待扩展

### 5.2 epoll 预留

- [ ] `ServerConfig.mode` 已含 `ServerMode.Epoll`；`server.uya` 中 `Blocking` 以外仍返回错误，未实现 `run_epoll_loop`

### 5.3 测试与示例

- [x] `tests/test_http_server.uya`：fork 子进程作客户端，父进程 accept → parse → `router_find_route_request` → 响应；校验 plaintext（`--safety-proof` + `make check`）
- [x] `examples/http_server.uya`：最小可运行示例（`127.0.0.1:8765`，单连接一次请求；`match` 成功分支须置于错误分支之后以避免 C99 后端问题）

### 5.4 相关修复（syscall）

- [x] Linux x86_64：`SYS_waitpid`(61) 实为 `wait4`，`sys_waitpid` / `libc.unistd.waitpid` 已改为四参（`rusage=NULL`），避免 `wait` 后异常崩溃（影响 `pthread_join` 等）

---

## Phase 6：测试与示例完善

### 6.1 覆盖

- [ ] 所有 !T 错误路径有测试（parse、router、get_header、get_bearer_token）（已部分覆盖：含 `parse_header_*`、`parse_too_many_headers`、`test_http_multipart`、`router_add_*` 等）
- [x] 多请求 Keep-alive 测试（`tests/test_http_server.uya` 流水线双 GET + `parse_post_body_incomplete`）
- [x] 预期编译失败：`tests/error_http_request_get_header_type.uya`（少传 `request_get_header` 参数）

### 6.2 示例

- [x] REST 场景测试：`http_pipeline_post_created_get_no_content`（流水线 POST→`201 Created`+body、GET→`204 No Content`）；`http_get_path_param_and_query`（`GET /item/99?q=v` + `router_apply_path_params_request`，`path_params[].value` 指向 `Request.path`）
- [x] 在 [readme.md](../readme.md) 已增加「标准库 HTTP（实验性）」小节（TDD、`make check`、`--uya --c99`）；设计文档仍见 [http_framework_design.md](http_framework_design.md)

---

## Phase 7：http.jwt

### 7.1 工具与解析

- [ ] `jwt.uya`：Base64URL 解码（decode_base64url）
- [ ] JWT 三段解析：header.payload.signature；不依赖 get_bearer_token

### 7.2 API

- [ ] verify(token: &[byte], secret: &[byte]) !&[byte]（HS256 验签，返回 raw payload）
- [ ] decode(token: &[byte]) !&[byte]（不验签）
- [ ] sign(payload: &[byte], secret: &[byte]) !&[byte]（签发 HS256）
- [ ] has_expired(payload: &[byte]) bool（可选；首版可不实现）

### 7.3 依赖

- [ ] HMAC-SHA256：FFI（libc/OpenSSL）或最小自实现；文档注明选择

### 7.4 测试

- [ ] `tests/test_http_jwt.uya`：verify、decode、sign、无效 token 返回 InvalidToken

---

## Phase 8：性能基准与验证

### 8.1 基准程序

- [ ] `benchmarks/http_bench.uya` 或等价：plaintext、简单 JSON、path 参数；body 档位 1KB/10KB/100KB
- [ ] 记录 QPS、p50/p95/p99 延迟、并发连接数、内存（RSS/每连接）

### 8.2 环境与脚本

- [ ] 文档记录：CPU、内存、OS、编译器；wrk 使用 keep-alive
- [ ] 脚本解析 wrk 输出；基线存入 `benchmarks/baseline.json`
- [ ] 回归允许 ±5%；CI 或文档中说明如何复现

---

## Phase 9/10：后续迭代

- [ ] ServerMode.Epoll 多路复用实现
- [ ] 中间件实现：logging、CORS、jwt_auth（包装 Handler，401/403 语义见设计文档）
- [ ] 异步 Handler、线程池模式（ThreadPool）
- [ ] http.client（可选）
- [ ] 与 std.json 集成（请求/响应 JSON 序列化）

---

## 与主待办集成

- [x] 在 [todo_mini_to_full.md](todo_mini_to_full.md) 标准库表中已增加 **38.1 std.http** 条目
