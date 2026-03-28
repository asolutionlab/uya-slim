# TFLM 纯 Uya 实现 — 计划索引

本页为 TensorFlow Lite Micro 风格嵌入式推理引擎的**纯 Uya 实现**在 Uya 仓库中的计划与文档入口。

---

## 文档

- **[tflm_uya_design.md](tflm_uya_design.md)** — 详细设计：目标与约束、总体架构、模型/内存/算子/解释器各层接口与数据结构、数据流、测试策略、路线图与风险。
- **[tflm_uya_todo.md](tflm_uya_todo.md)** — 待办清单：阶段 1～3 的任务项、验收标准与依赖。

---

## 约定

- **库根目录**：`lib/tflm/`。**模块路径**：`UYA_ROOT=lib/` 时，`lib/tflm/common.uya` → `use tflm.common`，`lib/tflm/kernels/conv.uya` → `use tflm.kernels.conv`。
- **测试位置**：`tests/` 根目录，文件命名 `test_tflm_*.uya`；需通过 `--c99` 与 `--uya --c99`（见 [.cursorrules](../.cursorrules)）。
- **验证**：所有 `test_tflm_*.uya` 需通过 `./tests/run_programs_parallel.sh --c99` 与 `--uya --c99`。

---

## 与 TFLM 的对应关系

| 本库模块           | TFLM 对应                    |
|--------------------|-----------------------------|
| lib/tflm/model.uya | 模型加载、FlatBuffer 解析   |
| lib/tflm/arena.uya| MicroAllocator / 张量 Arena |
| lib/tflm/tensor.uya| TfLiteTensor 视图           |
| lib/tflm/resolver.uya | MicroMutableOpResolver   |
| lib/tflm/interpreter.uya | MicroInterpreter      |
| lib/tflm/kernels/* | 各类 BuiltinOperator 内核   |

---

## 参考

- [uya.md](uya.md) — Uya 语言规范。
- [tflm_uya_design.md](tflm_uya_design.md) — 详细设计与接口说明。
- TensorFlow Lite Micro：<https://github.com/tensorflow/tflite-micro>；FlatBuffer schema：`tflite/schema/schema.fbs`。
