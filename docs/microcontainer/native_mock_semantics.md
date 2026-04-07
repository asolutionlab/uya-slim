# MicroContainer Native Mock 语义规范

**版本**: v0.1  
**日期**: 2026-04-07  
**关联文档**: [runtime-architecture.md](./runtime-architecture.md), [backend_adapter_contract.md](./backend_adapter_contract.md), [capability_api_schema.md](./capability_api_schema.md), [capability_backend_compat.md](../capability_backend_compat.md), [host_abi.md](../host_abi.md), [permission_model.md](../permission_model.md)

---

## 1. 目标

本文档定义 `Native Mock Adapter` 的语义边界。

核心目标是：

- 让 native 环境成为高保真调试和测试后端
- 保证 native mock 不改变 runtime 语义
- 保证同一 artifact 在 device / native 下的行为可对齐
- 让 mock 只替换数据源和表现形式，不替换权限和状态机

> Native Mock 是“可观测的模拟后端”，不是“语义放宽器”。

---

## 2. 作用边界

### 2.1 Native Mock 可以替换

- 时间来源
- 显示输出
- 传感器输入
- 存储后端
- 网络后端
- 调试 trace

### 2.2 Native Mock 不可以替换

- runtime 状态机
- capability policy
- 权限判定
- 预算判定
- 错误语义
- loader / verifier 结果

### 2.3 Native Mock 不是

- 不是直接放宽权限的 native 直跑模式
- 不是给 artifact 增加新能力的扩展器
- 不是绕过 core 的调试捷径

如果需要 direct native exec，它应作为另一条可选路径存在，而不是 mock 语义的一部分。

---

## 3. 核心原则

### 3.1 语义保持

同一 artifact 在 device 与 native mock 下应满足：

- 同样的 capability 是否可用
- 同样的权限检查结果
- 同样的预算超限结果
- 同样的错误归一化结果

### 3.2 默认确定性

native mock 的默认行为必须是确定性的：

- 不依赖宿主墙钟时间
- 不依赖随机未初始化状态
- 不依赖进程间共享全局副作用

### 3.3 可重放

在相同 seed、相同脚本、相同输入序列下，native mock 必须产生相同输出。

### 3.4 故障闭合

当 mock 无法提供某项能力时，必须返回明确错误，而不是伪造成功结果。

---

## 4. 模拟对象

### 4.1 Clock Mock

Clock Mock 负责模拟 `host_time_now()` 之类的时间能力。

要求：

- 使用 mock clock，不读取真实墙钟作为语义依据
- 时间推进必须由 core、测试脚本或显式调试动作控制
- 同一 session 内的时间变化必须可复现

建议规则：

- 启动时固定一个基准时间
- 单次调用返回当前快照
- 调度或脚本可以推进时间，但不得静默跳变

### 4.2 Display Mock

Display Mock 负责模拟显示输出能力，例如 `host_screen_draw_text(...)`。

要求：

- 将渲染请求写入 capture buffer
- 将显示事件写入 trace
- 不依赖真实 GUI 或终端排版作为语义结果

显示 mock 的结果应便于：

- 单元测试断言
- 集成测试回放
- 人工调试检查

### 4.3 Storage Mock

Storage Mock 负责模拟 KV 存储能力，例如 `host_kv_get(...)`、`host_kv_set(...)`。

要求：

- 默认按 `instance_id` 隔离命名空间
- 默认不与真实宿主全局 KV 混用
- 读写结果必须可复现

建议规则：

- 每个测试 case 默认使用独立存储目录或内存命名空间
- 若显式开启持久化，则持久化范围必须受控且可清理
- 关闭或重置 mock 后不应遗留跨测试污染

### 4.4 Sensor Mock

Sensor Mock 负责模拟传感器能力，例如 `host_sensor_step_read()`。

要求：

- 传感器输入应来自脚本、录制回放或 seed 驱动序列
- 不能凭空生成“看起来合理”的真实数据
- 当脚本耗尽且没有 fallback 时，必须失败闭合

建议规则：

- 以序列方式消费样本
- 每次读取都应可 trace
- 样本来源应能在日志中追踪

### 4.5 Motor / Vibrate Mock

Motor 或振动能力在 mock 下只产生可观测事件，不产生真实硬件动作。

要求：

- 记录持续时间、强度、调用时刻
- 不得影响程序逻辑分支
- 不得因为 mock 而额外成功或额外失败

### 4.6 Network Mock

Network Mock 默认应是受限的。

要求：

- 默认 fail-closed
- 只允许脚本化、录制化或显式允许的网络路径
- 不得默认访问真实外网

如果测试需要网络，应通过明确配置提供：

- mock 响应
- loopback 代理
- 本地录制回放

---

## 5. 时间与调度

### 5.1 时间来源

native mock 的时间语义由 core 和 mock clock 共同决定，而不是宿主墙钟决定。

### 5.2 推进规则

- core 可以按调度 tick 推进时间
- 测试脚本可以显式推进时间
- backend 不得私自推进时间来掩盖超时或预算问题

### 5.3 超时语义

超时应按 core 的预算系统判定，不能因为 mock 运行得快就忽略超时语义。

---

## 6. 状态隔离

### 6.1 默认隔离

每个 instance 默认拥有独立的：

- mock clock 视图
- storage 命名空间
- sensor 样本游标
- display capture buffer
- network 脚本状态

### 6.2 会话重置

测试或重载时，应默认清除 session 状态，避免跨 case 污染。

### 6.3 持久化模式

若显式开启持久化：

- 持久化范围必须是可配置的
- 持久化数据必须可清理
- 持久化不能改变 API 语义，只能改变数据生命周期

---

## 7. Trace 与回放

### 7.1 Trace 要求

native mock 应记录至少以下信息：

- `instance_id`
- `capability_id`
- `api_id`
- 输入参数摘要
- 返回结果摘要
- 预算消耗
- 错误归一化结果

### 7.2 回放要求

回放模式必须满足：

- 相同脚本得到相同输出
- 相同输入序列得到相同响应
- 发生错误时保留错误上下文

### 7.3 Replay 优先级

当 trace、script 和 seed 同时存在时，优先级建议为：

1. 明确 replay trace
2. 明确脚本
3. seed 驱动默认值

---

## 8. 权限与预算

native mock 不能绕过权限和预算：

- 未获批权限仍然拒绝
- 预算超限仍然失败
- 逻辑错误仍然上报

mock 只是改变后端实现方式，不改变裁决结果。

---

## 9. 错误语义

当 native mock 无法提供某项能力时，必须返回统一错误，而不是静默降级。

建议错误来源：

- capability 未启用 -> `Disabled`
- 输入参数不合法 -> `InvalidArgument`
- 脚本样本缺失 -> `HostApiError`
- mock 后端内部故障 -> `BackendInternalError`

backend 可以保留内部原因码，但 core 看到的必须是归一化结果。

---

## 10. 明确不做

MVP 阶段本文档不覆盖：

- 真实 GUI 或浏览器渲染
- 完整网络模拟器
- 分布式 mock 集群
- 自动 fuzz 输入生成
- direct native exec 的具体实现

---

## 11. 验收标准

native mock 语义正确的最低标准是：

- 同一 artifact 在 device 和 native mock 下通过同一套权限判定
- 同一 API 调用在 mock 下返回与 device 一致的归一化语义
- mock 输出可 trace、可回放、可清理
- mock 不引入额外 capability
- mock 不改变 core 的状态机、预算和错误模型

---

## 12. 后续建议

建议继续补充：

- Native Mock 事件格式
- Replay Script 格式
- Storage Mock 持久化约定
