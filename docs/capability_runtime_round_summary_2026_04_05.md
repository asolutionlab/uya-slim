# Capability Runtime 轮次总结（2026-04-05）

**日期**：2026-04-05  
**范围**：穿戴设备 capability runtime / 微容器方向 / WAMR 对比 / TDD 基线  
**适用对象**：后续继续推进 capability runtime、微容器、WASM 后端的人

---

## 1. 本轮结论

本轮讨论的核心结论是：

1. `微容器` 在当前项目语境下，不应仅被理解为“通用容器”，而应被收敛为：
   - 面向无 App 手表的轻量能力运行时
   - 其对外价值是“安全下发、受限执行、可回滚的插件/能力容器”

2. `capability runtime` 应作为上层统一抽象存在：
   - 负责包协议、权限、生命周期、Host API、benchmark 口径
   - 不直接绑定某一种执行后端

3. 在执行后端上，当前建议不是立即二选一，而是保持兼容层：
   - `Native Uya` 后端
   - `WAMR` 后端
   - 以及用于联调的 `Fake` 后端

4. 若目标是先验证商业闭环，`WAMR` 比完全自定义执行器更现实：
   - 工作量更低
   - sandbox 语义更成熟
   - 更适合做“先变现”的 MVP

5. 若目标是长期做设备侧护城河，自定义微容器/执行器仍有价值：
   - 更可控
   - 更容易针对 ROM/RAM/功耗做极限裁剪
   - 更适合在产品验证后逐步替换关键路径

6. 正确的工程方向不是“先证明谁更快”，而是：
   - 先做最大兼容层
   - 再用统一 benchmark 去比较 `WAMR` 与 `Native Uya`

---

## 2. 为什么转向 Capability Runtime

本轮讨论不是单纯新增一个模块，而是对“微容器”方向做了重新定义。

当前项目里，“微容器”不再主要指服务器上的通用容器语义，而是指：

- 无 App 穿戴设备上的能力执行载体
- 有权限、签名、版本、回滚、Host API 边界的运行时单元

因此，`capability runtime` 是更准确的上层名称：

- `capability` 回答：这是什么能力、能做什么、怎样被装载和管理
- 执行后端回答：这个能力最后如何被安全执行
- 微容器只是执行后端的一个实现方向，而不是上层产品协议本身

---

## 3. 当前仓库状态

截至本轮结束，`lib/std/runtime/capability/` 已形成一条比较完整的最小骨架，目前目录下共有 **15** 个文件：

- [capability.uya](../lib/std/runtime/capability/capability.uya)
- [types.uya](../lib/std/runtime/capability/types.uya)
- [manifest.uya](../lib/std/runtime/capability/manifest.uya)
- [policy.uya](../lib/std/runtime/capability/policy.uya)
- [abi.uya](../lib/std/runtime/capability/abi.uya)
- [registry.uya](../lib/std/runtime/capability/registry.uya)
- [loader.uya](../lib/std/runtime/capability/loader.uya)
- [hostapi.uya](../lib/std/runtime/capability/hostapi.uya)
- [backend.uya](../lib/std/runtime/capability/backend.uya)
- [fake_backend.uya](../lib/std/runtime/capability/fake_backend.uya)
- [native_backend.uya](../lib/std/runtime/capability/native_backend.uya)
- [wamr_backend.uya](../lib/std/runtime/capability/wamr_backend.uya)
- [adapter.uya](../lib/std/runtime/capability/adapter.uya)
- [manager.uya](../lib/std/runtime/capability/manager.uya)
- [benchmark.uya](../lib/std/runtime/capability/benchmark.uya)

能力层相关测试与脚本也已经存在：

- [test_capability_runtime_compat.uya](../tests/test_capability_runtime_compat.uya)
- [bench_capability_runtime.uya](../tests/bench_capability_runtime.uya)
- [run_capability_runtime_compat.sh](../tests/run_capability_runtime_compat.sh)
- [run_capability_runtime_benchmark.sh](../tests/run_capability_runtime_benchmark.sh)
- [compare_capability_runtime_benchmark.py](../tests/compare_capability_runtime_benchmark.py)

---

## 4. 本轮落下来的文档

本轮围绕 capability runtime 补了几份关键设计文档：

