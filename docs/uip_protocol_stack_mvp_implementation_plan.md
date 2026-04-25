# UIP 协议栈 MVP 实现计划

> 基于 Uya 实现 Unified IP Protocol Stack  
> 目标：分层、可裁剪、第一版可运行

---

## 一、目标范围

本轮 MVP 只做：

- UIP 固定帧头
- wire encode/decode
- IPv4 DNS 解析封装
- TCP client/server 基础
- request/response
- ping/pong
- 基础测试

本轮不做：

- TLS / DTLS
- UDP transport
- async client/server
- Protobuf codec
- 自动重连
- 多路复用

---

## 二、文件规划

### 新增模块文件

```
lib/std/uip/
  errors.uya    — UIP 域错误定义
  types.uya     — 常量、公共结构体、默认配置
  wire.uya      — 大端序读写、header/frame encode/decode
  resolver.uya   — DNS 解析封装
  tcp.uya       — TCP socket connect/listen/accept、frame 收发
  session.uya   — request_id 管理、request/response helper、ping/pong
  uip.uya       — 统一 re-export 出口
```

### 新增测试文件

```
tests/test_std_uip_wire.uya   — wire 编解码纯逻辑测试
tests/test_std_uip_tcp.uya    — loopback TCP 联调测试
```

---

## 三、分文件实现内容

### 1. `lib/std/uip/errors.uya`

**职责：** 定义 UIP 域错误，隔离底层 errno。

```uya
// lib/std/uip/errors.uya

export error UipInvalidMagic;
export error UipUnsupportedVersion;
export error UipInvalidFlags;
export error UipInvalidCodec;
export error UipInvalidFrame;
export error UipMessageTooLarge;
export error UipChecksumMismatch;
export error UipTimeout;
export error UipConnectionClosed;
export error UipResolveFailed;
export error UipTransportError;
export error UipUnsupportedTransport;
export error UipRequestIdMismatch;
```

> **说明：** 不把底层 errno 直接暴露给上层业务。所有 TCP/DNS 层错误映射到 UIP 语义错误。

---

### 2. `lib/std/uip/types.uya`

**职责：** 常量、公共结构体、默认配置函数。

#### 2.1 常量

```uya
// 协议版本与长度
export const UIP_VERSION: u8 = 1;
export const UIP_HEADER_LEN: usize = 24;
export const UIP_DEFAULT_MAX_BODY_LEN: usize = 65536;

// codec 类型
export const UIP_CODEC_RAW: u8 = 0;
export const UIP_CODEC_JSON: u8 = 1;
export const UIP_CODEC_PROTOBUF: u8 = 2;

// flags 位定义
export const UIP_FLAG_REQUEST: u8 = 0x01;
export const UIP_FLAG_RESPONSE: u8 = 0x02;
export const UIP_FLAG_ONEWAY: u8 = 0x04;
export const UIP_FLAG_HEARTBEAT: u8 = 0x08;
export const UIP_FLAG_ERROR: u8 = 0x10;

// 内置消息类型
export const UIP_MSG_HELLO: u16 = 0x0001;
export const UIP_MSG_PING: u16 = 0x0002;
export const UIP_MSG_PONG: u16 = 0x0003;
export const UIP_MSG_ERROR: u16 = 0x0004;
export const UIP_MSG_EVENT: u16 = 0x0005;
```

#### 2.2 结构体

```uya
// UIP 帧头（内存布局与 wire 格式一一对应，共 24 字节）
export struct UipHeader {
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body_len: u32,
    checksum: u32,
    reserved: u32,
}

// 解析后的完整消息
export struct UipMessage {
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body_len: u32,
    checksum: u32,
    body: &[byte],
}

// 全局配置
export struct UipConfig {
    max_body_len: usize,
    timeout_ms: u32,
    heartbeat_ms: u32,
    enable_checksum: bool,
}
```

#### 2.3 默认配置

