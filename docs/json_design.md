# Uya 高性能 JSON 编解码器设计文档

**版本**：v0.1  
**状态**：设计阶段，部分已实现（见 [todo_json.md](todo_json.md)）  
**参考**：RFC 8259、simdjson、[grammar_formal.md](grammar_formal.md)（语法规范）、[todo_json.md](todo_json.md)（实现待办）

---

## 1. 概述

本文档定义 Uya 标准库的 JSON 编解码器设计，基于 Uya 的零 GC、编译期证明、显式内存控制、切片零拷贝等特性，实现高性能 JSON 解析与编码，目标性能接近 C/Rust 高性能库（serde_json、simd-json 水平），明显优于 Go/Java 标准库。

### 1.1 设计目标

- **零拷贝**：字符串值直接引用输入 buffer，不复制
- **单次分配**：解析阶段使用 Arena，一次分配得到 Tape
- **显式内存**：API 要求调用方传入 Arena 或预分配 buffer
- **编译期序列化与反序列化**：宏 to_json、from_json 利用编译器反射实现自动结构体序列化/反序列化；**有宏之后结构体无需手写**。未提供宏或需细粒度控制时可手写；无运行时反射。
- **可选 SIMD**：Phase 4 提供 AVX2/NEON 加速，标量路径始终可用

---

## 2. 设计原则（对齐 Uya 特性）

| Uya 特性 | JSON 设计应用 |
|----------|---------------|
| 零 GC / 显式内存 | 解析器使用 Arena 单次分配，编码器接受预分配 buffer 或 Arena |
| 编译期证明 | 结构体 ↔ JSON 由编译器反射宏 to_json / from_json 自动生成，**结构体无需手写**；无宏时可手写，零反射 |
| 错误联合 `!T` | `parse()` 返回 `!JsonValue`；编码当前为 `encode_to` 返回 `!usize`、`encode_into_arena` 返回 `!JsonStrView`（避免 slice 返回值） |
| 指针 / 视图 | 字符串用 `JsonStrView`(ptr+len)；理想为 `&[byte]`，受 slice codegen 限制当前用 ptr+len |
| 无隐式分配 | API 显式要求传入 `&Arena` 或 buffer 容量 |
| `@asm` | 可选 SIMD 分支（AVX2/NEON）用于结构字符扫描 |

---

## 3. JSON 标准范围

- **遵循**：RFC 8259 核心（对象、数组、字符串、数字、布尔、null）
- **支持**：`\uXXXX`、`\n\t\r\"\\` 转义
- **不支持**：注释、尾逗号、单引号
- **UTF-8**：默认不校验（零拷贝优先）；可选 `parse_strict` 启用 UTF-8 校验

---

## 4. 整体架构

```mermaid
flowchart TB
    subgraph Parse [解析流程]
        A[Input: &[byte]] --> B[Stage1: 结构扫描]
        B --> C[Stage2: 构建 Tape]
        C --> D[JsonValue]
    end
    
    subgraph Encode [编码流程]
        E[结构化数据] --> F[ToJson / mc 宏生成或手写]
        F --> G[JsonWriter]
        G --> H[Output: &[byte]]
    end
    
    subgraph Memory [内存]
        I[Arena] --> J[parse 分配]
        K[调用方 buffer] --> G
    end
```

ToJson / FromJson 由编译器反射宏 to_json、from_json 或手写实现；有宏则结构体无需手写。

---

## 5. 核心数据结构

**语法依据**：[grammar_formal.md](grammar_formal.md) 联合体、结构体、指针类型。Uya 指针为 `&T` / `&const T`；联合体变体需为合法标识符（避免关键字 `null`）。

### 5.1 JsonValue（零拷贝值类型）

```uya
union JsonValue {
    json_null: void,    // 对应 JSON null；不用 null 避免与关键字冲突
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str: JsonStrView,   // 当前实现用 (ptr, len) 视图，规避 slice codegen；理想为 &[byte]
    arr: JsonArray,
    obj: JsonObject,
}

struct JsonStrView {
    ptr: &byte,
    len: usize,
}

struct JsonArray {
    items: &JsonValue,  // Arena 分配
    len: usize,
}

struct JsonKeyValue {
    key: JsonStrView,
    value: JsonValue,
}

struct JsonObject {
    pairs: &JsonKeyValue,  // Arena 分配
    len: usize,
}
```

### 5.2 JsonParser（可选，当前解析器未暴露此结构体）

```uya
struct JsonParser {
    input: &[byte],     // 理想形态；当前 parse 使用 (ptr, len) 以规避 slice 参数
    tape: &JsonValue,
    tape_len: usize,
    arena: &Arena,
}
```

### 5.3 访问方式

- `JsonValue` 通过 `match` 访问变体
- 数组：`arr.items[i]`（需证明 `0 <= i < arr.len`）
- 对象：`obj.pairs[i].key`、`obj.pairs[i].value`
- 反序列化见 §7.4（FromJson / from_json）

---

## 6. 解析器（Decoder）

### 6.1 两阶段解析

1. **Stage 1**：扫描结构字符 `{ } [ ] , : "`，构建结构索引（可选 SIMD）
2. **Stage 2**：按需或一次性填充 Tape，所有指针指向 `input` 或 `arena`
3. **数值解析**：手写整数/浮点解析（避免 strtod FFI），溢出/NaN/Inf 返回错误

### 6.2 API

