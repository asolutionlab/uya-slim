# MicroContainer Capability API Schema（能力 API 结构）

**版本**: v0.1  
**日期**: 2026-04-07  
**关联文档**: [requirements_v1.3.md](./requirements_v1.3.md), [host_abi.md](../host_abi.md), [permission_model.md](../permission_model.md), [capability_manifest.md](../capability_manifest.md), [runtime-architecture.md](./runtime-architecture.md), [backend_adapter_contract.md](./backend_adapter_contract.md), [capability_backend_compat.md](../capability_backend_compat.md)

---

## 1. 目标

本文档定义 MicroContainer 体系中的**能力 API 逻辑结构**，用于统一：

- capability manifest 中的能力声明
- 权限模型中的权限名称
- Host API 的固定调用边界
- backend adapter 的绑定方式

本文档关注的是“语义层 schema”，不是某一种具体二进制编码。

> 同一 capability_id 和 api_id 在不同 backend 下必须保持同一语义。

---

## 2. 作用边界

### 2.1 本文档负责

- 定义 capability 的命名方式
- 定义 capability 与 API 的分层
- 定义参数、返回值、错误、预算的描述方式
- 定义 capability 到 Host API 的映射规则

### 2.2 本文档不负责

- 具体序列化格式
- 具体内存布局
- 具体汇编 / 寄存器 ABI
- backend 私有扩展字段

这些内容应由 `host_abi.md` 和 backend adapter 实现细化。

---

## 3. 总体结构

```text
Manifest
  -> Capability Descriptor
  -> API Descriptor
  -> Permission / Budget / Error Policy
  -> Host API Binding
  -> Backend Adapter
```

能力 API 的调用在逻辑上可以抽象为：

```text
invoke(capability_id, api_id, args, ctx) -> result
```

其中：

- `capability_id` 标识能力域
- `api_id` 标识该能力域中的具体操作
- `args` 为调用参数
- `ctx` 为运行时上下文
- `result` 为统一返回结果

---

## 4. 设计原则

### 4.1 稳定命名

- `capability_id` 必须稳定
- `api_id` 必须在同一 capability 内稳定
- 不能因为 backend 不同而改名

### 4.2 默认拒绝

- 未声明 capability 的调用必须拒绝
- 未获批权限的调用必须拒绝
- backend 不能用“默认允许”掩盖缺省配置

### 4.3 权限与 API 双绑定

每个 API 都必须能映射到明确权限：

- 安装时可检查
- 运行时必须再次检查

### 4.4 后端不可增语义

backend 可以实现更多观测或更高性能，但不能：

- 新增未声明 capability
- 改变 API 参数意义
- 改变错误语义
- 改变预算语义

---

## 5. 核心数据模型

### 5.1 CapabilityDescriptor

一个 capability 描述一个能力域，例如 `time`、`storage.kv` 或 `screen`。

