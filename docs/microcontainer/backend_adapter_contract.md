# MicroContainer Backend Adapter Contract（后端适配器契约）

**版本**: v0.1  
**日期**: 2026-04-07  
**关联文档**: [requirements_v1.3.md](./requirements_v1.3.md), [runtime-architecture.md](./runtime-architecture.md), [capability_api_schema.md](./capability_api_schema.md), [native_mock_semantics.md](./native_mock_semantics.md), [capability_backend_compat.md](../capability_backend_compat.md)

---

## 1. 目标

本文档定义 `MicroContainer Core` 与 `Backend Adapter` 之间的接口级边界。

核心目标是：

- 统一核心语义
- 隔离后端实现差异
- 保证同一 artifact 在不同后端下得到一致的可观测结果
- 让 core 只依赖契约，不依赖具体引擎实现

> 后端可以不同，语义不能分叉。

---

## 2. 边界定义

### 2.1 Core 负责

- manifest 解析
- capability policy
- 生命周期状态机
- 调度与预算
- 错误归一化
- telemetry schema
- recovery policy

### 2.2 Backend 负责

- 具体 artifact 格式验证
- 模块装载
- 实例创建与销毁
- 执行入口调用
- host API 绑定
- 引擎级 trap 捕获
- 引擎私有资源清理

### 2.3 两者之间共享但不互相拥有

- payload bytes
- parsed manifest
- limits
- host API table
- trace sink
- replay / debug 控制开关

---

## 3. 统一接口

Backend Adapter 必须提供以下最小接口：

```text
describe() -> BackendDescriptor
init(ctx: BackendInitContext) -> Result
validate_module(payload: PayloadRef, manifest: ManifestView) -> ValidationResult
load_module(payload: PayloadRef, manifest: ManifestView) -> LoadResult
create_instance(module: ModuleHandle, cfg: InstanceConfig) -> InstanceHandle
bind_host_api(instance: InstanceHandle, host_api: HostApiTableRef) -> Result
invoke(instance: InstanceHandle, entry: EntryPoint, ctx: InvokeContext) -> InvokeResult
suspend(instance: InstanceHandle) -> ControlResult
resume(instance: InstanceHandle) -> ControlResult
destroy_instance(instance: InstanceHandle) -> ControlResult
unload_module(module: ModuleHandle) -> ControlResult
shutdown() -> ControlResult
```

### 3.1 `describe()`

- 返回后端静态能力描述
- 不得依赖当前 instance 状态
- 不得改变执行语义

### 3.2 `init()`

- 初始化后端运行时
- 可在进程启动时调用一次
- 重复调用必须可预期，不能引发隐式语义变化

### 3.3 `validate_module()`

- 只检查后端可接受的格式、ABI、特性开关和基础合法性
- 不负责权限决策
- 不负责产品级 policy

### 3.4 `load_module()`

- 生成后端内部模块句柄
- 可做解析、重定位、编译、缓存
- 不得修改 payload 原始内容

### 3.5 `create_instance()`

- 生成可执行实例
- 绑定 core 传入的 limits 和 policy
- 不得默认扩大资源预算

### 3.6 `bind_host_api()`

- 绑定 core 提供的 host API table
- 只能使用 table 中存在的入口
- 不得私自新增 capability

### 3.7 `invoke()`

- 对 core 暴露同步调用语义
- 同一 instance 同一时刻只允许一个活跃 invoke，除非 descriptor 明确声明并且 core 已授权并发
- 必须把 trap、abort、timeout、budget 超限等结果显式返回

### 3.8 `suspend()` / `resume()`

- 仅在 descriptor 声明支持时可用
- 不支持时必须返回 `UnsupportedFeature`
- 不能靠隐式暂停状态模拟成功

### 3.9 `destroy_instance()` / `unload_module()`

- 必须释放后端持有的资源
- 重复调用应返回稳定错误或幂等成功
- 不得泄漏 instance-private 状态

### 3.10 `shutdown()`

- 释放 backend-global 资源
- 关闭线程、缓存、文件句柄、设备上下文等
- 不能影响 core 仍在管理的其他 backend 实例

### 3.11 数据模型说明

以下类型是契约层的最小语义对象，具体字段可以扩展，但不能改变其语义边界：

```text
BackendDescriptor {
  backend_id: string
  backend_kind: string
  artifact_kind: string
  abi: string
  feature_flags: string[]
  supports_suspend: bool
  supports_replay: bool
  supports_inspection: bool
}

BackendInitContext {
  limits: LimitsView
  policy: PolicyView
  host_api_table: HostApiTableRef
  trace_sink: TraceSinkRef
}

InstanceConfig {
  instance_id: string
  limits: LimitsView
  policy: PolicyView
  replay_seed: u64?
  debug_flags: string[]
}

InvokeContext {
  call_id: string
  deadline_us: u64
  budget_snapshot: BudgetSnapshot
  trigger: TriggerType
}

InvokeResult {
  status: ResultKind
  value: bytes
  error: BackendError
  consumed_us: u64
}

BackendError {
  category: string
  code: string
  message: string
  recoverable: bool
}
```

其中 `LimitsView`、`PolicyView`、`ResultKind`、`TriggerType` 等都是契约语义对象的示意名；实现层可以把它们展开成更细的枚举或结构，但不能改变 core / backend 的职责边界。

---

## 4. 对象与所有权

