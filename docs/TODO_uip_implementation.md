# UIP 协议栈 MVP - 详细实现清单

> 基于 `docs/uip_protocol_stack_mvp_implementation_plan.md` 生成  
> 目标：分层、可裁剪、第一版可运行

---

## 实现顺序总览

```
Step 1:  errors.uya      → 基础错误定义
Step 2:  types.uya        → 常量、结构体、配置
Step 3:  wire.uya         → 协议编解码（关键路径）
Step 4:  test_wire.uya    → 验证 wire 层
Step 5:  resolver.uya     → DNS 封装
Step 6:  tcp.uya          → TCP socket 封装
Step 7:  session.uya      → session 管理
Step 8:  uip.uya          → 统一导出
Step 9:  test_tcp.uya     → TCP 联调测试
```

---

## Step 1: `lib/std/uip/errors.uya`

### 职责
定义 UIP 域错误，隔离底层 errno。

### 详细设计

#### 错误列表

| 错误名 | 用途 | 触发场景 |
|--------|------|----------|
| `UipInvalidMagic` | magic 校验失败 | header 前3字节 != "UIP" |
| `UipUnsupportedVersion` | 版本不支持 | version != 1 |
| `UipInvalidFlags` | flags 非法 | 同时设置 REQUEST + RESPONSE |
| `UipInvalidCodec` | codec 非法 | codec 不在 [0,1,2] |
| `UipInvalidFrame` | 帧格式错误 | 长度不足、溢出等 |
| `UipMessageTooLarge` | body 过大 | body_len > max_body_len |
| `UipChecksumMismatch` | 校验和不匹配 | CRC32 不一致 |
| `UipTimeout` | 操作超时 | connect/read/write 超时 |
| `UipConnectionClosed` | 连接关闭 | peer 关闭连接 |
| `UipResolveFailed` | DNS 解析失败 | 无法解析主机名 |
| `UipTransportError` | 传输层错误 | socket 操作失败 |
| `UipUnsupportedTransport` | 不支持的传输层 | 尝试使用 UDP 等 |
| `UipRequestIdMismatch` | request_id 不匹配 | response id 与请求不一致 |

### 实现步骤

- [x] 1. 创建 `lib/std/uip/` 目录结构
- [x] 2. 定义 13 个 export error 类型
- [x] 3. 添加模块级文档注释
- [x] 4. 检查与现有错误定义风格的一致性

### 代码模板

