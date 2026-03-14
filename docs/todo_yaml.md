# Uya YAML 编解码器实现待办

**参考**：[yaml_design.md](yaml_design.md)

实现时遵循项目 TDD 流程：先添加测试 → 实现代码 → `make check` 验证。

---

## Phase 1：Flow 风格解析器（复用 std.json 扩展）

### 1.1 前置依赖

- [ ] std.json Phase 1 已具备可用的 parse、JsonValue、Arena
- [ ] 确认 Arena 接口：`arena_alloc` / `arena_reset` 或等效

### 1.2 扩展 JSON 词法/语法

- [ ] 无引号 key：`key: value` 中 key 可为 bare word
- [ ] YAML 布尔字面量：`yes`、`no`、`true`、`false`、`on`、`off`
- [ ] 复用 JSON 的 `null`、数字、字符串、数组、对象解析

### 1.3 数据结构

- [ ] 创建 `lib/std/yaml/` 目录
- [ ] `error.uya`：定义 YAML 错误（InvalidUtf8、InvalidEscape、InvalidScalar、UnexpectedToken、UnexpectedEof、InvalidIndent、NumberOverflow、InvalidNumber、NestingTooDeep 等）
- [ ] `value.uya`：`YamlValue` union、`YamlArray`、`YamlKeyValue`、`YamlObject` 结构体（与 JsonValue 结构对称）

### 1.4 解析器

- [ ] `parser.uya`：实现 `parse(arena, input) !YamlValue`
  - [ ] 优先调用 std.json 解析（Flow 与 JSON 兼容部分）
  - [ ] 扩展词法处理无引号 key、yes/no 等
  - [ ] 错误位置报告（行/列或偏移）

### 1.5 测试

- [ ] `tests/test_yaml_parse_flow_basic.uya`：null、bool（含 yes/no）、数字、字符串
- [ ] `tests/test_yaml_parse_flow_array.uya`：空数组、嵌套数组
- [ ] `tests/test_yaml_parse_flow_object.uya`：无引号 key、嵌套对象
- [ ] `tests/error_yaml_*.uya`：预期解析失败用例（Tab 缩进、非法字符等）

---

## Phase 2：编码器与 ToYaml

### 2.1 YamlWriter

- [ ] `encoder.uya`：`YamlWriter` 结构体（buffer + 写入位置）
- [ ] `write_null`、`write_bool`、`write_i64`、`write_f64`
- [ ] `write_string`（转义处理）
- [ ] `write_array_start`、`write_array_end`、`write_object_start`、`write_object_end`
- [ ] 支持 Flow 风格输出（默认）

### 2.2 基础类型 ToYaml

- [ ] `impl.uya`：为 i32、i64、f64、bool、`&[byte]` 实现 ToYaml（若接口可用）或提供 `yaml_write_*` 函数

### 2.3 API

- [ ] `encode_to(value, buf, cap, style) !usize`
- [ ] `encode(arena, value, style) !&[byte]`
- [ ] `YamlEncodeStyle`：Flow / Block（Phase 3 实现 Block）

### 2.4 与 std.json 互操作

- [ ] `convert.uya`：`yaml_value_to_json_value`、`json_value_to_yaml_value`

### 2.5 测试

- [ ] `tests/test_yaml_encode_basic.uya`：基础类型 roundtrip
- [ ] `tests/test_yaml_encode_flow.uya`：Flow 风格 encode
- [ ] `tests/test_yaml_json_convert.uya`：YamlValue ↔ JsonValue 转换

---

## Phase 3：Block 风格与块标量

### 3.1 Block 解析

- [ ] Block 映射：`key: value` + 缩进栈
- [ ] Block 序列：`- item` 列表
- [ ] 缩进规则：仅空格，Tab 报错
- [ ] 扩展 `parse` 支持 Block 风格输入

### 3.2 块标量

- [ ] `|` 字面量块
- [ ] `>` 折叠块

### 3.3 Block 编码

- [ ] `YamlEncodeStyle.Block` 输出
- [ ] 块标量编码

### 3.4 多文档

- [ ] `parse_multi(arena, input) !&[YamlValue]`
- [ ] `---` 分隔符解析

### 3.5 测试

- [ ] `tests/test_yaml_parse_block.uya`
- [ ] `tests/test_yaml_parse_block_scalar.uya`
- [ ] `tests/test_yaml_parse_multi.uya`
- [ ] `tests/error_yaml_tab.uya`：Tab 缩进预期失败

---

## Phase 4：锚点/别名（可选，带安全限制）

- [ ] 解析 `&anchor`、`*alias`
- [ ] 深度上限（如 64）、别名引用次数上限（如 1024）
- [ ] 超出限制报 `AnchorTooDeep` 或 `AnchorOverflow`
- [ ] 编码时可选输出锚点
- [ ] 测试 YAML 炸弹防护

---

## Benchmark

- [ ] 获取 YAML 官方测试矩阵或 RapidYAML 仓库典型 YAML 文件
- [ ] Flow 风格可与 JSON benchmark 共用部分数据集
- [ ] 编写 `tests/bench_yaml.uya` 或独立 benchmark 脚本
- [ ] 记录 Phase 1 / Phase 4 吞吐量（GB/s）

---

## 与主待办集成

- [x] 已在 [todo_mini_to_full.md](todo_mini_to_full.md) 第 39 项添加 **std.yaml** 条目
