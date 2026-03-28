---
name: Protobuf 编解码器计划
overview: 为 Uya 标准库设计高性能 Protocol Buffers 二进制编解码器，遵循 wire format 规范，基于宏/注解实现结构体序列化，零拷贝处理 string/bytes 字段。
todos: []
isProject: false
---

# Uya Protobuf 编解码器计划

## 1. Protobuf 特性概览

- **二进制格式**：非文本，与 JSON/YAML 不同，无结构字符扫描
- **Wire types**：0 (varint)、1 (64-bit)、2 (length-delimited)、5 (32-bit)
- **Tag**：`wire_type | (field_number << 3)`，varint 编码
- **Varint**：7-bit payload + MSB 续位，小数字节少
- **零拷贝可能**：string、bytes 可直接 `&[byte]` 引用输入 buffer；调用方需保证 decoded 结构体生命周期不超 input
- **Schema 依赖**：需 .proto 或 Uya 结构体定义，编解码皆需字段号

---

## 2. 设计目标

- **零拷贝**：string/bytes 字段返回 `&[byte]` 视图；默认不校验 UTF-8（可选 `decode_strict`）
- **单次分配**：解析用 Arena
- **编译期序列化**：`impl_protobuf!(StructName)` 宏或 `@pb_field` 注解，零反射
- **显式内存**：`decode(arena, input)`、`encode_to(buf, cap)`
- **Wire format 兼容**：与标准 protobuf 互操作

---

## 3. 与 std.json / std.yaml 的差异


| 方面     | JSON/YAML | Protobuf                  |
| ------ | --------- | ------------------------- |
| 格式     | 文本        | 二进制                       |
| 结构     | 键名        | field number (1, 2, 3...) |
| 解析     | 词法+结构扫描   | 顺序读取 tag + payload        |
| SIMD   | 可加速结构扫描   | 难以直接受益                    |
| Schema | 无         | 必需（.proto 或 Uya 结构体）      |
| 动态解析   | 常见        | 可选（PbValue 动态类型）          |


---

## 4. 分阶段范围

### Phase 1：Wire 层 + 基础类型

- Varint 编码/解码
- sint32/sint64（zigzag 编码，负数更紧凑）
- fixed32、fixed64、double、float
- string、bytes（length-delimited，零拷贝）
- 单层 message 编解码（无嵌套）
- proto3 默认值：decode 时缺失字段填充 0、""、false
- API：`decode_message<T>(arena, input) !T`，`encode_message(value) !&[byte]` 或 `encode_to`

### Phase 2：嵌套与 repeated

- 嵌套 message
- repeated 标量、repeated message；同 field 多次出现合并为数组
- repeated 内存：`ptr: &T, len: usize`（Arena 分配）
- packed repeated（更高效）

### Phase 3：高级特性

- map（wire 等价 repeated message，key 为 field 1）
- oneof（wire 同 field 仅一次；Uya 用 union + tag 对应）
- enum（varint，值为 proto 定义序号）
- optional（proto3 默认、proto2 optional）

### 不做或延后

- .proto 文件解析（可交由独立工具生成 Uya 代码）
- proto2 完整语义（默认值、required）
- extensions、any、service/rpc

---

## 5. 核心 API 草图

```uya
// 宏或手写：若 @mc 不成熟则手写 decode_/encode_ 函数
struct User {
    id: i64,           // field 1, varint
    name: &[byte],     // field 2, length-delimited
}
impl_protobuf!(User, 1 -> id, 2 -> name);

fn decode(arena: &Arena, input: &[byte]) !User;
fn encode_to(value: &User, buf: &byte, cap: usize) !usize;
fn encode(arena: &Arena, value: &User) !&[byte];
```

---

## 6. 动态解析（可选）

- `PbValue` union：支持 unknown fields 跳过、动态反射式访问
- `fn decode_dynamic(arena, input) !PbMessage`：无强类型，按 field number 访问
- 与 typed decode 共用 wire 层（varint、tag、length-delimited 等），仅上层构建 PbMessage 而非 T

---

## 7. 错误类型

- TruncatedInput、InvalidVarint、InvalidTag、UnknownWireType、FieldNumberOverflow、RecursionLimit 等

---

## 8. 模块与文件规划

```
lib/std/protobuf/
  protobuf.uya     # 模块入口，重导出
  wire.uya         # varint、zigzag、tag 编解码
  error.uya        # 错误定义
  decode.uya       # decode、decode_message、decode_dynamic
  encode.uya       # encode、encode_to
  impl.uya         # 基础类型编解码
  impl_macro.uya   # 可选：impl_protobuf! 宏
```

## 9. 性能指标与对比

### 9.1 Uya 目标


| 阶段                   | 解码目标         | 编码目标         | 说明                   |
| -------------------- | ------------ | ------------ | -------------------- |
| Phase 1（单层、基础类型）     | 0.5–1.5 GB/s | 0.3–1 GB/s   | 对标 prost / 小型 upb    |
| Phase 2（嵌套、repeated） | 0.3–1 GB/s   | 0.2–0.8 GB/s | 嵌套与 repeated 增加分支与分配 |
| Phase 3（map、oneof）   | 视结构          | 视结构          | 与 Phase 2 同量级        |


### 9.2 指标定义

- **吞吐量**：MB/s 或 GB/s，按「消息字节数 × 重复次数 / 总耗时」计算
- **单线程、热缓存**，多次运行取中位数
- **消息类型**：简单 message（若干标量 + 可选 string/bytes）、addressbook 等中等复杂度

### 9.3 主流库对比（参考）


| 实现                  | 语言   | 解析吞吐量             | 编码吞吐量     | 备注      |
| ------------------- | ---- | ----------------- | --------- | ------- |
| upb（table-driven）   | C    | 2.0–2.3 GB/s      | ~0.6 GB/s | 官方高性能实现 |
| libprotobuf（Proto2） | C++  | 0.2–0.4 GB/s      | ~1.3 GB/s | 参考基线    |
| prost               | Rust | 约 0.5–1.5 GB/s 量级 | 类似        | 零拷贝可选   |
| Go encoding 官方      | Go   | 约 0.1–0.3 GB/s    | 类似        | 反射/生成并存 |
| Java Protobuf       | Java | 约 0.05–0.2 GB/s   | 类似        | 反射为主    |


Uya 目标：Phase 1 接近 prost，力争达到 upb 的 1/2–2/3；明显优于 Go/Java 官方库。

### 9.4 Benchmark 方案

- **数据集**：protobuf 官方 benchmark 消息、addressbook.proto 生成数据、自建小/中/大 message 样本
- **环境**：单线程、固定消息大小或条数、预热后取中位数
- **报告**：解码 GB/s、编码 GB/s、可选延迟 p99

## 10. 产出物

- [docs/protobuf_design.md](docs/protobuf_design.md) - 详细设计文档（结构对标 json_design.md）
- [docs/todo_protobuf.md](docs/todo_protobuf.md) - 实现待办
- 在 [docs/todo_mini_to_full.md](docs/todo_mini_to_full.md) 添加 std.protobuf 条目

---

## 11. 参考

- [Protocol Buffers Encoding](https://developers.google.com/protocol-buffers/docs/encoding)
- [protobuf wire format](https://kreya.app/blog/protocolbuffers-wire-format)
- Go protowire、Rust prost、C++ CodedInputStream 等实现