```uya
// lib/std/uip/errors.uya
// UIP 协议栈错误定义

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

### 测试用例

| 用例 | 描述 | 预期 |
|------|------|------|
| TC-ERR-01 | 验证所有错误类型可被 import | 编译通过 |
| TC-ERR-02 | 验证错误可被 try-catch 捕获 | 正确匹配错误类型 |

---

## Step 2: `lib/std/uip/types.uya`

### 职责
常量、公共结构体、默认配置函数。

### 详细设计

#### 2.1 常量定义

**协议版本与长度：**
```uya
const UIP_VERSION: u8 = 1;           // 协议版本
const UIP_HEADER_LEN: usize = 24;    // 固定帧头长度
const UIP_DEFAULT_MAX_BODY_LEN: usize = 65536;  // 默认最大 body
```

**Codec 类型：**
```uya
const UIP_CODEC_RAW: u8 = 0;         // 原始字节
const UIP_CODEC_JSON: u8 = 1;        // JSON 编码
const UIP_CODEC_PROTOBUF: u8 = 2;    // Protobuf 编码（预留）
```

**Flags 位定义：**
```uya
const UIP_FLAG_REQUEST: u8 = 0x01;     // 请求
const UIP_FLAG_RESPONSE: u8 = 0x02;     // 响应
const UIP_FLAG_ONEWAY: u8 = 0x04;       // 单向（无响应）
const UIP_FLAG_HEARTBEAT: u8 = 0x08;    // 心跳
const UIP_FLAG_ERROR: u8 = 0x10;        // 错误响应
```

**内置消息类型：**
```uya
const UIP_MSG_HELLO: u16 = 0x0001;
const UIP_MSG_PING: u16 = 0x0002;
const UIP_MSG_PONG: u16 = 0x0003;
const UIP_MSG_ERROR: u16 = 0x0004;
const UIP_MSG_EVENT: u16 = 0x0005;
```

#### 2.2 结构体设计

**UipHeader（内存布局与 wire 格式一一对应）：**

| 字段 | 类型 | 偏移 | 大小 | 说明 |
|------|------|------|------|------|
| magic | implicit "UIP" | 0 | 3 | 固定标识 |
| version | u8 | 3 | 1 | 版本号 |
| flags | u8 | 4 | 1 | 标志位 |
| codec | u8 | 5 | 1 | 编码类型 |
| msg_type | u16 | 6 | 2 | 消息类型 BE |
| request_id | u32 | 8 | 4 | 请求ID BE |
| body_len | u32 | 12 | 4 | body长度 BE |
| checksum | u32 | 16 | 4 | CRC32 BE |
| reserved | u32 | 20 | 4 | 保留字段 |

**UipMessage（解析后的完整消息）：**
```uya
export struct UipMessage {
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body_len: u32,
    checksum: u32,
    body: &[byte],        // 指向调用方提供的 buffer
}
```

**UipConfig（全局配置）：**
```uya
export struct UipConfig {
    max_body_len: usize,   // 最大 body 长度
    timeout_ms: u32,       // 超时时间（毫秒）
    heartbeat_ms: u32,     // 心跳间隔（毫秒）
    enable_checksum: bool, // 是否启用校验
}
```

### 实现步骤

- [x] 1. 依赖 errors.uya
- [x] 2. 定义所有常量（协议版本、codec、flags、msg_type）
- [x] 3. 定义 UipHeader 结构体（24字节内存布局）
- [x] 4. 定义 UipMessage 结构体
- [x] 5. 定义 UipConfig 结构体
- [x] 6. 实现 `uip_default_config()` 函数，返回默认配置

### 代码模板

```uya
// lib/std/uip/types.uya
use std.uip.errors;

export const UIP_VERSION: u8 = 1;
export const UIP_HEADER_LEN: usize = 24;
export const UIP_DEFAULT_MAX_BODY_LEN: usize = 65536;

export const UIP_CODEC_RAW: u8 = 0;
export const UIP_CODEC_JSON: u8 = 1;
export const UIP_CODEC_PROTOBUF: u8 = 2;

export const UIP_FLAG_REQUEST: u8 = 0x01;
export const UIP_FLAG_RESPONSE: u8 = 0x02;
export const UIP_FLAG_ONEWAY: u8 = 0x04;
export const UIP_FLAG_HEARTBEAT: u8 = 0x08;
export const UIP_FLAG_ERROR: u8 = 0x10;

export const UIP_MSG_HELLO: u16 = 0x0001;
export const UIP_MSG_PING: u16 = 0x0002;
export const UIP_MSG_PONG: u16 = 0x0003;
export const UIP_MSG_ERROR: u16 = 0x0004;
export const UIP_MSG_EVENT: u16 = 0x0005;

export struct UipHeader { ... }
export struct UipMessage { ... }
export struct UipConfig { ... }

export fn uip_default_config() UipConfig { ... }
```

### 测试用例

| 用例 | 描述 | 预期 |
|------|------|------|
| TC-TYP-01 | 验证常量值正确 | UIP_VERSION == 1, UIP_HEADER_LEN == 24 |
| TC-TYP-02 | 验证 UipHeader 内存大小 | sizeof(UipHeader) == 24 |
| TC-TYP-03 | 验证 uip_default_config() 返回值 | max_body_len == 65536, heartbeat_ms == 30000 |
| TC-TYP-04 | 验证 flags 可组合 | UIP_FLAG_REQUEST \| UIP_FLAG_ONEWAY = 0x05 |

---

## Step 3: `lib/std/uip/wire.uya`

### 职责
大端序读写、header/frame encode/decode、checksum 校验。

### 详细设计

#### 3.1 内部辅助函数

**大端序读写：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_write_u16_be` | `(out: &byte, pos: usize, v: u16) usize` | 写 u16 大端序，返回写入后位置 |
| `uip_write_u32_be` | `(out: &byte, pos: usize, v: u32) usize` | 写 u32 大端序 |
| `uip_read_u16_be` | `(in: &const byte, pos: usize) u16` | 读 u16 大端序 |
| `uip_read_u32_be` | `(in: &const byte, pos: usize) u32` | 读 u32 大端序 |