```text
CapabilityDescriptor {
  capability_id: string
  version: string
  category: string
  permissions: PermissionId[]
  apis: ApiDescriptor[]
  budgets: BudgetPolicy?
  availability: AvailabilityPolicy?
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `capability_id` | 能力域标识，建议使用 `domain.subdomain` 风格 |
| `version` | 能力描述版本 |
| `category` | 能力分类，如 `time`、`storage`、`sensor` |
| `permissions` | 该 capability 对应的权限集合 |
| `apis` | 该 capability 下的 API 列表 |
| `budgets` | 该 capability 的预算策略，可选 |
| `availability` | 该 capability 的可用性策略，可选 |

### 5.2 ApiDescriptor

一个 API 描述 capability 内的一次具体操作。

```text
ApiDescriptor {
  api_id: string
  host_name: string
  signature: FunctionSignature
  permission: PermissionId
  side_effect: SideEffectClass
  sync_mode: SyncMode
  error_set: ErrorSet
  budget_cost: BudgetCost?
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `api_id` | capability 内唯一操作名 |
| `host_name` | 对应的 Host API 名称 |
| `signature` | 参数和返回值签名 |
| `permission` | 该 API 所需权限 |
| `side_effect` | 该 API 的副作用分类 |
| `sync_mode` | 同步或异步 |
| `error_set` | 允许返回的错误集合 |
| `budget_cost` | 该 API 的预算消耗描述，可选 |

### 5.3 FunctionSignature

函数签名建议使用逻辑类型描述，而不是直接绑定某种语言 ABI。

```text
FunctionSignature {
  params: ParamSchema[]
  returns: ResultSchema
}
```

参数和返回值的逻辑类型建议包括：

- `bool`
- `i32`
- `u32`
- `i64`
- `u64`
- `string`
- `bytes`
- `array<T>`
- `record`
- `enum`
- `optional<T>`

### 5.4 ResultSchema

API 返回值建议统一为两层：

- 逻辑返回值
- 归一化错误

```text
ResultSchema {
  value: TypeRef?
  error: ErrorSchema?
}
```

### 5.5 ErrorSchema

错误应保持语义稳定，不应依赖 backend 私有错误码。

```text
ErrorSchema {
  category: string
  code: string
  message: string?
}
```

建议错误类别：

- `validation`
- `policy`
- `resource`
- `execution`
- `internal`

---

## 6. 当前标准 capability 集

当前仓库里的 capability API 可以按以下能力域组织。

| capability_id | api_id | host API | permission | 状态 |
|---------------|--------|----------|------------|------|
| `time` | `now` | `host_time_now()` | `time.read` | MVP |
| `log` | `write` | `host_log_write(level, msg)` | `log.write` | MVP |
| `vibrate` | `use` | `host_vibrate(ms)` | `vibrate.use` | MVP |
| `screen` | `draw_text` | `host_screen_draw_text(x, y, text)` | `screen.draw_basic` | MVP |
| `storage.kv` | `get` | `host_kv_get(key, out)` | `storage.kv.read` | MVP |
| `storage.kv` | `set` | `host_kv_set(key, value)` | `storage.kv.write` | MVP |
| `sensor.step` | `read` | `host_sensor_step_read()` | `sensor.step.read` | 扩展 |

说明：

- 上表中的 `host API` 是逻辑绑定名，不限定具体后端调用形式
- `sensor.step.read` 已在兼容层文档中出现，但不代表所有后端都必须同等提供
- 若 capability 不可用，应通过统一错误语义返回，而不是静默降级成成功

---

## 7. 绑定规则

### 7.1 capability_id 规则

- 必须稳定
- 建议采用点号分层，例如 `storage.kv`
- 不同 backend 不得使用不同 capability_id

### 7.2 api_id 规则

- 在同一 capability 内唯一
- 建议使用简短动词，例如 `now`、`get`、`set`
- 不要把 backend 私有实现名泄露到 api_id

### 7.3 host_name 规则

- 建议采用 `host_<domain>_<verb>` 风格
- host_name 是物理 ABI 名称，不是业务语义名称
- 物理 ABI 可变，但逻辑 schema 不可变

### 7.4 permission 规则

- 每个 API 必须明确绑定权限
- 权限名应复用 `permission_model.md` 中已定义的名称
- 不允许“无权限隐式可调用”

---

## 8. 版本兼容

### 8.1 ABI 版本

当前建议的运行时 ABI 版本为：

```text
uya-cap-1
```

### 8.2 兼容原则

- 新增 API，且不破坏现有签名时，可视为向后兼容扩展
- 删除 API 或改变参数 / 返回语义时，需要升级主版本
- backend 只要声明支持同一 `runtime.abi`，就必须遵守同一套语义

### 8.3 Manifest 关系

Manifest 中的 `runtime.abi` 是 capability schema 的入口约束：

- ABI 不匹配则拒绝加载
- 能力表不完整则拒绝激活或按策略降级
- 权限不满足则拒绝运行

---

## 9. 校验规则

schema 校验应至少检查：

- capability_id 是否重复
- api_id 是否重复
- permission 是否存在于权限模型
- host_name 是否能映射到 host ABI
- 参数类型是否在支持集合内
- 返回值与错误集合是否闭合

---

## 10. 明确不做

MVP 阶段本文档不覆盖：

- 二进制 schema 编码
- 自动生成绑定代码
- 设备特定私有 API 扩展
- 多租户权限继承
- 动态注册第三方 capability

---

## 11. 后续建议

建议继续补充：

- 二进制 Capability Schema 编码
- Host API 到 Uya 语言绑定生成器
- Capability 版本差异对照表
