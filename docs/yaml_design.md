# Uya 高性能 YAML 编解码器设计文档

**版本**：v0.1  
**状态**：设计阶段  
**参考**：YAML 1.2 规范、RapidYAML、[json_design.md](json_design.md)

---

## 1. 概述

本文档定义 Uya 标准库的 YAML 编解码器设计，基于 Uya 的零 GC、编译期证明、显式内存控制、切片零拷贝等特性，实现高性能 YAML 子集解析与编码。目标：Phase 1 接近 RapidYAML 水平，明显优于 Go/Java 标准库；Phase 1 优先 Flow 风格，最大化复用 std.json 解析器。

### 1.1 设计目标

- **零拷贝**：字符串值直接引用输入 buffer，不复制
- **单次分配**：解析阶段使用 Arena，一次分配得到 Tape
- **显式内存**：API 要求调用方传入 Arena 或预分配 buffer
- **编译期序列化**：结构体通过宏生成 to_yaml，无运行时反射
- **子集策略**：先 Flow 风格（接近 JSON），再扩展 Block、块标量、多文档、锚点（带安全限制）

---

## 2. 设计原则（对齐 Uya 特性）

| Uya 特性 | YAML 设计应用 |
|----------|---------------|
| 零 GC / 显式内存 | 解析器使用 Arena 单次分配，编码器接受预分配 buffer 或 Arena |
| 编译期证明 | 结构体 → YAML 映射在编译期由宏生成，零反射 |
| 错误联合 `!T` | `parse()` 返回 `!YamlValue`，`encode()` 返回 `!&[byte]` |
| 切片 `&[T]` | 字符串值返回 `&[byte]` 视图，直接指向输入 buffer |
| 无隐式分配 | API 显式要求传入 `&Arena` 或 buffer 容量 |
| `@vector`/`@mask`、`@asm` | 可选 SIMD（与 std.json 思路一致：优先 `@vector`，可选 `@asm`） |

---

## 3. YAML 标准范围与子集策略

### 3.1 Phase 1：Flow 风格（JSON 兼容子集）

- **首选路径**：仅支持 Flow 风格 `{key: value}`、`[a, b, c]`，最大化复用 std.json 解析
- **Phase 1 的「JSON 兼容」定义**：语法兼容（Flow 与 JSON 括号结构一致）+ 类型兼容（null、bool、数字、字符串、数组、对象）；YAML 特有字面量（如 `yes`/`no`）按 YAML 规则解析，输出统一到 YamlValue
- **YAML Flow 与 JSON 差异**：
  - key 可无引号
  - 布尔支持 `yes`/`no`/`true`/`false`/`on`/`off`
  - 需扩展 JSON 词法/语法
- **备选**：若 Flow 扩展成本高，则改为实现简单 Block 映射（`key: value` + 缩进栈），不依赖 JSON 后端

### 3.2 Phase 2：Block 风格

- Block 映射：`key: value` 通过缩进栈解析
- Block 序列：`- item` 列表

### 3.3 Phase 3：块标量与多文档

- 块标量：`|`（字面量）、`>`（折叠）
- 多文档：`---` 分隔，API 返回 `&[YamlValue]` 或迭代器

### 3.4 Phase 4：锚点/别名（可选，带安全限制）

- `&anchor` / `*alias`，可导致指数膨胀（YAML 炸弹）
- **限制**：深度上限、别名引用次数上限，超出报错

### 3.5 不支持与限制

| 特性 | 支持情况 |
|------|----------|
| Tab 缩进 | 不支持，遇到 Tab 报 `InvalidIndent`，强制空格 |
| 复杂标签 | 不支持 `!!binary`、`!!omap` 等 |
| 锚点（无限制） | 不支持，仅 Phase 4 带深度/次数限制 |
| 多行字符串（块标量） | Phase 3 支持 |

---

## 4. 与 std.json 关系

- **Phase 1** 若采用 Flow 风格，可复用 std.json 解析器并扩展 YAML 特有词法
- **互操作**：提供 `yaml_value_to_json_value` / `json_value_to_yaml_value` 转换函数
- **内存布局**：YamlValue 与 JsonValue 结构对称，可共用布局

---

## 5. 整体架构

```mermaid
flowchart TB
    subgraph Parse [解析流程]
        A[Input: &[byte]] --> B[词法/结构扫描]
        B --> C[构建 Tape]
        C --> D[YamlValue]
    end

    subgraph Encode [编码流程]
        E[结构化数据] --> F[ToYaml / 宏生成]
        F --> G[YamlWriter]
        G --> H[Output: &[byte]]
    end

    subgraph Memory [内存]
        I[Arena] --> J[parse 分配]
        K[调用方 buffer] --> G
    end
```

