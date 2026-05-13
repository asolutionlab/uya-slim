# Uya HTTP WebSocket 实现待办

**参考**：[std_http_websocket_design.md](./std_http_websocket_design.md)、[todo_http.md](./todo_http.md)

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → 运行相关快速验证。  
新增测试优先覆盖纯协议层、loopback 集成和 `uyagin` upgrade 主链路。

## 范围说明

- 本页对应 `std.http.websocket` 设计稿的落地拆解。
- 本页覆盖这一版计划内能力：
  - HTTP/1.1 Upgrade WebSocket
  - HTTP/2 WebSocket（RFC 8441）
  - `std.http` 命名空间内的 HTTP/3 / QUIC WebSocket 路线
  - `uyagin` 集成
  - WebSocket over TLS transport 适配
  - JSON 消息编解码辅助 API
  - 自动重连策略
  - 自动心跳 / ping-pong 保活策略
  - 写队列、背压与后台发送模型
- 本页不把浏览器 JS/DOM 集成、跨协议网关编排作为首要交付目标。

---

## Phase 1：模块骨架与公共类型

### 1.1 模块与文件

- [ ] 新增 `lib/std/http/websocket_types.uya`
- [ ] 新增 `lib/std/http/websocket_frame.uya`
- [ ] 新增 `lib/std/http/websocket_handshake.uya`
- [ ] 新增 `lib/std/http/websocket_async.uya`
- [ ] 新增 `lib/std/http/websocket_tls.uya`
- [ ] 新增 `lib/std/http/websocket_client.uya`
- [ ] 新增 `lib/std/http/websocket_json.uya`
- [ ] 新增 `lib/std/http/uyagin_websocket.uya` 作为框架桥接层

### 1.2 错误、常量、枚举

- [ ] 定义 WebSocket 专用错误：
  - `WebSocketBadHandshake`
  - `WebSocketUnsupportedVersion`
  - `WebSocketMissingKey`
  - `WebSocketInvalidKey`
  - `WebSocketProtocolError`
  - `WebSocketFrameTooLarge`
  - `WebSocketMessageTooLarge`
  - `WebSocketNeedMoreData`
  - `WebSocketConnectionClosed`
  - `WebSocketMaskedServerFrame`
  - `WebSocketUnmaskedClientFrame`
  - `WebSocketUnsupportedOpcode`
  - `WebSocketUtf8Required`
  - `WebSocketControlFrameTooLarge`
  - `WebSocketFragmentedControlFrame`
  - `WebSocketContinuationMissing`
- [ ] 定义常量：
  - `WS_GUID`
  - `WS_MAX_HEADER_BYTES`
  - `WS_CONTROL_MAX_PAYLOAD`
- [ ] 定义枚举：
  - `WebSocketOpcode`
  - `WebSocketRole`

### 1.3 公共结构体与接口

- [ ] 定义 `WebSocketFrameView`
- [ ] 定义 `WebSocketMessageView`
- [ ] 定义 `WebSocketAcceptOptions`
- [ ] 定义 `AsyncWebSocketConn` 接口
- [ ] 定义 `WebSocketFdTransport`
- [ ] 定义 `WebSocketTlsTransport`
- [ ] 定义 `WebSocketConn`
- [ ] 定义 `WebSocketClient`
- [ ] 定义 `ReconnectPolicy`

### 1.4 测试

- [ ] 新增 `tests/test_http_websocket_types.uya`
- [ ] 覆盖错误、常量、枚举值与结构体基本初始化
- [ ] 验证接口签名与结构体方法实现的最小编译冒烟

---

## Phase 2：握手与 Upgrade

### 2.1 基础握手工具

- [ ] 实现 `websocket_request_is_upgrade(req)`
- [ ] 实现 `websocket_validate_upgrade_request(req)`
- [ ] 实现 `websocket_compute_accept(key, out, out_cap)`
- [ ] 实现 `websocket_pick_subprotocol(req, supported, supported_count)`