- [capability_manifest.md](../docs/capability_manifest.md)
  - 定义能力包协议、资源限制、权限、签名、触发器

- [capability_backend_compat.md](../docs/capability_backend_compat.md)
  - 定义 `WAMR / Native Uya` 共存时的最大兼容层
  - 明确统一 backend interface、Host API、benchmark 口径

这些文档的意义不是单独成文，而是已经和仓库里的 capability 代码骨架开始对齐：

- `manifest` 已映射到 `CapabilityManifest`
- `runtime.backend` 已映射到 `CapabilityBackendKind`
- `compat layer` 已映射到 `backend/adapter/manager`

---

## 5. 当前代码层的结构理解

### 5.1 协议层

这一层主要由以下文件承载：

- [manifest.uya](../lib/std/runtime/capability/manifest.uya)
- [types.uya](../lib/std/runtime/capability/types.uya)
- [policy.uya](../lib/std/runtime/capability/policy.uya)
- [abi.uya](../lib/std/runtime/capability/abi.uya)

当前已固定的关键元素包括：

- `CapabilityBackendKind`
  - `Fake`
  - `Wamr`
  - `NativeUya`

- `CapabilityPermissionId`
- `CapabilityState`
- `CapabilityStatusCode`
- `CapabilityManifest`
- `CapabilityExecutionContext`

### 5.2 生命周期层

这一层主要由以下文件承载：

- [registry.uya](../lib/std/runtime/capability/registry.uya)
- [loader.uya](../lib/std/runtime/capability/loader.uya)
- [manager.uya](../lib/std/runtime/capability/manager.uya)

当前已经具备最小闭环：

- install
- load
- activate
- invoke
- disable
- rollback
- unload

### 5.3 后端兼容层

这一层主要由以下文件承载：

- [backend.uya](../lib/std/runtime/capability/backend.uya)
- [adapter.uya](../lib/std/runtime/capability/adapter.uya)
- [fake_backend.uya](../lib/std/runtime/capability/fake_backend.uya)
- [native_backend.uya](../lib/std/runtime/capability/native_backend.uya)
- [wamr_backend.uya](../lib/std/runtime/capability/wamr_backend.uya)

当前状态是：

- `Fake` 后端：用于联调与 TDD
- `Native Uya` 后端：当前是魔数校验 + invoke 骨架
- `WAMR` 后端：当前是 wasm magic 校验 + invoke 骨架
- `Adapter`：已经负责按 `CapabilityBackendKind` 做统一分发

### 5.4 Benchmark 层

这一层主要由以下文件承载：

- [benchmark.uya](../lib/std/runtime/capability/benchmark.uya)
- [bench_capability_runtime.uya](../tests/bench_capability_runtime.uya)
- [compare_capability_runtime_benchmark.py](../tests/compare_capability_runtime_benchmark.py)

这说明项目已经从“只讨论架构”进入了“准备对比两个后端”的阶段。

---

## 6. 与 WAMR / Native Uya 对比的当前判断

本轮讨论中，对两种后端的定位已经比较明确：

### 6.1 WAMR

当前被视为：

- 更适合 MVP 和商业验证的后端
- 更适合快速跑通安全下发、Host API、受限执行闭环
- 更适合拿来做第一轮资源与性能对比

在项目中的角色应是：

- `capability runtime` 的一种可替换后端
- 不是平台协议本身

### 6.2 Native Uya

当前被视为：

- 更长期、更可控的后端方向
- 更可能在后续替代高频、关键能力路径
- 更贴近“微容器护城河”的自研部分

在项目中的角色应是：

- 与 `WAMR` 并列比较的候选执行后端
- 不应在当前阶段直接绑死整个 capability 平台

---

## 7. 本轮 TDD 实际结果

本轮不是只写了骨架，也做了 capability 线自己的 TDD 尝试。

### 7.1 已跑通的 capability 兼容层测试

通过脚本：

- [run_capability_runtime_compat.sh](../tests/run_capability_runtime_compat.sh)

可以跑通：

- manifest 默认值校验
- invalid backend 拒绝
- permission declare / grant / require
- undeclared grant 报错
- fake backend load / invoke
- 以及后续继续加进去的 adapter / manager / WAMR / native 基础测试

### 7.2 已知约束