```uya
export fn uip_default_config() UipConfig {
    return UipConfig{
        max_body_len: UIP_DEFAULT_MAX_BODY_LEN,
        timeout_ms: 5000,
        heartbeat_ms: 30000,
        enable_checksum: true,
    };
}
```

---

### 3. `lib/std/uip/wire.uya`

**职责：** 大端序读写、帧头编解码、帧编解码、flags/codec 校验、checksum 校验。

#### 3.1 内部辅助函数

```uya
// 大端序读写
fn uip_write_u16_be(out: &byte, pos: usize, v: u16) usize;
fn uip_write_u32_be(out: &byte, pos: usize, v: u32) usize;
fn uip_read_u16_be(in: &const byte, pos: usize) u16;
fn uip_read_u32_be(in: &const byte, pos: usize) u32;

// body 复制
fn uip_copy_body(dst: &byte, src: &[byte]) void;

// flags/codec 合法性校验
fn uip_validate_flags(flags: u8) bool;
fn uip_validate_codec(codec: u8) bool;
```

#### 3.2 导出函数

```uya
// 编码帧头到 out，返回写入字节数（固定 24）
export fn uip_encode_header(
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body_len: u32,
    checksum: u32,
    out: &byte
) !void;

// 解码帧头，成功返回 UipHeader，失败返回 UIP 错误
export fn uip_decode_header(in: &const byte, in_len: usize) !UipHeader;

// 编码完整帧（header + body）
// out_len 必须 >= UIP_HEADER_LEN + body_len
// 返回总帧长
export fn uip_encode_message(
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body: &[byte],
    cfg: &UipConfig,
    out: &byte,
    out_len: usize
) !usize;

// 解码完整帧（先读 header，再读 body）
// 返回 UipMessage，body slice 指向内部 buffer
export fn uip_decode_message(
    hdr_buf: &const byte,
    hdr_len: usize,
    body_buf: &const byte,
    body_len: usize,
    cfg: &UipConfig
) !UipMessage;
```

#### 3.3 校验规则

**`uip_decode_header` 必须校验：**

| 步骤 | 检查项 | 失败时返回 |
|---|---|---|
| 1 | `in_len >= UIP_HEADER_LEN` | `UipInvalidFrame` |
| 2 | magic 前3字节 == "UIP" | `UipInvalidMagic` |
| 3 | version == UIP_VERSION | `UipUnsupportedVersion` |
| 4 | flags 合法性 | `UipInvalidFlags` |
| 5 | codec 合法性（0/1/2） | `UipInvalidCodec` |
| 6 | request_id / body_len 不溢出 | `UipInvalidFrame` |

**`uip_decode_message` 必须校验：**

| 步骤 | 检查项 | 失败时返回 |
|---|---|---|
| 1 | decode header 成功 | 继承 header 错误 |
| 2 | `body_len <= cfg.max_body_len` | `UipMessageTooLarge` |
| 3 | `body_len == 实际 body_len` | `UipInvalidFrame` |
| 4 | checksum 匹配（如果开启） | `UipChecksumMismatch` |

#### 3.4 checksum 实现

```uya
// 复用 lib/std/crypto/crc32.uya
use std.crypto.crc32;

fn uip_calc_checksum(body: &[byte]) u32 {
    if body.len == 0 {
        return 0;
    }
    return crc32_crc32(body);
}
```

> **明确不做：** header 扩展、分片、压缩。

---

### 4. `lib/std/uip/resolver.uya`

**职责：** 封装 `std.net.dns`，对上层屏蔽 DNS 细节，提供统一的 IPv4 解析接口。

#### 4.1 依赖

```uya
use std.net.dns;
```

#### 4.2 结构体

```uya
export struct UipResolver {
    dns: DnsClient,
}
```

#### 4.3 导出函数