### 2.2 HTTP 协商细节

- [ ] 校验 `Connection: Upgrade`
- [ ] 校验 `Upgrade: websocket`
- [ ] 校验 `Sec-WebSocket-Version: 13`
- [ ] 校验 `Sec-WebSocket-Key`
- [ ] 返回 `101 Switching Protocols`
- [ ] 处理可选 `Sec-WebSocket-Protocol`
- [ ] 明确本版是否拒绝 `Sec-WebSocket-Extensions`

### 2.3 裸 HTTP 集成

- [ ] 实现 `websocket_accept_from_http(fd, req, options) !WebSocketConn`
- [ ] 明确 upgrade 成功后的 fd 所有权转移规则
- [ ] 明确 upgrade 失败时由哪一层负责返回 HTTP 错误响应

### 2.4 测试

- [ ] 新增 `tests/test_http_websocket_handshake.uya`
- [ ] 覆盖握手成功
- [ ] 覆盖缺失 `Sec-WebSocket-Key`
- [ ] 覆盖 `Sec-WebSocket-Version != 13`
- [ ] 覆盖大小写差异 header
- [ ] 覆盖 subprotocol 选择成功与失败

---

## Phase 3：frame 编解码

### 3.1 编码

- [ ] 实现 `websocket_encode_frame_header(...)`
- [ ] 实现 masking 应用函数
- [ ] 支持 text / binary / close / ping / pong / continuation 编码
- [ ] 区分 client/server mask 规则

### 3.2 解析

- [ ] 实现 `websocket_parse_frame_from_buffer(...)`
- [ ] 支持 7-bit / 16-bit / 64-bit payload 长度解析
- [ ] 支持 mask key 读取与 unmask
- [ ] 检查控制帧长度上限
- [ ] 检查控制帧 `FIN == true`
- [ ] 检查 continuation 状态合法性

### 3.3 测试

- [ ] 新增 `tests/test_http_websocket_frame.uya`
- [ ] 覆盖 text/binary frame 编解码
- [ ] 覆盖 ping/pong/close 控制帧
- [ ] 覆盖客户端未 mask 被 server 拒绝
- [ ] 覆盖服务端错误 mask 被 client 拒绝
- [ ] 覆盖长度边界 125 / 126 / 65535 / 65536
- [ ] 覆盖 continuation 错序与控制帧分片错误

---

## Phase 4：异步连接与会话主链路

### 4.1 transport

- [ ] 让 `WebSocketFdTransport` 实现 `AsyncReader` / `AsyncWriter`
- [ ] 为 transport 补 `drop` 关闭 fd
- [ ] 对齐 `MqttFdTransport` 风格，确保可直接接 event loop

### 4.2 `WebSocketConn` 基础方法

- [ ] 实现 `read_frame(...)`
- [ ] 实现 `write_frame(...)`
- [ ] 实现 `ping(...)`
- [ ] 实现 `close_with_code(...)`
- [ ] 实现 `enqueue_message(...)`
- [ ] 实现 `flush_pending(...)`
- [ ] 明确 `closed` 状态与幂等 close 语义
- [ ] 明确 caller-owned 直接写 API 与连接内 owned queue API 的边界

### 4.3 消息层方法

- [ ] 实现 `read_message(...)`
- [ ] 实现 `write_message(...)`
- [ ] 默认支持 continuation 聚合到 caller-owned `msg` 缓冲区
- [ ] 明确 `payload` 生命周期与复用规则

### 4.4 控制帧策略

- [ ] 当 `auto_pong == true` 时自动响应 ping
- [ ] 默认忽略 pong 但保留底层可观测性
- [ ] close frame 到达时进入 closed 状态并返回统一错误

### 4.5 测试

- [ ] 新增 `tests/test_http_websocket_async.uya`
- [ ] 覆盖 loopback frame 收发
- [ ] 覆盖多 frame message 聚合
- [ ] 覆盖 close 后再次读写行为
- [ ] 覆盖 auto pong
- [ ] 覆盖 enqueue/flush 最小链路

