# TFLM 纯 Uya 实现 — 待办清单

与 [tflm_uya_design.md](tflm_uya_design.md) 配合：设计文档定「做什么、长什么样」，本文档定「按什么顺序做、做到什么算完成」。

---

## 阶段 1：MVP（模型 + 内存 + 解释器 + 基础算子）

- [ ] **common.uya**：定义错误码（`error.ModelTooShort`、`error.VersionMismatch`、`error.ModelCorrupted`、`error.OpNotSupported`、`error.ArenaExhausted`、`error.InvalidAlignment`、`error.DimensionMismatch`、`error.BufferTooSmall` 等）、`Context` 类型（或放在 context.uya）、`PrepareFn`/`EvalFn` 类型别名、`BuiltinOperator` 枚举、`TFLITE_VERSION` 等常量。
- [ ] **model.uya**：最小 FlatBuffer 解析（`ModelHeader`、`load_model(data: &[u8]) !&const ModelHeader`）；子图/算子/张量访问接口（可先写死偏移或手写常量）。
- [ ] **arena.uya**：`ArenaAllocator`、`align_forward`、`allocate(allocator, size, alignment) !&void`。可选：在 `allocate` 内检查 `alignment != 0` 且为 2 的幂，否则返回 `error.InvalidAlignment`。
- [ ] **tensor.uya**：张量视图结构体（dims、dim_count、type、**data 为指向首元素的指针** &byte 或 &void，可选 bytes 字段）；与 TFLite 语义一致；FFI 传参使用 `tensor.data as *i8`。
- [ ] **resolver.uya**：`OpResolver`（prepare/eval 函数指针数组）、`register_op`、`find(...) !(PrepareFn, EvalFn)`（返回元组，调用方解构为 prepare/eval）。
- [ ] **interpreter.uya**：`Interpreter`、`Context`、`invoke(interpreter) !void` 主循环；`get_subgraph`、`get_operator`、`fill_context` 等辅助。
- [ ] **kernels**：至少实现 Conv2D、DepthwiseConv2D、FullyConnected、Softmax 的 prepare/eval（可先纯 Uya 实现，不依赖 CMSIS-NN）。
- [ ] **测试**：`test_tflm_model.uya`、`test_tflm_arena.uya`、`test_tflm_interpreter.uya`（最小单算子模型）；全部通过 `--c99` 与 `--uya --c99`。

**验收**：能加载最小 .tflite 模型、分配 Arena、注册并执行至少一个算子，输出与预期一致。

---

## 阶段 2：优化与扩展

- [ ] **CMSIS-NN 集成**：在 `kernels/conv.uya`（或 `backend/arm.uya`）中 `extern` 声明并包装 `arm_convolve_HWC_q7_basic` 等；Uya 侧做边界检查后通过 `&buf[0] as *i8` 传参。
- [ ] **更多算子**：Pooling、Activation、Reshape 等按 TFLite BuiltinOperator 逐步添加。
- [ ] **量化**：int8 量化参数与 requantize 逻辑完善；饱和运算与规范对齐（若使用 `+|`、`+%` 等）。
- [ ] **测试**：与 TFLite 转换的 .tflite 模型对比（相同输入下输出一致），可选。

**验收**：在目标 MCU（如 Cortex-M4）上跑通带 CMSIS-NN 的 Conv2D，代码体积与延迟可接受。

---

## 阶段 3：可选扩展

- [ ] **多后端**：编译期选择 ARM vs 通用实现（依赖 `TARGET_ARCH` 或宏/构建系统，见设计文档 §7）。
- [ ] **工具链**：内存使用分析（编译期或运行时峰值）、算子融合等，按需规划。
- [ ] **@offset_of**：若 Uya 增加该内置，用于 FlatBuffer 偏移编译期验证；当前用手写常量或运行时检查。

---

## 依赖与参考

- Uya 编译器需支持：`!T`、`try`/`catch`、`defer`/`errdefer`、`extern`、`as` 指针转换、`@size_of`、`@len`（见 [uya.md](uya.md)、[grammar_quick.md](grammar_quick.md)）。
- TFLite schema：<https://github.com/tensorflow/tflite-micro/blob/main/tflite/schema/schema.fbs>。
- 开发分支建议：`feature/tflm-pure-uya`（或与主仓库约定一致）。
