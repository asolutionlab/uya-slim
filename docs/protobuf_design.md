# Uya 高性能 Protobuf 编解码器设计文档

**版本**：v0.1  
**状态**：设计阶段  
**参考**：Protocol Buffers Encoding、[protobuf 编解码器计划](../.cursor/plans/protobuf_编解码器计划_1cc43520.plan.md)

---

## 1. 概述

本文档定义 Uya 标准库的 Protocol Buffers 二进制编解码器设计，基于 Uya 的零 GC、编译期证明、显式内存控制、切片零拷贝等特性，实现高性能 protobuf 解析与编码。目标：Phase 1 接近 Rust prost 水平，力争达到 upb 的 1/2–2/3，明显优于 Go/Java 官方库。

### 1.1 设计目标

- **零拷贝**：string/bytes 字段返回 `&[byte]` 视图；调用方需保证 decoded 结构体生命周期不超 input
- **单次分配**：解析阶段使用 Arena
- **显式内存**：API 要求调用方传入 Arena 或预分配 buffer
- **编译期序列化**：结构体通过宏或手写 decode/encode，零反射
- **Wire format 兼容**：与标准 protobuf 互操作

### 1.2 Protobuf 特性概览

- **二进制格式**：非文本，顺序读取 tag + payload
- **Wire types**：0 (varint)、1 (64-bit)、2 (length-delimited)、5 (32-bit)
- **Tag**：`wire_type | (field_number << 3)`，varint 编码
- **Varint**：7-bit payload + MSB 续位
- **sint32/sint64**：zigzag 编码，负数更紧凑
- **Schema 依赖**：编解码皆需 field number 与类型

---

## 2. 设计原则（对齐 Uya 特性）

| Uya 特性 | Protobuf 设计应用 |
|----------|-------------------|
| 零 GC / 显式内存 | 解析器使用 Arena，编码器接受 buffer 或 Arena |
| 编译期证明 | 结构体 → protobuf 映射由宏或手写生成，零反射 |
| 错误联合 `!T` | `decode()` 返回 `!T`，`encode()` 返回 `!&[byte]` |
| 切片 `&[T]` | string/bytes 返回 `&[byte]` 视图，零拷贝 |
| 无隐式分配 | API 显式要求传入 `&Arena` 或 buffer 容量 |

---

## 3. 标准范围与分阶段

### 3.1 Phase 1：Wire 层 + 基础类型

- Varint、zigzag（sint32/sint64）、fixed32、fixed64、double、float
- string、bytes（length-delimited，零拷贝，默认不校验 UTF-8，可选 `decode_strict`）
- 单层 message，proto3 默认值（缺失字段填充 0、""、false）

### 3.2 Phase 2：嵌套与 repeated

- 嵌套 message
- repeated 标量、repeated message；同 field 多次出现合并
- repeated 内存：`ptr: &T, len: usize`（Arena 分配）
- packed repeated

### 3.3 Phase 3：高级特性

- map、oneof（Uya union + tag）、enum、optional

### 3.4 不做或延后

- .proto 文件解析（可交由独立工具生成 Uya 代码）
- proto2 完整语义、extensions、any、service/rpc

---

## 4. 整体架构

```mermaid
flowchart TB
    subgraph Decode [解码流程]
        A[Input: &[byte]] --> B[Wire 层: varint/tag/length]
        B --> C[按 schema 填充结构体]
        C --> D[T 或 PbMessage]
    end

    subgraph Encode [编码流程]
        E[结构体 T] --> F[宏/手写 encode]
        F --> G[PbWriter]
        G --> H[Output: &[byte]]
    end

    subgraph Memory [内存]
        I[Arena] --> J[decode 分配]
        K[调用方 buffer] --> G
    end
```

---

## 5. 核心数据结构

### 5.1 类型化 message（宏或手写）

```uya
struct User {
    id: i64,           // field 1, varint
    name: &[byte],     // field 2, length-delimited
}
impl_protobuf!(User, 1 -> id, 2 -> name);
```

### 5.2 动态解析 PbMessage（可选）

```uya
union PbValue {
    varint: u64,
    fixed64: u64,
    fixed32: u32,
    len_delimited: &[byte],  // string/bytes/嵌套 message
}

struct PbField {
    field_num: u32,
    value: PbValue,
}

struct PbMessage {
    fields: &PbField,  // Arena 分配
    len: usize,
}
```