当前 capability 测试没有直接复用仓库默认的 `tests/Makefile` hosted 链路，而是走独立脚本，原因是：

- `--nostdlib` 生成的 capability 测试 C 会带 `_start`
- 仓库默认测试链接方式是面向另一类入口模型
- 若强行复用，会出现 `_start` 与默认链接入口冲突

本轮的处理策略是：

- 只在 capability 这条线上适配当前编译器入口模型
- 不去修改更外围的通用测试基础设施

这是一个**有意识的边界控制**，不是遗留问题被忽略。

---

## 8. 本轮确认的工程原则

本轮讨论后，后续推进 capability runtime 时建议坚持以下原则：

1. 上层协议不直接绑定后端
   - `manifest`
   - `permission`
   - `Host API`
   - `lifecycle`
   - `benchmark schema`
   应保持稳定

2. 通过 `backend kind` 切换后端
   - `Fake`
   - `Wamr`
   - `NativeUya`

3. 优先比较统一口径下的性能和资源占用
   - ROM
   - RAM
   - install / activate / invoke latency
   - Host API overhead
   - timeout / failure 行为

4. 不在当前阶段让 capability 平台被某一个执行器绑死

5. 只把与 capability 线直接相关的问题留在 capability 线内解决
   - 如测试入口模型适配
   - 不轻易扩散到全局测试基础设施或 codegen 行为

---

## 9. 当前仍未完成的部分

虽然 capability runtime 已经从文档走到骨架与测试，但当前仍明显处于“第一阶段”。

尚未完成的核心点包括：

1. `WAMR` 后端还只是骨架
   - 目前只有 wasm magic 校验与最小 invoke 占位
   - 还没有接真实 WAMR runtime

2. `Native Uya` 后端还只是骨架
   - 目前只有原生 payload magic 校验与最小 invoke 占位
   - 还没有真实自定义执行器

3. `Host API` 还不完整
   - 目前更偏权限边界占位
   - 还没真正接到设备 API / 微容器宿主能力

4. `benchmark` 还未形成最终决策闭环
   - 当前有 harness 和工具
   - 但还没有真实 WAMR vs Native 的设备侧数据

5. 与 `微容器` 的下层结合仍需继续明确
   - 当前 capability runtime 已有清晰上层协议
   - 但如何映射到真正的微容器地址空间、调度、syscall 边界，还未完全落下

---

## 10. 推荐的下一步

结合当前项目状态，建议后续按以下顺序推进：

1. 继续把 capability 线的测试补完整
   - 优先覆盖 `manager + adapter + backend` 的状态转换和错误路径

2. 接入真实 `WAMR` runtime 的最小壳
   - 保持 manifest / Host API / benchmark 口径不变

3. 对 `Native Uya` 后端先保持窄语义
   - 不急着做完整执行器
   - 先把 payload 校验、invoke 约定、上下文生命周期固定住

4. 用现有 benchmark 框架开始收集第一批对比数据
   - 即使是模拟数据，也先把流程跑起来

5. 等 capability runtime 上层足够稳定后，再决定：
   - 哪些能力继续走 WAMR
   - 哪些关键路径值得迁到 Native / 微容器执行器

---

## 11. 相关提交脉络

本轮之前后，capability runtime 相关提交已经形成连续轨迹，最近可见的关键提交包括：

- `3effb8a3` `docs/runtime: add capability runtime mvp design and skeleton`
- `bfa903e9` `runtime/capability: add loader and host api skeleton`
- `7bab8e16` `Add capability backend compat layer and loader tests`
- `63e189cf` `Add capability WAMR backend skeleton`
- `c6f685be` `Add capability backend adapter dispatch`
- `2014b156` `Add capability native backend skeleton`
- `738196b1` `Add capability manager skeleton`
- `40842b0e` `Add capability unload lifecycle`
- `4a8c5561` `Add capability runtime benchmark harness`

这说明 capability runtime 已经不是一个口头方向，而是正在形成一条独立子系统。

---

## 12. 一句话总结

截至本轮结束，项目已经从“讨论无 App 手表上的微容器设想”推进到：

**以 capability runtime 为上层抽象、以 WAMR / Native Uya 为可替换执行后端、并开始具备 TDD 与 benchmark 基线的独立子系统。**