```uya
// 初始化 resolver，可指定 nameserver（如 "8.8.8.8"）
// nameserver 为空则从 /etc/resolv.conf 读取
export fn uip_resolver_init(resolver: &UipResolver, nameserver: &[byte]) void {
    dns_client_init(&resolver.dns, nameserver);
}

// 设置查询超时（毫秒）
export fn uip_resolver_set_timeout_ms(resolver: &UipResolver, timeout_ms: u32) void {
    dns_client_set_timeout_ms(&resolver.dns, timeout_ms);
}

// 解析主机名，返回第一个 IPv4 地址到 out[0..4]
// out_len_out 返回实际写入字节数（固定为 4）
// 失败返回 UipResolveFailed
export fn uip_resolve_first_ipv4(
    resolver: &UipResolver,
    host: &[byte],
    out: &byte,
    out_len_out: &usize
) !usize;
```

#### 4.4 实现要点

- 内部调用 `dns_client_resolve_first_ipv4`
- DNS 错误统一映射为 `UipResolveFailed`
- 支持传入空 `nameserver` 走系统默认 resolver

---

### 5. `lib/std/uip/tcp.uya`

**职责：** TCP socket connect / listen / accept、frame 读写、conn / server 封装。

#### 5.1 依赖

```uya
use libc.syscall;
use std.uip.errors;
use std.uip.types;
use std.uip.wire;
use std.uip.resolver;
```

#### 5.2 结构体

```uya
// TCP 连接
export struct UipTcpConn {
    fd: i32,
    config: UipConfig,
}

// TCP 客户端配置
export struct UipTcpClientConfig {
    host: &[byte],
    port: u16,
    nameserver: &[byte],
    timeout_ms: u32,
    max_body_len: usize,
}

// TCP 服务端配置
export struct UipTcpServerConfig {
    port: u16,
    backlog: i32,
    timeout_ms: u32,
    max_body_len: usize,
}

// TCP 服务端
export struct UipTcpServer {
    fd: i32,
    config: UipConfig,
}
```

#### 5.3 内部辅助函数

```uya
fn uip_fill_sockaddr_ipv4(a: byte, b: byte, c: byte, d: byte, port: u16, out: &byte) void {
    // sockaddr_in 布局：
    // offset 0:  sin_family = AF_INET (2)
    // offset 2:  sin_port   (big-endian)
    // offset 4:  sin_addr   (4 bytes)
    // offset 8:  sin_zero   (8 bytes zero)
    // 总长度 16 字节
    // 参照 dns.uya:fill_sockaddr_ipv4 和 http1_async.uya:fill_sockaddr_ipv4 的实现风格
}

fn uip_tcp_set_reuseaddr(fd: i32) !void;
fn uip_tcp_set_timeouts(fd: i32, timeout_ms: u32) !void;

// 同步读 exactly len 字节，失败视为连接关闭
fn uip_tcp_read_exact(fd: i32, out: &byte, len: usize) !void;

// 同步写 exactly len 字节
fn uip_tcp_write_all(fd: i32, data: &const byte, len: usize) !void;
```

#### 5.4 客户端导出函数

```uya
// 建立到 host:port 的 TCP 连接
// 内部完成 DNS 解析 + socket + connect
export fn uip_tcp_connect(cfg: &UipTcpClientConfig) !UipTcpConn;

// 关闭连接
export fn uip_tcp_close(conn: &UipTcpConn) void;
```

#### 5.5 服务端导出函数

```uya
// 监听 port，返回 server
export fn uip_tcp_server_listen(cfg: &UipTcpServerConfig) !UipTcpServer;

// 接受一个连接，返回 conn
export fn uip_tcp_server_accept(server: &UipTcpServer) !UipTcpConn;

// 关闭服务端
export fn uip_tcp_server_close(server: &UipTcpServer) void;
```

#### 5.6 帧读写导出函数

```uya
// 将 message 编码后发送
// tx_buf: 编码用 buffer，容量至少 UIP_HEADER_LEN + body_len
// 返回发送的总字节数
export fn uip_tcp_write_message(
    conn: &UipTcpConn,
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body: &[byte],
    tx_buf: &byte,
    tx_cap: usize
) !usize;

// 读取一个帧：先读 24 字节 header，再读 body
// hdr_buf: 接收 header，容量 >= 24
// body_buf: 接收 body，容量 >= cfg.max_body_len
// 返回解析后的 UipMessage
export fn uip_tcp_read_message(
    conn: &UipTcpConn,
    hdr_buf: &byte,
    hdr_cap: usize,
    body_buf: &byte,
    body_cap: usize
) !UipMessage;
```