**内存操作：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_copy_body` | `(dst: &byte, src: &[byte]) void` | 复制 body 数据 |
| `uip_fill_magic` | `(out: &byte) void` | 填充 magic "UIP" |

**校验函数：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_validate_flags` | `(flags: u8) bool` | 校验 flags 合法性 |
| `uip_validate_codec` | `(codec: u8) bool` | 校验 codec 合法性 |

#### 3.2 导出函数

```uya
// 编码帧头（固定 24 字节）
export fn uip_encode_header(
    flags: u8,
    codec: u8,
    msg_type: u16,
    request_id: u32,
    body_len: u32,
    checksum: u32,
    out: &byte
) !void;

// 解码帧头
export fn uip_decode_header(in: &const byte, in_len: usize) !UipHeader;

// 编码完整帧（header + body）
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

// 解码完整帧
export fn uip_decode_message(
    hdr_buf: &const byte,
    hdr_len: usize,
    body_buf: &const byte,
    body_len: usize,
    cfg: &UipConfig
) !UipMessage;
```

#### 3.3 校验规则

**`uip_decode_header` 校验表：**

| 步骤 | 检查项 | 失败返回 |
|------|--------|----------|
| 1 | in_len >= 24 | UipInvalidFrame |
| 2 | magic[0..3] == "UIP" (0x55 0x49 0x50) | UipInvalidMagic |
| 3 | version == 1 | UipUnsupportedVersion |
| 4 | uip_validate_flags(flags) | UipInvalidFlags |
| 5 | uip_validate_codec(codec) | UipInvalidCodec |
| 6 | body_len <= max_body_len | UipMessageTooLarge |

**`uip_validate_flags` 规则：**
- REQUEST (0x01) 和 RESPONSE (0x02) 不能同时置位
- HEARTBEAT (0x08) 可与 ONEWAY (0x04) 组合
- ERROR (0x10) 通常与 RESPONSE (0x02) 组合

**`uip_validate_codec` 规则：**
- 只允许 0 (RAW)、1 (JSON)、2 (Protobuf)

#### 3.4 Checksum 实现

```uya
use std.crypto.crc32;

fn uip_calc_checksum(body: &[byte]) u32 {
    if body.len == 0 {
        return 0;
    }
    return crc32_crc32(body);
}
```

### 实现步骤

- [x] 1. 依赖 errors.uya, types.uya
- [x] 2. 实现 `uip_write_u16_be` / `uip_write_u32_be`
- [x] 3. 实现 `uip_read_u16_be` / `uip_read_u32_be`
- [x] 4. 实现 `uip_fill_magic` 填充 "UIP"
- [x] 5. 实现 `uip_copy_body` 内存复制
- [x] 6. 实现 `uip_validate_flags` 校验
- [x] 7. 实现 `uip_validate_codec` 校验
- [x] 8. 实现 `uip_calc_checksum` 调用 crc32
- [x] 9. 实现 `uip_encode_header` 编码帧头
- [x] 10. 实现 `uip_decode_header` 解码帧头（含所有校验）
- [x] 11. 实现 `uip_encode_message` 编码完整帧
- [x] 12. 实现 `uip_decode_message` 解码完整帧（含 checksum）

### 测试用例

