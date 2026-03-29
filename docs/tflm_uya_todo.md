# TFLM 纯 Uya 实现 — 待办清单

与 [tflm_uya_design.md](tflm_uya_design.md) 配合：设计文档定「做什么、长什么样」，本文档定「按什么顺序做、做到什么算完成」。

---

## 阶段 1：MVP（模型 + 内存 + 解释器 + 基础算子）

- [x] **common**（`lib/tflm/common/common.uya`）：错误码（含 `ResolverFull`）、`Context`、`BuiltinOperator`、`TFLITE_VERSION`。（当前 Uya 无法在结构体中存放 `fn(...) !void` 数组，故未定义 `PrepareFn`/`EvalFn` 类型别名；见 resolver / interpreter 说明。）
- [x] **model**（`lib/tflm/model/model.uya`）：Phase 1 **线性 stub** `ModelPlan` + `load_model_plan` / `model_plan_opcode_at`（固定小端头 + opcode 列表）；**非**完整 FlatBuffer，后续可替换为真 `.tflite` 解析。
- [x] **arena**（`lib/tflm/arena/arena.uya`）：`ArenaAllocator`、`align_forward`、`arena_allocate`（返回 `&byte`）、`arena_reset`；非法非 2 幂 alignment → `InvalidAlignment`。
- [x] **tensor**（`lib/tflm/tensor/tensor.uya`）：`TensorView`（`data: &byte`、`bytes`、`TensorType`、`tensor_elem_count`）。
- [x] **resolver**（`lib/tflm/resolver/resolver.uya`）：`OpResolver` 仅存已注册 `BuiltinOperator`；`register_op`、`resolver_has`。（函数指针表待语言支持后对齐设计文档 §5.1。）
- [x] **interpreter**（`lib/tflm/interpreter/interpreter.uya`）：`Interpreter`、`invoke`；在 `invoke` 内对算子 **match 分发** 至 `kernels` 的 prepare/eval。
- [x] **kernels**（`lib/tflm/kernels/kernels.uya`）：Conv2D（1×1）、DepthwiseConv2D（3×3 valid）、FullyConnected（i32）、Softmax（f32 + `libc exp`）的 prepare/eval。
- [x] **测试**：`test_tflm_model.uya`、`test_tflm_arena.uya`、`test_tflm_interpreter.uya`；`make check`（`--c99` + `--uya --c99` + `--safety-proof`）通过。

**验收**：stub 模型加载、Arena 分配与对齐校验、注册算子后 `invoke` 跑通 **FullyConnected**；同测文件内对 Conv / Depthwise / Softmax 做直接 eval smoke。**模块路径**：`lib/tflm/<模块>/<模块>.uya` → `use tflm.<模块>`（与 `std.protobuf.*` 同级规则）。

---

## 阶段 2：优化与扩展

- [x] **CMSIS-NN 集成**：`lib/tflm/backend/backend.uya` 中 `extern` + `tflm_arm_conv_hwc_q7_basic` 包装 `arm_convolve_HWC_q7_basic`；边界检查后 `&buf[0] as *i8` 等传参。CI 主机用 `tests/tflm_cmsis_host_stub.c`（`test_tflm_cmsis` 在 `run_programs_parallel.sh` / `tests/Makefile` 中额外链接）；真机替换为 CMSIS-NN。
- [x] **更多算子**：`AVERAGE_POOL_2D` / `MAX_POOL_2D`（2×2、stride 2、valid、HWC i32）、`RELU`（i32/f32）、`RESHAPE`（同类型、同元素数 memcpy）；`BuiltinOperator` 与 `interpreter` 分发已对齐 TFLite 枚举值（1 / 17 / 19 / 22）。
- [x] **量化**：`lib/tflm/quant/quant.uya` 提供 `quant_sat_i32_to_i8`、`quant_mul_i32_shift_sat`；`TensorType.tt_int8` 与 `tensor_elem_byte_size` 供后续 int8 算子接表。
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
