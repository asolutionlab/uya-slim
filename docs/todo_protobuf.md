# Uya Protobuf 编解码器实现待办

**参考**：[protobuf_design.md](protobuf_design.md)

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。

---

## Phase 1：Wire 层 + 基础类型

### 1.1 前置依赖

- [ ] 确认 Arena 可用性：与 std.json 共用
- [ ] std.mem：mem_copy 等

### 1.2 Wire 层

- [ ] 创建 `lib/std/protobuf/` 目录
- [ ] `error.uya`：TruncatedInput、InvalidVarint、InvalidTag、UnknownWireType、FieldNumberOverflow、RecursionLimit
- [ ] `wire.uya`：varint 编解码
- [ ] `wire.uya`：zigzag（sint32/sint64）编解码
- [ ] `wire.uya`：tag 解析（field_number、wire_type）

### 1.3 基础类型编解码

- [ ] `impl.uya`：int32、int64、uint32、uint64、sint32、sint64、bool、fixed32、fixed64、float、double
- [ ] `impl.uya`：string、bytes（length-delimited，零拷贝）
- [ ] proto3 默认值：decode 时缺失字段填充 0、""、false

### 1.4 单层 message

- [ ] `decode.uya`：`decode(arena, input) !T`，需 T 实现 ProtobufDecode 或手写 decode 函数
- [ ] `encode.uya`：`encode_to(value, buf, cap) !usize`、`encode(arena, value) !&[byte]`
- [ ] 若宏可用：`impl_protobuf!(User, 1 -> id, 2 -> name)`；否则提供手写 decode_/encode_ 示例

### 1.5 测试

- [ ] `tests/test_protobuf_wire.uya`：varint、zigzag、tag 编解码
- [ ] `tests/test_protobuf_decode_basic.uya`：单层 message，标量 + string/bytes
- [ ] `tests/test_protobuf_encode_basic.uya`：encode roundtrip
- [ ] `tests/error_protobuf_*.uya`：TruncatedInput、InvalidVarint 等预期失败

---

## Phase 2：嵌套与 repeated

### 2.1 嵌套 message

- [ ] 递归 decode/encode 嵌套 message
- [ ] 嵌套深度限制（RecursionLimit）

### 2.2 repeated

- [ ] repeated 标量、repeated message
- [ ] 同 field 多次出现合并为 `ptr: &T, len: usize`（Arena 分配）
- [ ] packed repeated

### 2.3 测试

- [ ] `tests/test_protobuf_nested.uya`
- [ ] `tests/test_protobuf_repeated.uya`
- [ ] `tests/test_protobuf_packed.uya`

---

## Phase 3：高级特性

- [ ] map（wire 等价 repeated message）
- [ ] oneof（union + tag）
- [ ] enum（varint）
- [ ] optional
- [ ] 测试：`tests/test_protobuf_map.uya`、`test_protobuf_oneof.uya`

---

## Phase 4：动态解析（可选）

- [ ] `PbValue`、`PbField`、`PbMessage` 结构
- [ ] `decode_dynamic(arena, input) !PbMessage`
- [ ] unknown fields 跳过
- [ ] 与 typed decode 共用 wire 层

---

## Benchmark

- [ ] 获取 protobuf 官方 benchmark 消息、addressbook 数据
- [ ] 编写 `tests/bench_protobuf.uya` 或独立 benchmark 脚本
- [ ] 记录 Phase 1/2 解码、编码吞吐量（GB/s）

---

## 与主待办集成

- [x] 已在 [todo_mini_to_full.md](todo_mini_to_full.md) 第 40 项添加 **std.protobuf** 条目
