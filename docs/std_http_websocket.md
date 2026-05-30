# Uya `std.http.websocket` 使用说明

`std.http.websocket` 提供 HTTP/1.1 Upgrade WebSocket、TLS/WSS transport、JSON helper、heartbeat、reconnect wrapper 与队列/pump 能力。

## 最短路径

- 裸 HTTP:
  - `websocket_accept_from_http(fd, req, &opts)`
- UyaGin:
  - `uyagin_websocket_upgrade_sync(ctx, &opts)`
  - `@await ws.read_message(...)`
  - `@await ws.write_message(...)`
- HTTPS / WSS:
  - `websocket_accept_from_https_server(&srv, &opts)`

## 常用能力

- 协议层:
  - `read_frame(...)`
  - `write_frame(...)`
- 消息层:
  - `read_message(...)`
  - `write_message(...)`
- JSON:
  - `websocket_json_decode_value(...)`
  - `websocket_conn_write_json<T>(...)`
- 心跳:
  - `websocket_conn_heartbeat_tick(...)`
- 自动重连:
  - `websocket_client_reconnect_tick(...)`
  - `WebSocketClientConnector`
- 队列 / pump:
  - `enqueue_message(...)`
  - `flush_one_pending(...)`
  - `flush_pending(...)`
  - `shutdown_pending(...)`

## 示例

- 最小 echo:
  - [uyagin_websocket_echo.uya](../examples/uyagin_websocket_echo.uya)
- chat/session:
  - [uyagin_websocket_chat_session.uya](../examples/uyagin_websocket_chat_session.uya)
- WSS:
  - [https_websocket_echo.uya](../examples/https_websocket_echo.uya)
- JSON:
  - [uyagin_websocket_json_echo.uya](../examples/uyagin_websocket_json_echo.uya)

## 路线占位

- HTTP/2 RFC 8441 / HTTP/3 / QUIC 路线说明：
  - [std_http_websocket_http2_http3_route.md](./std_http_websocket_http2_http3_route.md)