---

## Phase 5：`uyagin` Upgrade 集成

### 5.1 桥接 API

- [ ] 实现 `uyagin_websocket_upgrade(ctx, options) Future<!WebSocketConn>`
- [ ] 若拆桥接文件，则落在 `lib/std/http/uyagin_websocket.uya`
- [ ] 让 `GinContext` 在 upgrade 成功后进入“连接已接管”状态
- [ ] 禁止 upgrade 后再走普通 HTTP body/response 路径

### 5.2 业务使用体验

- [ ] 提供 echo handler 风格示例
- [ ] 提供 chat/session 风格示例
- [ ] 验证结构体 `AsyncHandler` + 结构体 `WebSocketConn` 方法组合是否顺手

### 5.3 测试

- [ ] 新增 `tests/test_http_uyagin_websocket.uya`
- [ ] 覆盖 `uyagin` route -> upgrade -> echo roundtrip
- [ ] 覆盖非 WebSocket 请求命中 upgrade handler 的失败路径
- [ ] 覆盖 upgrade 后重复写 HTTP 响应的防呆

---

## Phase 6：TLS transport 适配

### 6.1 设计收敛

- [ ] 明确是新增 `WebSocketTlsTransport`，还是让现有抽象泛化到任意 `AsyncReader` / `AsyncWriter`
- [ ] 与 `tls.https` / 现有 TLS server 能力对齐，避免重复包装
- [ ] 明确 TLS 握手结束后如何桥接到 WebSocket upgrade

### 6.2 实现

- [ ] 支持 HTTPS 上的 WebSocket handshake
- [ ] 支持 TLS 连接上的 frame/message 读写
- [ ] 确保 transport 生命周期与 close/drop 语义一致

### 6.3 测试

- [ ] 新增 `tests/test_https_websocket_loopback.uya`
- [ ] 覆盖最小 WSS loopback handshake
- [ ] 覆盖 TLS 下 echo roundtrip

---

## Phase 7：JSON 消息辅助 API

### 7.1 API 设计

- [ ] 设计文本消息与 JSON 的关系：限定 text opcode 还是允许调用方自行指定
- [ ] 确定依赖现有 `std.json` 的 encoder / value / decoder 形式

### 7.2 实现

- [ ] 提供 `write_json(...)` 一类高层方法
- [ ] 提供 `read_json(...)` 或 “读 text + decode” 辅助方法
- [ ] 明确解码失败错误映射

### 7.3 测试

- [ ] 新增 `tests/test_http_websocket_json.uya`
- [ ] 覆盖 struct -> JSON -> text frame
- [ ] 覆盖 text frame -> JSON decode
- [ ] 覆盖非法 JSON 错误路径

---

## Phase 8：自动心跳与保活

### 8.1 策略与状态

- [ ] 为 `WebSocketConn` 增加心跳配置
- [ ] 增加 ping 间隔、pong 超时、空闲超时等参数
- [ ] 明确心跳是主动任务、被动 piggyback 还是外部调度驱动

### 8.2 实现

- [ ] 自动定期发送 ping
- [ ] 追踪最近 pong / 最近活动时间
- [ ] 超时后进入关闭流程

### 8.3 测试

- [ ] 新增 `tests/test_http_websocket_heartbeat.uya`
- [ ] 覆盖自动 ping
- [ ] 覆盖 pong 超时
- [ ] 覆盖仅业务流量存在时无需额外 ping 的策略分支

---

## Phase 9：自动重连

### 9.1 客户端侧抽象

- [ ] 明确自动重连只适用于 client role，不污染 server 侧连接对象
- [ ] 设计 `WebSocketClient` / `ReconnectPolicy` 等包装结构体
- [ ] 明确重连对外暴露的是“会话对象”还是“连接工厂”

### 9.2 策略