### 5.3 访问方式

- 类型化：直接访问 `user.id`、`user.name`
- 动态：`pb_message_get_field(msg, field_num)` 返回 `PbValue`

---

## 6. Wire 层

### 6.1 Varint

- 每字节 7-bit 数据 + 1-bit 续位（MSB）
- 小端序拼接 7-bit 块
- 最大 10 字节（64-bit）

### 6.2 Zigzag（sint32/sint64）

- 0→0, -1→1, 1→2, -2→3, 2→4, ...
- `encode: (n << 1) ^ (n >> 31)` 等

### 6.3 Tag

- `tag = (field_number << 3) | wire_type`
- wire_type：0 varint, 1 64-bit, 2 length-delimited, 5 32-bit

### 6.4 Length-delimited

- 先 varint 长度，再 payload
- string、bytes、嵌套 message、packed repeated 均用此格式

---

## 7. 解析器（Decoder）

### 7.1 API

```uya
fn decode(arena: &Arena, input: &[byte]) !T;       // 类型化，需 impl ProtobufDecode for T
fn decode_dynamic(arena: &Arena, input: &[byte]) !PbMessage;  // 动态
fn decode_strict(arena: &Arena, input: &[byte]) !T;  // 可选：string 校验 UTF-8
```

### 7.2 解析流程

1. 循环读取 tag（varint）
2. 根据 wire_type 读取 payload
3. 同 field 多次出现：repeated 合并，否则取最后一次（proto3）
4. unknown fields 跳过

### 7.3 错误类型

```uya
error {
    TruncatedInput,
    InvalidVarint,
    InvalidTag,
    UnknownWireType,
    FieldNumberOverflow,
    RecursionLimit,
}
```

---

## 8. 编码器（Encoder）

### 8.1 API

```uya
fn encode_to(value: &T, buf: &byte, cap: usize) !usize;
fn encode(arena: &Arena, value: &T) !&[byte];
```

### 8.2 编码流程

1. 按 field number 顺序（或用户指定）写入 tag + payload
2. 嵌套 message 先算长度，再 length-delimited 写入
3. repeated：每项单独 tag+payload，或 packed（wire_type 2）

### 8.3 宏或手写

- 若 `impl_protobuf!` 可用：生成 `decode_` / `encode_` 实现
- 否则：手写 `fn user_decode`、`fn user_encode`，文档说明用户需为每个 message 实现

---

## 9. 模块与文件规划

```
lib/std/protobuf/
  protobuf.uya     # 模块入口，重导出
  wire.uya         # varint、zigzag、tag 编解码
  error.uya        # 错误定义
  decode.uya       # decode、decode_dynamic
  encode.uya       # encode、encode_to、PbWriter
  impl.uya         # 基础类型编解码（i32、i64、bool、&[byte] 等）
  impl_macro.uya   # 可选：impl_protobuf! 宏
```

---

## 10. 依赖与约束

- **Arena**：与 std.json 共用
- **std.mem**：mem_copy 等
- **std.string**：UTF-8 校验（decode_strict 时）
- **泛型**：`decode<T>` 需 T 实现 ProtobufDecode 或等效约束

---

## 11. 性能目标

| 阶段 | 解码目标 | 编码目标 |
|------|----------|----------|
| Phase 1 | 0.5–1.5 GB/s | 0.3–1 GB/s |
| Phase 2 | 0.3–1 GB/s | 0.2–0.8 GB/s |

- **吞吐量**：消息字节数 × 重复次数 / 总耗时，单线程、热缓存、中位数

---

## 12. 与主流库对比

| 实现 | 语言 | 解析 | 编码 |
|------|------|------|------|
| upb | C | 2.0–2.3 GB/s | ~0.6 GB/s |
| libprotobuf | C++ | 0.2–0.4 GB/s | ~1.3 GB/s |
| prost | Rust | 0.5–1.5 GB/s 量级 | 类似 |
| Go 官方 | Go | 0.1–0.3 GB/s | 类似 |
| Java Protobuf | Java | 0.05–0.2 GB/s | 类似 |

Uya 目标：Phase 1 接近 prost，力争 upb 的 1/2–2/3；明显优于 Go/Java。