| 用例 | 描述 | 输入 | 预期 |
|------|------|------|------|
| TC-WIRE-01 | encode/decode 往返 | REQUEST, RAW, msg_type=0x0101, body="hello" | 所有字段一致 |
| TC-WIRE-02 | 空 body | body="" | body_len=0, checksum=0 |
| TC-WIRE-03 | invalid magic | 改 magic[0] = 0x00 | UipInvalidMagic |
| TC-WIRE-04 | invalid version | version = 2 | UipUnsupportedVersion |
| TC-WIRE-05 | invalid flags | 同时置 0x01\|0x02 | UipInvalidFlags |
| TC-WIRE-06 | invalid codec | codec = 99 | UipInvalidCodec |
| TC-WIRE-07 | checksum mismatch | encode 后篡改 body | UipChecksumMismatch |
| TC-WIRE-08 | body too large | body_len > max_body_len | UipMessageTooLarge |
| TC-WIRE-09 | truncated header | in_len = 10 | UipInvalidFrame |
| TC-WIRE-10 | 大端序读写正确 | 写入 u32=0x12345678 | 读出 0x12345678 |
| TC-WIRE-11 | 不同 msg_type 编码 | msg_type=0xFFFF | 正确编码为 BE |

---

## Step 4: `tests/test_std_uip_wire.uya`

### 职责
验证 wire 层编解码逻辑，不涉及网络。

### 测试用例详解

| 用例 | 测试函数 | 测试逻辑 |
|------|----------|----------|
| TC-WIRE-01 | `test_encode_decode_roundtrip` | encode 后 decode，验证字段一致性 |
| TC-WIRE-02 | `test_empty_body` | body=""，验证 body_len=0, checksum=0 |
| TC-WIRE-03 | `test_invalid_magic` | 修改 magic 字节，验证返回 UipInvalidMagic |
| TC-WIRE-04 | `test_unsupported_version` | version != 1，验证返回 UipUnsupportedVersion |
| TC-WIRE-05 | `test_invalid_flags_request_response` | 同时置 REQUEST+RESPONSE，验证返回 UipInvalidFlags |
| TC-WIRE-06 | `test_invalid_codec` | codec=99，验证返回 UipInvalidCodec |
| TC-WIRE-07 | `test_checksum_mismatch` | encode 后修改 body，验证返回 UipChecksumMismatch |
| TC-WIRE-08 | `test_message_too_large` | body_len > cfg.max_body_len，验证返回 UipMessageTooLarge |
| TC-WIRE-09 | `test_truncated_header` | in_len < 24，验证返回 UipInvalidFrame |
| TC-WIRE-10 | `test_big_endian_u32` | 写入 0x12345678，验证读出相同值 |
| TC-WIRE-11 | `test_all_msg_types` | 测试 HELLO/PING/PONG/ERROR/EVENT 类型编码解码 |

### 实现步骤

- [x] 1. 创建 tests/ 目录
- [x] 2. 引入 std.uip.wire 依赖
- [x] 3. 实现 11 个测试用例
- [x] 4. 运行测试验证

---

## Step 5: `lib/std/uip/resolver.uya`

### 职责
封装 DNS 解析，提供统一的 IPv4 解析接口。

### 详细设计

#### 5.1 依赖
```uya
use std.net.dns;
```

#### 5.2 结构体

```uya
export struct UipResolver {
    dns: DnsClient,  // 内部使用 std.net.dns 的 DnsClient
}
```

#### 5.3 导出函数

| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_resolver_init` | `(resolver: &UipResolver, nameserver: &[byte]) void` | 初始化 resolver |
| `uip_resolver_set_timeout_ms` | `(resolver: &UipResolver, timeout_ms: u32) void` | 设置超时 |
| `uip_resolve_first_ipv4` | `(resolver: &UipResolver, host: &[byte], out: &byte, out_len_out: &usize) !usize` | 解析首个 IPv4 |

#### 5.4 错误映射

| DNS 错误 | 映射为 |
|----------|--------|
| DnsNotFound | UipResolveFailed |
| DnsTimeout | UipResolveFailed |
| DnsServerFailure | UipResolveFailed |
| 其他 | UipResolveFailed |

### 实现步骤

- [x] 1. 依赖 errors.uya, std.net.dns
- [x] 2. 定义 UipResolver 结构体
- [x] 3. 实现 `uip_resolver_init` 调用 dns_client_init
- [x] 4. 实现 `uip_resolver_set_timeout_ms` 调用 dns_client_set_timeout_ms
- [x] 5. 实现 `uip_resolve_first_ipv4` 调用 dns_client_resolve_first_ipv4
- [x] 6. DNS 错误统一映射为 UipResolveFailed

### 测试用例

| 用例 | 描述 | 预期 |
|------|------|------|
| TC-RES-01 | 解析 localhost | 返回 127.0.0.1 (4字节) |
| TC-RES-02 | 解析无效域名 | 返回 UipResolveFailed |
| TC-RES-03 | 自定义 nameserver | 使用指定 DNS 服务器 |
| TC-RES-04 | 验证输出长度 | out_len_out == 4 |

---

## Step 6: `lib/std/uip/tcp.uya`

### 职责
TCP socket connect/listen/accept、frame 收发。

### 详细设计

#### 6.1 结构体定义

```uya
// TCP 连接
export struct UipTcpConn {
    fd: i32,           // socket 文件描述符
    config: UipConfig, // 配置
}

