# Uya JSON 编解码器实现待办

**参考**：[json_design.md](json_design.md)（设计与语法对齐 [grammar_formal.md](grammar_formal.md)）

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。

---

## Phase 1：基础解析器（标量）

### 1.1 前置依赖

- [x] 确认 Arena 可用性：已实现 `lib/std/mem/arena.uya`（仅缓冲区 bump，无 malloc）
- [x] `arena_init`/`arena_alloc`/`arena_reset` 可用

### 1.2 数据结构

- [x] 创建 `lib/std/json/` 目录
- [x] `errors.uya`：Json 错误（InvalidUtf8、InvalidEscape、InvalidUnicode、UnexpectedToken、UnexpectedEof、NumberOverflow、InvalidNumber、NestingTooDeep）
- [x] `value.uya`：`JsonValue` union、`JsonStrView`、`JsonArray`、`JsonKeyValue`、`JsonObject`

### 1.3 标量解析器

- [x] `parser.uya`：实现 `parse(arena, ptr, len) !JsonValue`（API 用 ptr+len 替代 `&[byte]` 以规避 slice codegen）
  - [x] 空白跳过、null/true/false、整数(i64)/浮点(f64)、字符串(JsonStrView)、数组、对象
  - [x] 转义 `\n\t\r\"\\`、`\uXXXX`
  - [x] codegen 已修复：err_union 的 union payload（如 `!JsonValue`）会先 emit union 定义、错误返回用 `(payload_c){0}` 初始化；i64 字面量用 `number_value_i64` 避免截断

### 1.4 测试