### 4.1 Core 拥有

- manifest 的权威版本
- capability policy
- limits
- scheduler clock
- host API registry
- telemetry sink

### 4.2 Backend 拥有

- `ModuleHandle`
- `InstanceHandle`
- backend-private caches
- backend-private threads / contexts
- backend-private compiled code

### 4.3 只读借用

以下对象在调用期间视为只读借用：

- payload bytes
- parsed manifest
- limits snapshot
- host API table

Backend 不得修改这些对象的内容，也不得把它们当成可变状态源。

---

## 5. 生命周期语义

Backend 必须将生命周期暴露为可预测状态，而不是隐式副作用。

建议状态顺序：

```text
uninitialized -> initialized -> module_loaded -> instance_ready -> running -> suspended -> destroyed -> unloaded -> shutdown
```

### 5.1 规则

- `invoke()` 只能在 `instance_ready` 或 `running` 下发生
- `suspend()` 只能在 `running` 下发生
- `resume()` 只能在 `suspended` 下发生
- `destroy_instance()` 之后实例句柄不得再次用于执行
- `unload_module()` 之后模块句柄不得再次创建实例
- `shutdown()` 之后 backend 只能重新 `init()`

### 5.2 非法状态

非法状态转换必须返回稳定错误，例如 `InvalidState`，不能 panic，也不能默默修正。

---

## 6. Host API 绑定规则

### 6.1 绑定来源

core 负责构造 `HostApiTable`，backend 只负责消费它。

### 6.2 绑定要求

- backend 只能调用表中登记的 host API
- backend 不得把未登记能力暴露给 artifact
- backend 不得修改 capability id、api id 或参数模型
- backend 不得改变 host call 的可见顺序

### 6.3 绑定实现形式

实现形式可以不同：

- import table
- syscall bridge
- function pointer table
- native stub

但对 core 而言，这些都只是同一套语义下的不同传输方式。

### 6.4 Host 调用上下文

建议每次 host call 都携带：

- `instance_id`
- `capability_id`
- `api_id`
- `deadline_us`
- `budget_snapshot`
- `trace_id`
- `replay_seed`（若适用）

backend 不得伪造这些上下文，也不得忽略 core 提供的预算信息。

---

## 7. 资源与预算

core 传入的 limits 是硬约束，不是建议值。

典型限制包括：

- memory budget
- stack budget
- exec time budget
- wakeup budget
- api budget
- io budget

### 7.1 预算语义

- backend 必须在预算耗尽前停止执行
- backend 若无法实现某类预算，必须在 `describe()` 或 `load_module()` 阶段声明不支持
- backend 不能用“内部超额后再补救”的方式掩盖越界

### 7.2 超限处理

超限结果必须显式返回，不能吞掉：

- `TimedOut`
- `ResourceExceeded`
- `HostApiError`
- `BackendInternalError`

core 再根据统一策略决定是否回收、熔断或重试。

---

## 8. 错误模型

backend 可以返回内部错误，但 core 只接受归一化后的结果。

### 8.1 错误分类

建议分为以下几类：

- validation
- unsupported
- policy
- resource
- execution
- internal

### 8.2 归一化目标

错误最终应归一到共享平台错误集合，例如：

- `InvalidPackage`
- `InvalidModule`
- `InvalidArgument`
- `PermissionDenied`
- `TimedOut`
- `ResourceExceeded`
- `Disabled`
- `HostApiError`
- `BackendInternalError`

### 8.3 映射规则

- 格式问题归入 validation
- 权限问题归入 policy
- 时间或内存超限归入 resource
- trap / abort / engine fault 归入 execution
- 不能识别的 backend 崩溃归入 internal

backend 必须保留足够上下文，方便 core 判定这是“可恢复失败”还是“需要熔断的故障”。

---

## 9. 观测与调试

backend 可以额外提供：

- trace
- debug log
- inspection API
- replay hook

但这些能力只能增加可观测性，不能改变执行语义。

### 9.1 允许

- 打印 trace
- 暴露只读 inspection
- 在调试模式下记录调用详情

### 9.2 不允许

- 因 debug flag 跳过验证
- 因 trace 开关改变调度顺序
- 因 inspection 改写 instance 状态

---

## 10. 禁止行为

- 禁止绕过 core 的 capability policy
- 禁止新增未登记 capability
- 禁止修改 payload、manifest 或 limits snapshot
- 禁止调用未注册的 host API
- 禁止把 backend 私有 fallback 暴露成语义上的成功
- 禁止在相同输入下靠隐藏全局状态改变结果
- 禁止吞掉 trap 或 timeout 再返回成功
- 禁止把一个 instance 的失败静默切换到另一个执行引擎

---

## 11. 验收标准

满足以下条件，说明 backend adapter contract 实现合格：

- 同一 payload + manifest + policy 在不同 backend 上得到一致的归一化结果
- 同一 permission decision 在不同 backend 上一致
- 同一 invalid module 输入在不同 backend 上一致拒绝
- 同一 budget 配置在不同 backend 上一致超限
- backend trace 不改变语义
- core 可以切换 backend 而不改 scheduler、verifier、budget 和 lifecycle 逻辑

---

## 12. 后续建议

建议继续补充：

- [Capability API Schema](./capability_api_schema.md)
- [Native Mock 语义规范](./native_mock_semantics.md)
- Backend Descriptor 细化表