// TCP 客户端配置
export struct UipTcpClientConfig {
    host: &[byte],
    port: u16,
    nameserver: &[byte],
    timeout_ms: u32,
    max_body_len: usize,
}

// TCP 服务端
export struct UipTcpServer {
    fd: i32,
    config: UipConfig,
}

// TCP 服务端配置
export struct UipTcpServerConfig {
    port: u16,
    backlog: i32,
    timeout_ms: u32,
    max_body_len: usize,
}
```

#### 6.2 sockaddr_in 布局（16 字节）

```
Offset   Size   Field
------   ----   -----
  0        2    sin_family = AF_INET (2)
  2        2    sin_port (big-endian)
  4        4    sin_addr (IPv4)
  8        8    sin_zero (填充 0)
```

#### 6.3 导出函数

**客户端：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_tcp_connect` | `(cfg: &UipTcpClientConfig) !UipTcpConn` | 建立 TCP 连接 |
| `uip_tcp_close` | `(conn: &UipTcpConn) void` | 关闭连接 |

**服务端：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_tcp_server_listen` | `(cfg: &UipTcpServerConfig) !UipTcpServer` | 监听端口 |
| `uip_tcp_server_accept` | `(server: &UipTcpServer) !UipTcpConn` | 接受连接 |
| `uip_tcp_server_close` | `(server: &UipTcpServer) void` | 关闭服务端 |

**帧读写：**
| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_tcp_write_message` | `(conn: &UipTcpConn, ...) !usize` | 发送消息 |
| `uip_tcp_read_message` | `(conn: &UipTcpConn, ...) !UipMessage` | 读取消息 |

#### 6.4 connect 流程

```
1. uip_resolver_init(&resolver, cfg.nameserver)
2. uip_resolve_first_ipv4(&resolver, cfg.host) -> ipv4[4]
3. sys_socket(AF_INET, SOCK_STREAM, 0) -> fd
4. uip_fill_sockaddr_ipv4(ipv4, cfg.port) -> addr[16]
5. uip_tcp_set_timeouts(fd, cfg.timeout_ms)
6. sys_connect(fd, addr, 16)
7. return UipTcpConn{ fd, config }
```

#### 6.5 listen 流程

```
1. sys_socket(AF_INET, SOCK_STREAM, 0) -> fd
2. setsockopt SO_REUSEADDR
3. uip_fill_sockaddr_ipv4(0,0,0,0, cfg.port) -> addr[16]
4. sys_bind(fd, addr, 16)
5. sys_listen(fd, cfg.backlog)
6. return UipTcpServer{ fd, config }
```

#### 6.6 read_message 流程

```
1. uip_tcp_read_exact(fd, hdr_buf, 24)
2. uip_decode_header(hdr_buf, 24) -> header
3. if header.body_len > body_cap: return UipMessageTooLarge
4. uip_tcp_read_exact(fd, body_buf, header.body_len)
5. uip_decode_message(hdr_buf, 24, body_buf, header.body_len, &cfg) -> message
6. return message
```

### 实现步骤