```uya
// 当前实现：用 (ptr, len) 替代 &[byte] 以规避 slice codegen（见 grammar / 实现）
fn parse(arena: &Arena, ptr: &byte, len: usize) !JsonValue;

// 理想 API（待 slice 支持后）
// fn parse(arena: &Arena, input: &[byte]) !JsonValue;

// 懒解析（可选）
// fn parse_lazy(arena: &Arena, input: &[byte]) !JsonDoc;
// fn json_doc_get(doc: &JsonDoc, path: &const byte) !JsonValue;
```

### 6.3 错误类型

语法规范（[grammar_formal.md](grammar_formal.md)）：预定义错误为 `error ID ;`，单条声明。模块名用 `errors` 以免与关键字 `error` 冲突。

```uya
// lib/std/json/errors.uya
export error InvalidUtf8;
export error InvalidEscape;
export error InvalidUnicode;
export error UnexpectedToken;
export error UnexpectedEof;
export error NumberOverflow;
export error InvalidNumber;
export error NestingTooDeep;
export error BufferTooSmall;
// from_json 用
export error NotAnObject;
export error MissingField;
export error WrongType;
```

### 6.4 数值策略

- 整数：`i64`，超出范围报 `NumberOverflow`
- 浮点：`f64`，NaN/Inf 报 `InvalidNumber`

---

## 7. 编码器（Encoder）

### 7.1 ToJson 接口

Uya 指针为 `&T` / `&const T`；接口类型直接使用 `ToJson`（无 `impl` 关键字，见 [grammar_formal.md](grammar_formal.md)、changelog）。

```uya
interface ToJson {
    fn to_json(self: &Self, writer: &JsonWriter) void;
}
```

### 7.2 API

```uya
fn encode_to(value: &ToJson, buf: &byte, cap: usize) !usize;
fn encode_into_arena(arena: &Arena, value: &JsonValue) !JsonStrView;  // 当前实现，避免 !&[byte] 返回值
// fn encode(arena: &Arena, value: &ToJson) !&[byte];  // 可选，依赖 slice 返回值 codegen
```

### 7.3 结构体序列化（to_json）

**宏 to_json 利用编译器反射实现自动结构体序列化；有宏之后结构体无需手写**。未提供宏或需细粒度控制时可手写 ToJson（见 `tests/test_json_struct_roundtrip.uya`）。

### 7.4 结构体反序列化（from_json）

- **FromJson 接口**：`fn from_json(arena: &Arena, v: &JsonValue) !Self`（从 JsonValue 对象变体按字段名解析并填充结构体，失败返回错误）。
- **宏 from_json 利用编译器反射实现自动结构体反序列化；有宏之后结构体无需手写**。未提供宏或需细粒度控制时可手写。与 to_json 对称，实现 roundtrip。
- **手写辅助**：`json_object_find_index(o, key_ptr, key_len) !usize`；`json_expect_i64(v) !i64`、`json_expect_str(v) !JsonStrView`、`json_expect_bool(v) !bool`、`json_expect_f64(v) !f64`（类型不符返回 WrongType；f64 接受 int_val 自动转 float）；`json_str_view_eq`。调用方在同一作用域内用 `o.pairs[idx].value`，不返回/存储 `&JsonValue`（零 UB）。

---

## 8. 模块与文件规划

```
lib/std/json/
  json.uya          # 模块入口，重导出
  value.uya         # JsonValue、JsonStrView、JsonArray、JsonObject、JsonKeyValue
  errors.uya        # 错误定义（命名 errors 避免与关键字 error 冲突，见 grammar）
  parser.uya        # parse(arena, ptr, len)、解析逻辑
  encoder.uya       # JsonWriter、encode_to、encode_into_arena、ToJson、encode_to_to_json
  impl.uya          # 可选：基础类型 ToJson 实现
  impl_macro.uya    # 可选：利用编译器反射的 to_json/from_json 宏（规范 §25），有宏之后结构体无需手写，自动生成序列化/反序列化
```

---

## 9. 依赖与约束

- **Arena**：依赖 `src/arena.uya` 或新增 `std.mem.arena`；若无则退化为 libc
- **std.mem**：mem_copy 等
- **std.string**：UTF-8 校验（可选）
- **SIMD**：Phase 4 可选，标量必须能独立工作

---

## 10. 性能目标

| 阶段 | 目标 | 参考 |
|------|------|------|
| Phase 1（标量） | 0.2–0.5 GB/s | serde_json / RapidJSON |
| Phase 4（SIMD） | 1–3 GB/s | simd-json / sonic-rs |
| 编码 | 0.3–1 GB/s | 编译期 mc 宏或手写 to_json，无反射 |

### 10.1 Benchmark 方案

- **数据集**：twitter.json、citm_catalog.json、canada.json
- **方法**：单线程、热缓存、多次运行取中位数，单位 GB/s

---

## 11. 与其他语言库对比

| 语言/库 | 解析吞吐量 |
|---------|------------|
| C++ simdjson | 4–14 GB/s |
| Rust simd-json | 0.7–1.2 GB/s |
| Rust serde_json | 0.3–0.9 GB/s |
| C++ RapidJSON | 0.3–0.9 GB/s |
| Go encoding/json | ~0.1–0.3 GB/s |
| Java Jackson | ~0.05–0.2 GB/s |

Uya 设计目标：Phase 1 接近 RapidJSON；Phase 4 接近 simd-json；明显优于 Go/Java。