#### 5.7 `uip_tcp_connect` 流程

```
1. uip_resolver_init + uip_resolve_first_ipv4(host) -> ipv4[4]
2. sys_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) -> fd
3. uip_fill_sockaddr_ipv4(ipv4, port) -> addr[16]
4. uip_tcp_set_timeouts(fd, timeout_ms)
5. sys_connect(fd, addr, 16) -> 忽略 EINPROGRESS（同步场景直接等）
6. return UipTcpConn{ fd, config }
```

#### 5.8 `uip_tcp_server_listen` 流程

```
1. sys_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) -> fd
2. uip_tcp_set_reuseaddr(fd)
3. bind 0.0.0.0:port
4. sys_listen(fd, backlog)
5. return UipTcpServer{ fd, config }
```

#### 5.9 `uip_tcp_read_message` 关键实现

```
1. read_exact(fd, hdr_buf, 24)
2. uip_decode_header(hdr_buf, 24) -> header
3. 检查 header.body_len <= body_cap，否则 UipMessageTooLarge
4. read_exact(fd, body_buf, header.body_len)
5. uip_decode_message(hdr_buf, 24, body_buf, header.body_len, &cfg) -> message
6. return message
```

> **注意：** 第 5 步 `uip_decode_message` 的 hdr_buf 传入是为了方便 flags/codec 校验，但 checksum 校验基于 body_buf 中的实际 body 数据。

---

### 6. `lib/std/uip/session.uya`

**职责：** request_id 管理、request/response 对话、ping/pong helper。

#### 6.1 依赖

```uya
use std.uip.errors;
use std.uip.types;
use std.uip.wire;
use std.uip.tcp;
```

#### 6.2 结构体

```uya
export struct UipSession {
    conn: UipTcpConn,
    next_request_id: u32,
}
```

#### 6.3 导出函数

```uya
// 初始化 session，request_id 从 1 开始
export fn uip_session_init(session: &UipSession, conn: UipTcpConn) void {
    session.conn = conn;
    session.next_request_id = 1;
}

// 关闭底层连接
export fn uip_session_close(session: &UipSession) void {
    uip_tcp_close(&session.conn);
}

// 分配并返回下一个 request_id，0 留给 heartbeat/oneway
export fn uip_session_next_id(session: &UipSession) u32 {
    const id: u32 = session.next_request_id;
    session.next_request_id = session.next_request_id + 1;
    return id;
}

// 单次请求：发送 request，读取 response，校验 id
// tx_buf: 编码 buffer
// rx_hdr_buf: 读 header 用
// rx_body_buf: 读 body 用
export fn uip_session_request(
    session: &UipSession,
    msg_type: u16,
    codec: u8,
    body: &[byte],
    tx_buf: &byte,
    tx_cap: usize,
    rx_hdr_buf: &byte,
    rx_hdr_cap: usize,
    rx_body_buf: &byte,
    rx_body_cap: usize
) !UipMessage;

// 发送 ping（单向，不等待 pong）
export fn uip_session_send_ping(
    session: &UipSession,
    tx_buf: &byte,
    tx_cap: usize
) !void;

// 发送 pong（响应 ping）
export fn uip_session_send_pong(
    session: &UipSession,
    request_id: u32,
    tx_buf: &byte,
    tx_cap: usize
) !void;
```

#### 6.4 `uip_session_request` 流程

```
1. id = uip_session_next_id()
2. flags = UIP_FLAG_REQUEST
3. uip_tcp_write_message(conn, flags, codec, msg_type, id, body, tx_buf, tx_cap) -> 发送字节数
4. uip_tcp_read_message(conn, rx_hdr_buf, rx_hdr_cap, rx_body_buf, rx_body_cap) -> resp
5. 检查 resp.flags 包含 UIP_FLAG_RESPONSE
6. 检查 resp.request_id == id
7. return resp
```