- [x] 1. 依赖 errors.uya, types.uya, wire.uya, resolver.uya, libc.syscall
- [x] 2. 定义 UipTcpConn / UipTcpClientConfig / UipTcpServer / UipTcpServerConfig
- [x] 3. 实现 `uip_fill_sockaddr_ipv4`
- [x] 4. 实现 `uip_tcp_set_reuseaddr`
- [x] 5. 实现 `uip_tcp_set_timeouts`
- [x] 6. 实现 `uip_tcp_read_exact`
- [x] 7. 实现 `uip_tcp_write_all`
- [x] 8. 实现 `uip_tcp_connect`
- [x] 9. 实现 `uip_tcp_close`
- [x] 10. 实现 `uip_tcp_server_listen`
- [x] 11. 实现 `uip_tcp_server_accept`
- [x] 12. 实现 `uip_tcp_server_close`
- [x] 13. 实现 `uip_tcp_write_message`
- [x] 14. 实现 `uip_tcp_read_message`

### 测试用例

| 用例 | 描述 | 预期 |
|------|------|------|
| TC-TCP-01 | loopback connect | 成功建立连接，fd > 0 |
| TC-TCP-02 | 发送 Request + 接收 Response | roundtrip 成功 |
| TC-TCP-03 | 发送 PING (oneway) | 发送成功，不等待响应 |
| TC-TCP-04 | 服务端返回 PONG | 客户端收到 PONG |
| TC-TCP-05 | request_id 不匹配 | 检测到 UipRequestIdMismatch |
| TC-TCP-06 | body too large | 检测到 UipMessageTooLarge |
| TC-TCP-07 | 连接关闭后读 | 返回 UipConnectionClosed |
| TC-TCP-08 | 服务端正常关闭 | 客户端收到关闭事件 |
| TC-TCP-09 | listen + accept | 服务端监听，客户端连接成功 |
| TC-TCP-10 | 并发连接 | 串行处理多个连接 |

---

## Step 7: `lib/std/uip/session.uya`

### 职责
request_id 管理、request/response helper、ping/pong。

### 详细设计

#### 7.1 结构体

```uya
export struct UipSession {
    conn: UipTcpConn,      // 底层 TCP 连接
    next_request_id: u32,  // 下一个请求 ID（从 1 开始）
}
```

#### 7.2 导出函数

| 函数 | 签名 | 说明 |
|------|------|------|
| `uip_session_init` | `(session: &UipSession, conn: UipTcpConn) void` | 初始化 session |
| `uip_session_close` | `(session: &UipSession) void` | 关闭 session |
| `uip_session_next_id` | `(session: &UipSession) u32` | 获取下一个 request_id |
| `uip_session_request` | `(session: &UipSession, ...) !UipMessage` | 发送请求并等待响应 |
| `uip_session_send_ping` | `(session: &UipSession, ...) !void` | 发送心跳 |
| `uip_session_send_pong` | `(session: &UipSession, ...) !void` | 发送响应心跳 |

#### 7.3 request 流程

```
1. id = uip_session_next_id()
2. flags = UIP_FLAG_REQUEST
3. uip_tcp_write_message(conn, flags, codec, msg_type, id, body, ...)
4. resp = uip_tcp_read_message(conn, ...)
5. if resp.flags & UIP_FLAG_RESPONSE == 0: return error
6. if resp.request_id != id: return UipRequestIdMismatch
7. return resp
```

#### 7.4 send_ping 流程

```
1. body = 空 slice
2. flags = UIP_FLAG_HEARTBEAT | UIP_FLAG_ONEWAY
3. request_id = 0  // 心跳不使用 request_id
4. uip_tcp_write_message(conn, flags, UIP_CODEC_RAW, UIP_MSG_PING, 0, body, ...)
```

### 实现步骤

- [x] 1. 依赖 errors.uya, types.uya, wire.uya, tcp.uya
- [x] 2. 定义 UipSession 结构体
- [x] 3. 实现 `uip_session_init`
- [x] 4. 实现 `uip_session_close`
- [x] 5. 实现 `uip_session_next_id`（到达 MAX 后回绕到 1）
- [x] 6. 实现 `uip_session_request`
- [x] 7. 实现 `uip_session_send_ping`
- [x] 8. 实现 `uip_session_send_pong`

### 测试用例