---

## 6. 核心数据结构

### 6.1 YamlValue（零拷贝值类型）

```uya
union YamlValue {
    null,
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    str: &[byte],       // 指向输入 buffer，零拷贝
    arr: YamlArray,
    obj: YamlObject,
}

struct YamlArray {
    items: &YamlValue,  // Arena 分配
    len: usize,
}

struct YamlKeyValue {
    key: &[byte],       // 键名视图
    value: YamlValue,
}

struct YamlObject {
    pairs: &YamlKeyValue,  // Arena 分配
    len: usize,
}
```

### 6.2 多文档

```uya
// 单文档
fn parse(arena: &Arena, input: &[byte]) !YamlValue;

// 多文档
fn parse_multi(arena: &Arena, input: &[byte]) !&[YamlValue];
```

---

## 7. 解析器（Decoder）

### 7.1 两阶段解析

1. **Stage 1**：扫描结构字符（Flow：`{ } [ ] , : "`；Block：缩进、`-`、`:`）
2. **Stage 2**：填充 Tape，指针指向 `input` 或 `arena`
3. **数值解析**：与 JSON 一致，手写整数/浮点解析

### 7.2 API

```uya
fn parse(arena: &Arena, input: &[byte]) !YamlValue;
fn parse_multi(arena: &Arena, input: &[byte]) !&[YamlValue];  // Phase 3
```

### 7.3 错误类型

```uya
error {
    InvalidUtf8,
    InvalidEscape,
    InvalidScalar,
    UnexpectedToken,
    UnexpectedEof,
    InvalidIndent,      // Tab 或缩进错误
    NumberOverflow,
    InvalidNumber,
    NestingTooDeep,
    AnchorTooDeep,      // Phase 4：锚点深度超限
    AnchorOverflow,     // Phase 4：引用次数超限
}
```

---

## 8. 编码器（Encoder）

### 8.1 ToYaml 接口

```uya
interface ToYaml {
    fn to_yaml(self: &Self, writer: &mut YamlWriter) void;
}
```

### 8.2 API

```uya
fn encode_to(value: &impl ToYaml, buf: &byte, cap: usize, style: YamlEncodeStyle) !usize;
fn encode(arena: &Arena, value: &impl ToYaml, style: YamlEncodeStyle) !&[byte];
```

### 8.3 输出风格

- `Flow`：`{key: value}`、`[a, b]`（与 JSON 接近）
- `Block`：缩进风格（Phase 2 后支持）

---

## 9. 模块与文件规划

```
lib/std/yaml/
  yaml.uya          # 模块入口，重导出
  value.uya         # YamlValue、YamlArray、YamlObject、YamlKeyValue
  error.uya         # 错误定义
  parser.uya        # 解析器、parse、parse_multi
  encoder.uya       # YamlWriter、encode、encode_to
  impl.uya          # 基础类型 ToYaml 实现
  impl_macro.uya    # 可选：impl_yaml! 宏
  convert.uya       # yaml_value_to_json_value、json_value_to_yaml_value
```

---

## 10. 依赖与约束

- **Arena**：与 std.json 共用
- **std.json**：Phase 1 可复用解析逻辑；convert 模块依赖 JsonValue
- **std.mem**：mem_copy 等
- **std.string**：UTF-8 校验（可选）

---

## 11. 性能目标

| 阶段 | 目标 | 参考 |
|------|------|------|
| Phase 1（Flow 标量） | 0.2–0.5 GB/s | RapidYAML、RapidJSON |
| Phase 4（可选 SIMD） | 0.5–1.5 GB/s | 与 std.json 共用 SIMD 思路 |
| 编码 | 0.3–1 GB/s | 编译期宏，无反射 |

### 11.1 Benchmark 方案

- **数据集**：[YAML 官方测试矩阵](https://matrix.yaml.info/)、RapidYAML 仓库典型 YAML 文件
- **共用**：Flow 风格可与 JSON benchmark 共用部分数据集
- **方法**：单线程、热缓存、多次运行取中位数，单位 GB/s

---

## 12. 与主流库对比

| 库 | 语言 | 特点 |
|----|------|------|
| RapidYAML | C++ | 零拷贝、高性能，YAML 1.2 子集 |
| libyaml | C | 官方实现，功能全，性能中等 |
| yaml-cpp | C++ | 易用，功能全 |
| Go gopkg.in/yaml | Go | 标准选择，性能一般 |
| Java SnakeYAML | Java | 功能全，存在反序列化风险 |

Uya 设计目标：Phase 1 接近 RapidYAML；子集优先，安全限制锚点。