#### 6.5 `uip_session_send_ping` 流程

```
1. body = 空 slice
2. uip_tcp_write_message(conn, UIP_FLAG_HEARTBEAT | UIP_FLAG_ONEWAY, UIP_CODEC_RAW, UIP_MSG_PING, 0, body, tx_buf, tx_cap)
```

---

### 7. `lib/std/uip/uip.uya`

**职责：** 统一 re-export 出口，聚合所有子模块。

```uya
// lib/std/uip/uip.uya

// 统一导出所有子模块
pub use std.uip.errors;
pub use std.uip.types;
pub use std.uip.wire;
pub use std.uip.resolver;
pub use std.uip.tcp;
pub use std.uip.session;
```

> 若 uya 不支持 `pub use`，则按项目现有风格用单独的 `export` 或 `use` 再 re-export。

---

## 四、测试计划

### 1. `tests/test_std_uip_wire.uya`

**目标：** 只测纯协议编解码逻辑，不涉及网络。

#### 测试用例

| 用例 | 输入 | 期望 |
|---|---|---|
| 1 | encode `REQUEST, RAW, msg_type=0x0101, body="hello"`，再 decode | 所有字段一致 |
| 2 | encode empty body (len=0, checksum=0)，再 decode | body_len=0，body 为空 slice |
| 3 | 改 magic 第0字节，decode | `UipInvalidMagic` |
| 4 | 改 version != 1，decode | `UipUnsupportedVersion` |
| 5 | 同时置 request+response flags，decode | `UipInvalidFlags` |
| 6 | codec = 99，decode | `UipInvalidCodec` |
| 7 | encode 后篡改 body，decode | `UipChecksumMismatch` |
| 8 | header.body_len > max_body_len，decode | `UipMessageTooLarge` |
| 9 | 读取长度不足 24 字节 | `UipInvalidFrame` |

> **实现提示：** 测试中通过直接操作 byte buffer 构造各种边界数据，不需要真实 socket。

---

### 2. `tests/test_std_uip_tcp.uya`

**目标：** loopback 联调，测 TCP + wire 协作。

#### 测试用例

**前置通用逻辑（复用）：**

```uya
// 启动一个 TCP server 在随机端口
fn start_server(handler: fn (fd: i32) !void) !i32 {
    const fd: i32 = try sys_socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    setsockopt SO_REUSEADDR
    bind 0.0.0.0:0 -> 获取随机端口
    listen 5
    在后台线程 accept -> handler(fd)
    return port
}
```

| 用例 | 描述 | 期望 |
|---|---|---|
| 1 | 客户端 connect，发送 `REQUEST body="hello"`，服务端 echo `RESPONSE body="world"` | 客户端收到 status ok，body="world" |
| 2 | 客户端发送 `PING`（oneway），不等待响应 | 发送成功 |
| 3 | 服务端收到 PING，返回 `PONG` | 客户端收到 PONG |
| 4 | 服务端返回 response 但 request_id 不匹配 | 客户端检测到 `UipRequestIdMismatch` |
| 5 | 服务端返回 body_len > 客户端 body_cap | 客户端收到 `UipMessageTooLarge` |
| 6 | 服务端关闭连接，客户端读 | `UipConnectionClosed` |

---

## 五、实现顺序

```
Step 1:  lib/std/uip/errors.uya
Step 2:  lib/std/uip/types.uya
Step 3:  lib/std/uip/wire.uya
Step 4:  tests/test_std_uip_wire.uya          ← 验证协议格式
Step 5:  lib/std/uip/resolver.uya
Step 6:  lib/std/uip/tcp.uya
Step 7:  lib/std/uip/session.uya
Step 8:  lib/std/uip/uip.uya
Step 9:  tests/test_std_uip_tcp.uya          ← 验证 TCP + wire 协作
```