| 用例 | 描述 | 预期 |
|------|------|------|
| TC-SESSION-01 | 初始化 session | next_request_id == 1 |
| TC-SESSION-02 | next_id 递增 | 调用两次，id1=1, id2=2 |
| TC-SESSION-03 | request_id 回绕 | 到达 MAX 后回到 1 |
| TC-SESSION-04 | request 往返 | 收到匹配的 response |
| TC-SESSION-05 | 发送 ping | 发送成功，无响应 |
| TC-SESSION-06 | 收到 ping 返回 pong | 对端收到 pong |
| TC-SESSION-07 | response id 不匹配 | 返回 UipRequestIdMismatch |
| TC-SESSION-08 | response 无 RESPONSE flag | 返回 UipInvalidFrame |

---

## Step 8: `lib/std/uip/uip.uya`

### 职责
统一 re-export 出口，聚合所有子模块。

### 详细设计

导出所有子模块的公共接口：

```uya
pub use std.uip.errors;    // 错误类型
pub use std.uip.types;    // 常量、结构体
pub use std.uip.wire;     // 编解码
pub use std.uip.resolver; // DNS 解析
pub use std.uip.tcp;      // TCP 连接
pub use std.uip.session;  // Session 管理
```

### 实现步骤

- [x] 1. 创建 uip.uya 文件
- [x] 2. 按项目风格 re-export 所有子模块
- [x] 3. 添加模块级文档注释
- [x] 4. 验证 `use std.uip` 可访问所有导出

---

## Step 9: `tests/test_std_uip_tcp.uya`

### 职责
loopback TCP 联调测试，验证 TCP + wire 协作。

### 详细设计

#### 测试辅助函数

```uya
fn start_server(handler: fn (fd: i32) !void) !i32 {
    const fd: i32 = try sys_socket(AF_INET, SOCK_STREAM, 0);
    setsockopt SO_REUSEADDR
    bind 0.0.0.0:0 -> 获取随机端口
    listen 5
    在后台线程 accept -> handler(fd)
    return port
}
```

#### 测试用例

| 用例 | 描述 | 步骤 | 预期 |
|------|------|------|------|
| TC-TCP-INT-01 | Request-Response 往返 | 1. 客户端发送 body="hello"<br>2. 服务端 echo body="world"<br>3. 客户端收到 | status ok, body="world" |
| TC-TCP-INT-02 | PING 单向发送 | 1. 客户端发送 PING<br>2. 不等待响应 | 发送成功 |
| TC-TCP-INT-03 | PING-PONG 往返 | 1. 客户端发送 PING<br>2. 服务端返回 PONG<br>3. 客户端收到 | 收到 PONG |
| TC-TCP-INT-04 | request_id 不匹配 | 1. 服务端返回错误的 request_id | 客户端检测到 UipRequestIdMismatch |
| TC-TCP-INT-05 | body too large | 1. 服务端返回 body > client max | 客户端收到 UipMessageTooLarge |
| TC-TCP-INT-06 | 连接关闭检测 | 1. 服务端关闭连接<br>2. 客户端读 | UipConnectionClosed |

### 实现步骤

- [x] 1. 创建 tests/test_std_uip_tcp.uya
- [x] 2. 实现 start_server 辅助函数
- [x] 3. 实现 TC-TCP-INT-01 ~ TC-TCP-INT-06
- [x] 4. 运行测试验证

---

## 验收标准

> 当前实现状态：wire 层 13 个测试通过；TCP 集成层 6 个测试通过。

### wire 层
- [x] 所有 11 个 wire 测试用例通过
- [x] magic/version/flags/codec 校验路径覆盖完整
- [x] checksum 计算正确（对比已知 CRC32 值）

### TCP 层
- [x] loopback request/response 往返正确
- [x] ping/pong 往返正确
- [x] request_id mismatch 可被检测
- [x] oversized body 可被拒绝
- [x] 连接关闭后读返回 `UipConnectionClosed`

### 代码质量
- [x] `std.uip` 可作为独立模块使用
- [x] 不污染现有 `std.http` / `std.net.dns` 模块
- [x] 所有 export 函数有文档注释