- [x] `tests/test_json_value.uya`：仅测试 JsonValue 构造与 match（通过）
- [x] `tests/test_json_parse_basic.uya`：null、bool、整数、浮点 3.0、字符串
- [x] `tests/test_json_parse_float.uya`：浮点数 3.14、-1.5、科学计数法 1e2
- [x] `tests/test_json_parse_array.uya`：空数组、[1,2]、嵌套数组
- [x] `tests/test_json_parse_object.uya`：空对象、{\"a\":1}、嵌套对象
- [x] `tests/test_json_parse_invalid.uya`：预期解析失败用例（非法 JSON 需返回 error）
- [x] `tests/test_json_parse_string.uya`：字符串解析与转义（`"abc"`、`"a\nb"`、`""`）
- [x] `tests/test_json_roundtrip.uya`：parse → encode_to → parse 往返（对象 `{"x":1}`、数组 `[1,2]`）

---

## Phase 2：编码器（基础类型）

### 2.1 JsonWriter

- [x] `encoder.uya`：`JsonWriter` 结构体（buf、cap、used、overflow）
- [x] `json_write_null`、`json_write_bool`、`json_write_i64`、`json_write_f64`
- [x] `json_write_str_view`（转义 `\"\\\n\r\t`）
- [x] `json_write_value` 递归写入 JsonValue（含数组、对象）

### 2.2 基础类型 ToJson

- [x] 通过 `json_write_value` 统一处理 JsonValue，未单独做 ToJson 接口（可后续加 `impl.uya`）

### 2.3 API

- [x] `encode_to(v: &JsonValue, buf, cap) !usize`（缓冲区不足返回 error.BufferTooSmall）
- [x] `encode_into_arena(arena, v) !JsonStrView`（在 arena 中编码并返回 ptr+len 视图，等价语义，避免 `!&[byte]` 的 slice 返回值）
- [x] `encode(arena, value) !&[byte]`（已实现：依赖 slice 返回值 + 指针作切片 base；见 test_json_encode_slice.uya）
- [x] `encode_into_arena_for_to_json(arena, value: &ToJson) !JsonStrView`（与 encode_into_arena 对称，结构体序列化进 arena 取视图）

### 2.4 测试

- [x] `tests/test_json_encode_basic.uya`：null、bool、数字、字符串编码
- [x] `tests/test_json_encode_array.uya`：空数组、[1,2]
- [x] `tests/test_json_encode_object.uya`：空对象、{\"a\":1}
- [x] `tests/test_json_encode_arena.uya`：encode_into_arena 返回 JsonStrView
- [x] `tests/test_json_encode_slice.uya`：encode(arena, value) 返回 &[byte]，@len 与内容校验

---

## Phase 3：结构体序列化/反序列化

### 3.1 宏（编译器反射）或手写

- [x] 宏 to_json_skeleton：`lib/std/json/macros.uya`，方法块内 `to_json_skeleton({ ... })` 生成 to_json 骨架（开头/结尾 `{` `}` 由宏生成）。
- [x] 完整反射 to_json：`to_json_reflect()` 宏（方法块内无参调用），编译器按结构体字段自动生成 to_json；支持字段类型 i64、i32、f64、bool、JsonStrView；测试见 `tests/test_json_to_json_reflect.uya`。
- [ ] **encode_to_to_json 宏 / to_json 单态展开（进行中）**  
  - 已做：`encode_to_to_json` 改为库侧宏（`lib/std/json/macros.uya`），占位体 `error.BufferTooSmall as ! usize`；编译器在 `macro_expand` 中首参为类型名时用 `build_encode_to_to_json_block` 生成编码块，首参为类型形参 `T` 时不展开（保留调用）；单态体在 codegen 中经 `prepare_mono_body_expand_macros` 再展开；类型检查对 `try encode_to_to_json(...)` 特例放行；try 操作数为 block 时按 `!usize` 生成 C 类型。  
  - 待做：codegen 对「块末为 if（error | value）、块作为 try 操作数」生成可赋给 `struct err_union_size_t` 的表达式（如三元或 err_union 构造），并修正 `return &buf[0:n]` 的切片类型（避免 uya_slice_void）。当前 `make check` 通过 545/547，未通过：`test_json_to_json_reflect`、`test_json_struct_roundtrip`（链接失败）。
- [x] 宏 from_json：结构体方法块内 `from_json_reflect()` 由编译器展开；单态 `from_json<T>(arena, buffer)` 当 T 含 `_from_json_placeholder` 时使用合成 body（parse + match 按字段解码）；[x] 手写示例见 `json_object_find_index`、`user_from_json`。

### 3.2 测试

- [x] `tests/test_json_struct_roundtrip.uya`：结构体 → `encode_to_to_json` → 校验输出字节 → **parse 端到端**（再解析为 JsonValue 校验 id/name）
- [x] 结构体 roundtrip 含「parse → from_json → 结构体 → to_json → parse」，验证有宏时无需手写、无宏时手写 to_json/from_json 对称（见 `test_json_struct_roundtrip.uya`）。
- [x] `tests/test_json_from_json_errors.uya`：json_object_find_index 缺 key 返回 error.MissingField。
- [x] `tests/test_json_from_json_wrong_type.uya`：from_json 字段类型不匹配时返回 error.WrongType。
- [x] `errors.uya`：新增 WrongType，手写 from_json 时用于字段类型不符。
- [x] `encoder.uya`：新增 json_expect_i64/str/bool/f64(v)，手写 from_json 时减少 match 样板；f64 接受 int_val 自动转 float。
- [x] `tests/test_json_expect_helpers.uya`：覆盖四种 expect 辅助及类型不符时 WrongType。

---

## Phase 4：SIMD 加速（可选）

- [ ] 实现 Stage 1 结构字符扫描的 SIMD 分支（AVX2/NEON）
- [ ] 运行时 CPU 检测，选择标量或 SIMD 路径
- [ ] Benchmark 验证 1–3 GB/s 目标

---

## Benchmark

- [ ] 获取 twitter.json、citm_catalog.json、canada.json（可选，用于大文件吞吐量；当前用内嵌负载）
- [x] 编写 `tests/bench_json.uya`：内嵌 JSON 负载，parse/encode 循环 + `clock()` 测时，打印 ticks 与 parse_total_bytes（可用 CLOCKS_PER_SEC 换算 MB/s）
- [x] 记录 Phase 1 基准：运行 `./tests/build/bench_json` 可见 parse/encode ticks；Phase 4 SIMD 后可对比 GB/s

---

## 与主待办集成

- [x] 已在 [todo_mini_to_full.md](todo_mini_to_full.md) 第 38 项添加 **std.json** 条目