> **关键约束：** Step 3 完成后必须先补 `test_std_uip_wire.uya`，确保协议格式打稳再进入 TCP 层。TCP 层的问题排查成本远高于 wire 层。

---

## 六、关键实现决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 帧头长度 | 固定 24 字节 | 简单、便于同步读取、避免 TLV 复杂度 |
| 字节序 | big-endian | 网络协议惯例，与现有 DNS 风格一致 |
| IP 版本 | 仅 IPv4 | sockaddr_in 成熟，避免 sockaddr_in6 扩展 |
| TCP decode 策略 | 先读 header 再读 body，不要求整帧连续 buffer | 更适合 socket 读法，降低内存拷贝 |
| 服务端并发 | 同步串行 | MVP 优先，易测试、易调试 |
| checksum | CRC32 | 仓库已有 lib/std/crypto/crc32.uya |
| 错误策略 | UIP 语义错误隔离底层 errno | 上层业务不感知 socket 细节 |

---

## 七、风险点与应对

| 风险 | 描述 | 应对 |
|---|---|---|
| R1 | `UipMessage.body` 指向 body buffer，需保证返回后 buffer 仍有效 | 调用方提供 `rx_body_buf`，message 仅借用该 buffer |
| R2 | 错误映射风格不一致（透传 vs 转换） | 统一原则：wire 层用 UIP 错误；TCP 层转 `UipTransportError` / `UipConnectionClosed`；resolver 层转 `UipResolveFailed` |
| R3 | timeout 跨平台差异（SO_RCVTIMEO/SO_SNDTIMEO） | 第一版仅 best-effort，测试以 loopback 为主，不依赖严格超时 |
| R4 | request_id 溢出 | 到达 u32::MAX 后回绕到 1（跳过 0） |
| R5 | body_len = 0 时 checksum 行为 | 定义为 checksum = 0，encode/decode 均遵守 |

---

## 八、验收标准

### wire 层
- [ ] 所有 9 个 test_std_uip_wire.uya 测试用例通过
- [ ] magic/version/flags/codec 校验路径覆盖完整
- [ ] checksum 计算正确（对比已知 CRC32 值）

### TCP 层
- [ ] loopback request/response 往返正确
- [ ] ping/pong 往返正确
- [ ] request_id mismatch 可被检测
- [ ] oversized body 可被拒绝
- [ ] 连接关闭后读返回 `UipConnectionClosed`

### 代码质量
- [ ] `std.uip` 可作为独立模块使用
- [ ] 不污染现有 `std.http` / `std.net.dns` 模块
- [ ] 所有 export 函数有文档注释

---

## 九、协议帧格式速查

```
Offset  Size  Field        Description
------  ----  -----------  ------------------------------
  0       3   magic        固定 "UIP" (0x55 0x49 0x50)
  3       1   version      协议版本，当前为 1
  4       1   flags        请求/响应/心跳/错误标志位
  5       1   codec       负载编码：0=raw, 1=json, 2=protobuf
  6       2   msg_type    消息类型（big-endian）
  8       4   request_id  请求 ID（big-endian）
 12       4   body_len    body 长度（big-endian）
 16       4   checksum    body CRC32（body 为空时=0）
 20       4   reserved    保留，必须为 0

Header:  24 bytes (fixed)
Body:    variable, max 65536 bytes
Total:   24 + body_len bytes
```

---

## 十、模块依赖图

```
                    test_std_uip_wire.uya
                              |
                              v
              +---------------+---------------+
              |               |               |
           errors.uya    types.uya        wire.uya
              ^               ^               ^
              |               |               |
              +---------------+---------------+
                              |
                    uip.uya  (re-export all)
                              |
          +-------------------+-------------------+
          |                   |                   |
    resolver.uya           tcp.uya           session.uya
          ^                   ^                   ^
          |                   |                   |
          |           +--------+--------+         |
          |           |                 |         |
          |      sys_socket          sys_connect  |
          |           |                 |         |
          +----> dns_client_resolve    |         |
                                      v         v
                              libc.syscall.uya
```
