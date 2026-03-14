# Uya 高性能 JSON 编解码器设计文档

**版本**：v0.1  
**状态**：设计阶段  
**参考**：RFC 8259、simdjson、[.cursor/plans/uya_json_编解码器设计_da1b7f6b.plan.md](../.cursor/plans/uya_json_编解码器设计_da1b7f6b.plan.md)

---

## 1. 概述

本文档定义 Uya 标准库的 JSON 编解码器设计，基于 Uya 的零 GC、编译期证明、显式内存控制、切片零拷贝等特性，实现高性能 JSON 解析与编码，目标性能接近 C/Rust 高性能库（serde_json、simd-json 水平），明显优于 Go/Java 标准库。

### 1.1 设计目标

- **零拷贝**：字符串值直接引用输入 buffer，不复制
- **单次分配**：解析阶段使用 Arena，一次分配得到 Tape
- **显式内存**：API 要求调用方传入 Arena 或预分配 buffer
- **编译期序列化**：结构体通过宏生成 to_json，无运行时反射
- **可选 SIMD**：Phase 4 提供 AVX2/NEON 加速，标量路径始终可用

---

## 2. 设计原则（对齐 Uya 特性）

| Uya 特性 | JSON 设计应用 |
|----------|---------------|
| 零 GC / 显式内存 | 解析器使用 Arena 单次分配，编码器接受预分配 buffer 或 Arena |
| 编译期证明 | 结构体 → JSON 映射在编译期由宏生成，零反射 |
| 错误联合 `!T` | `parse()` 返回 `!JsonValue`，`encode()` 返回 `!&[byte]` |
| 切片 `&[T]` | 字符串值返回 `&[byte]` 视图，直接指向输入 buffer |
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
        E[结构化数据] --> F[ToJson / 宏生成]
        F --> G[JsonWriter]
        G --> H[Output: &[byte]]
    end
    
    subgraph Memory [内存]
        I[Arena] --> J[parse 分配]
        K[调用方 buffer] --> G
    end
```

---

## 5. 核心数据结构

### 5.1 JsonValue（零拷贝值类型）

```uya
union JsonValue {
    null,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str: &[byte],       // 指向输入 buffer，零拷贝
    arr: JsonArray,
    obj: JsonObject,
}

struct JsonArray {
    items: &JsonValue,  // Arena 分配
    len: usize,
}

struct JsonKeyValue {
    key: &[byte],       // 键名视图
    value: JsonValue,
}

struct JsonObject {
    pairs: &JsonKeyValue,  // Arena 分配
    len: usize,
}
```

### 5.2 JsonParser

```uya
struct JsonParser {
    input: &[byte],
    tape: &JsonValue,
    tape_len: usize,
    arena: &Arena,
}
```

### 5.3 访问方式

- `JsonValue` 通过 `match` 访问变体
- 数组：`arr.items[i]`（需证明 `0 <= i < arr.len`）
- 对象：`obj.pairs[i].key`、`obj.pairs[i].value`

---

## 6. 解析器（Decoder）

### 6.1 两阶段解析

1. **Stage 1**：扫描结构字符 `{ } [ ] , : "`，构建结构索引（可选 SIMD）
2. **Stage 2**：按需或一次性填充 Tape，所有指针指向 `input` 或 `arena`
3. **数值解析**：手写整数/浮点解析（避免 strtod FFI），溢出/NaN/Inf 返回错误

### 6.2 API

```uya
fn parse(arena: &Arena, input: &[byte]) !JsonValue;

// 懒解析（可选）
fn parse_lazy(arena: &Arena, input: &[byte]) !JsonDoc;
fn json_doc_get(doc: &JsonDoc, path: &const byte) !JsonValue;  // 路径先支持简单链式
```

### 6.3 错误类型

```uya
error {
    InvalidUtf8,
    InvalidEscape,
    InvalidUnicode,
    UnexpectedToken,
    UnexpectedEof,
    NumberOverflow,
    InvalidNumber,
    NestingTooDeep,
}
```

### 6.4 数值策略

- 整数：`i64`，超出范围报 `NumberOverflow`
- 浮点：`f64`，NaN/Inf 报 `InvalidNumber`

---

## 7. 编码器（Encoder）

### 7.1 ToJson 接口

```uya
interface ToJson {
    fn to_json(self: &Self, writer: &mut JsonWriter) void;
}
```

### 7.2 API

```uya
fn encode_to(value: &impl ToJson, buf: &byte, cap: usize) !usize;
fn encode(arena: &Arena, value: &impl ToJson) !&[byte];
```

### 7.3 宏驱动结构体序列化

```uya
struct User {
    id: i64,
    name: &[byte],
}
// 宏生成 to_json
impl_json!(User);
```

若 `@mc` 不成熟，则手写 `fn to_json`。

---

## 8. 模块与文件规划

```
lib/std/json/
  json.uya          # 模块入口，重导出
  value.uya         # JsonValue、JsonArray、JsonObject、JsonKeyValue
  error.uya         # 错误定义
  parser.uya        # JsonParser、parse、parse_lazy
  encoder.uya       # JsonWriter、encode、encode_to
  impl.uya          # 基础类型 ToJson 实现（i32、i64、f64、bool、&[byte] 等）
  impl_macro.uya    # 可选：impl_json! 宏
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
| 编码 | 0.3–1 GB/s | 编译期宏，无反射 |

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