- [ ] 支持固定间隔 / 指数退避
- [ ] 支持最大重试次数
- [ ] 支持重连后自动重新握手
- [ ] 明确 subprotocol / header / auth 信息如何复用

### 9.3 测试

- [ ] 新增 `tests/test_http_websocket_reconnect.uya`
- [ ] 覆盖断连后重连成功
- [ ] 覆盖超过最大重试次数
- [ ] 覆盖重连期间写请求被拒绝或排队的策略

---

## Phase 10：写队列、背压与后台发送模型

### 10.1 队列模型

- [ ] 设计单生产者/多生产者边界
- [ ] 评估复用 `std.async_channel` / ring queue / 自定义固定队列
- [ ] 明确 caller-owned buffer 与后台写队列如何协作

### 10.2 背压策略

- [ ] 队列满时返回错误、阻塞等待还是丢弃旧消息
- [ ] 控制帧与业务帧优先级策略
- [ ] close frame 是否抢占发送

### 10.3 后台发送

- [ ] 增加后台 flush task / frame pump
- [ ] 保证与显式 `write_message` 行为不冲突
- [ ] 明确 shutdown 时 drain 还是直接丢弃

### 10.4 测试

- [ ] 新增 `tests/test_http_websocket_backpressure.uya`
- [ ] 覆盖队列满
- [ ] 覆盖高频发送
- [ ] 覆盖 close 与排队消息竞争

---

## Phase 11：HTTP/2 WebSocket 与 HTTP/3/QUIC 路线

### 11.1 HTTP/2 WebSocket

- [ ] 明确 RFC 8441 在现有 `std.http` 架构中的模块归属
- [ ] 设计 HTTP/2 extended CONNECT 与现有 `WebSocketConn` 的对接方式
- [ ] 评估是否复用相同 frame/message/session 层
- [ ] 新增 HTTP/2 WebSocket 测试规划

### 11.2 HTTP/3 / QUIC

- [ ] 明确 HTTP/3 / QUIC WebSocket 仍保留在 `std.http.*` 命名空间
- [ ] 设计与现有 transport / session 接口的兼容层
- [ ] 评估 QUIC stream 与当前 `AsyncReader` / `AsyncWriter` 抽象是否足够
- [ ] 新增路线文档或实现占位

### 11.3 测试与验证

- [ ] 为 HTTP/2 WebSocket 规划最小 loopback / compile 级验证
- [ ] 为 HTTP/3 / QUIC 路线规划编译级或接口一致性验证

---

## Phase 12：示例、基准与文档收口

### 12.1 示例

- [ ] 新增最小 echo 示例
- [ ] 新增 `uyagin` chat/broadcast 示例
- [ ] 新增 WSS 示例
- [ ] 新增 JSON 消息示例

### 12.2 基准

- [ ] 新增 WebSocket echo benchmark
- [ ] 记录明文 WS 与 TLS WSS 的基线
- [ ] 如有对照组，可补 Go websocket benchmark

### 12.3 文档同步

- [ ] 在 `std_http_websocket_design.md` 中回填实现决策
- [ ] 视实现成熟度新增 `docs/std_http_websocket.md` 用户文档
- [ ] 评估是否在 `docs/todo_http.md` 增加 WebSocket 子条目或跳转链接

---

## 建议实施顺序

1. Phase 1：模块骨架与公共类型  
2. Phase 2：握手与 Upgrade  
3. Phase 3：frame 编解码  
4. Phase 4：异步连接与会话主链路  
5. Phase 5：`uyagin` Upgrade 集成  
6. Phase 6：TLS transport 适配  
7. Phase 7：JSON 消息辅助 API  
8. Phase 8：自动心跳与保活  
9. Phase 9：自动重连  
10. Phase 10：写队列、背压与后台发送模型  
11. Phase 11：HTTP/2 WebSocket 与 HTTP/3/QUIC 路线  
12. Phase 12：示例、基准与文档收口
