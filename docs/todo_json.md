# Uya JSON 编解码器实现待办

**参考**：[json_design.md](json_design.md)

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。

---

## Phase 1：基础解析器（标量）

### 1.1 前置依赖

- [ ] 确认 Arena 可用性：`src/arena.uya` 或新建 `lib/std/mem/arena.uya`
- [ ] 若无 Arena，实现或封装 `arena_alloc`/`arena_reset` 的等效接口

### 1.2 数据结构

- [ ] 创建 `lib/std/json/` 目录
- [ ] `error.uya`：定义 `JsonError`（InvalidUtf8、InvalidEscape、InvalidUnicode、UnexpectedToken、UnexpectedEof、NumberOverflow、InvalidNumber、NestingTooDeep）
- [ ] `value.uya`：`JsonValue` union、`JsonArray`、`JsonKeyValue`、`JsonObject` 结构体

### 1.3 标量解析器

- [ ] `parser.uya`：实现 `parse(arena, input) !JsonValue`
  - [ ] 空白跳过
  - [ ] 解析 null、true、false
  - [ ] 解析整数（i64）、浮点（f64），手写解析逻辑
  - [ ] 解析字符串，返回 `&[byte]` 视图（零拷贝）
  - [ ] 解析数组
  - [ ] 解析对象
  - [ ] 转义序列：`\n\t\r\"\\`、`\uXXXX`
  - [ ] 错误位置报告（行/列或偏移）

### 1.4 测试

- [ ] `tests/test_json_parse_basic.uya`：null、bool、数字、字符串
- [ ] `tests/test_json_parse_array.uya`：空数组、嵌套数组
- [ ] `tests/test_json_parse_object.uya`：空对象、嵌套对象
- [ ] `tests/error_json_*.uya`：预期解析失败用例

---

## Phase 2：编码器（基础类型）

### 2.1 JsonWriter

- [ ] `encoder.uya`：`JsonWriter` 结构体（buffer + 写入位置）
- [ ] `write_null`、`write_bool`、`write_i64`、`write_f64`
- [ ] `write_string`（转义处理）
- [ ] `write_array_start`、`write_array_end`、`write_object_start`、`write_object_end`

### 2.2 基础类型 ToJson

- [ ] `impl.uya`：为 i32、i64、f64、bool、`&[byte]` 实现 ToJson（若接口可用）或提供 `json_write_*` 函数

### 2.3 API

- [ ] `encode_to(value, buf, cap) !usize`
- [ ] `encode(arena, value) !&[byte]`（需能处理 JsonValue 等）

### 2.4 测试

- [ ] `tests/test_json_encode_basic.uya`：基础类型 roundtrip
- [ ] `tests/test_json_encode_array.uya`
- [ ] `tests/test_json_encode_object.uya`

---

## Phase 3：结构体序列化

### 3.1 宏或手写

- [ ] 若 `@mc` 可用：实现 `impl_json!(StructName)` 宏
- [ ] 否则：提供手写 `to_json` 示例，文档说明用户需为每个结构体实现

### 3.2 测试

- [ ] `tests/test_json_struct_roundtrip.uya`：结构体 encode → parse → 字段比较

---

## Phase 4：SIMD 加速（可选）

- [ ] 实现 Stage 1 结构字符扫描的 SIMD 分支（AVX2/NEON）
- [ ] 运行时 CPU 检测，选择标量或 SIMD 路径
- [ ] Benchmark 验证 1–3 GB/s 目标

---

## Benchmark

- [ ] 获取 twitter.json、citm_catalog.json、canada.json
- [ ] 编写 `tests/bench_json.uya` 或独立 benchmark 脚本
- [ ] 记录 Phase 1 / Phase 4 吞吐量（GB/s）

---

## 与主待办集成

- [x] 已在 [todo_mini_to_full.md](todo_mini_to_full.md) 第 38 项添加 **std.json** 条目
