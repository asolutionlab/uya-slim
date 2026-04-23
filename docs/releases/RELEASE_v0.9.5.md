# Uya v0.9.5 发布说明（草案）

> **类型**：**v0.9.x 发行线上的功能版本**  
> **发布日期**：待定  
> **版本主题**：**microapp hosted 多平台真执行闭环版**

## 概要

`v0.9.5` 的目标，不是继续横向铺更多 language / std feature，而是把 `v0.9.0` 到 `v0.9.4` 已经铺开的 microapp / 微容器链路，真正推进到“**同一份 portable source 在多个 hosted profile 下都能 native run，并且 release 闸门能稳定验证**”。

如果 `v0.9.4` 的重点是“整链路能稳定跑完并被 release 流程验证”，那么 `v0.9.5` 的重点就是把这条链路从 **单平台样板成功** 推进到 **hosted 多平台真执行成立**：

- `linux_x86_64_hardvm` 不再是唯一真执行样板
- `linux_aarch64_hardvm` 从 host-gated bring-up 推进到实际绿灯
- `macos_arm64_hardvm` 从“profile 已暴露”推进到“运行时真正接线”
- bridge ABI、fault/result model、profile CI 与文档口径统一到同一条发布线

---

## 当前已确认

截至当前分支，已经可以确认的事实是：

- `make b` 已于 `2026-04-23` 在当前 `Linux x86_64` 工作树实跑通过
- `make microapp-check` 与 `make microapp-hosted-smoke` 已形成稳定聚合入口
- `make release-clean` 已于 `2026-04-23` 在当前分支最新已提交快照的干净快照上通过
- `make microapp-aarch64-runtime-check` 已于 `2026-04-23` 在当前 `Linux x86_64` 宿主按设计输出 `microapp aarch64 hosted runtime skipped (host_arch=x86_64)`
- `make microapp-macos-runtime-check` 已于 `2026-04-23` 在当前 `Linux x86_64` 宿主按设计输出 `microapp macos arm64 hosted runtime skipped (host_os=Linux)`
- `linux_x86_64_hardvm` 已建立真实 mapped payload 执行样板
- `linux_aarch64_hardvm` 已具备 object extract 与 host-gated runtime 回归入口
- `macos_arm64_hardvm` 已具备 Mach-O object extract 与 host-gated runtime 回归入口
- 公开 `macos-ci` 在 `2026-04-22` 针对 `origin/main` 的最近几次 Apple Silicon 运行仍提前失败在 bootstrap 阶段，`make microapp-aarch64-runtime-check` 尚未真正开始执行
- 当前分支已把 `.github/workflows/macos-ci.yml` 的 macOS bootstrap 入口从 `make from-c` 修正为 `make from-c-native`，并补了 `workflow_dispatch` 以便后续手动触发 arm64 CI
- 新一轮公开 `macos-ci` 已确认跑到 `Bootstrap seed compiler from native hosted seed`；当前分支已继续修正 macOS `from-c-native` 优先选择 arch-specific hosted seed，并刷新 macOS hosted seeds 以消除 `char* -> uint8_t*` 的 `-Werror` 构建失败
- `tests/verify_microapp_portable_sources.sh` 已把 official portable source 与 `MMU / exit / fault` fixture 纳入 payload codegen 审计，持续拒绝宿主 libc 普通符号直接泄漏进 payload C
- `.uapp v1/v2` 兼容、trap result、recovery/update、structured fault 已纳入当前 microapp 聚合回归

当前仍待对应宿主签收的事实是：

- `linux_aarch64_hardvm` 仍需 arm64 宿主或 arm64 CI 的真实绿灯
- `macos_arm64_hardvm` 仍需 macOS arm64 宿主或 CI 的真实绿灯

---

## 当前验证矩阵

以下矩阵描述的是当前工作树已经确认的验证状态，而不是最终发版签收结论：

| 宿主 / 入口 | 当前状态 | 说明 |
|------|------|------|
| `Linux x86_64` / `make b` | 已通过 | `2026-04-23` 本机实跑通过，自举编译与 bootstrap compare 一致 |
| `Linux x86_64` / `make release-clean` | 已通过 | `2026-04-23` 已在当前分支最新已提交快照的干净快照上通过 |
| `Linux x86_64` / `make microapp-check` | 已通过 | 当前已包含 `example boundary`、portable source + `MMU / exit / fault` fixture 的 payload codegen 耦合审计、object extract、trap/result、recovery/update 聚合回归 |
| `Linux x86_64` / `make microapp-hosted-smoke` | 已通过 | 当前已包含 `macos object extract`、`aarch64 object extract`、portable source/fixture 宿主符号泄漏审计与 host API 诊断回归 |
| `Linux x86_64` / `make microapp-aarch64-runtime-check` | host-gated skip | `2026-04-23` 本机复核输出 `microapp aarch64 hosted runtime skipped (host_arch=x86_64)`，当前宿主不是 arm64，不构成 aarch64 真执行证明 |
| `Linux x86_64` / `make microapp-macos-runtime-check` | host-gated skip | `2026-04-23` 本机复核输出 `microapp macos arm64 hosted runtime skipped (host_os=Linux)`，当前宿主不是 macOS arm64，不构成 macOS arm64 真执行证明 |
| `macOS arm64 CI` / `make microapp-hosted-smoke` | 已接线，当前被 native seed bootstrap 阶段阻塞 | 新一轮公开 `macos-ci` 已越过旧的 `make from-c` 路径，但仍在 `Bootstrap seed compiler from native hosted seed` 处失败；当前分支已补 arch-specific seed 优先与 macOS hosted seed 刷新 |
| `macOS arm64 CI` / `make microapp-aarch64-runtime-check` | 已接线，待修正 native seed bootstrap 后拿最终绿灯记录 | workflow 已接入 standalone 入口，但最近公开运行未真正执行到该步骤 |
| `macOS arm64 CI` / `make microapp-macos-runtime-check` | 已接线，待修正 native seed bootstrap 后拿最终绿灯记录 | workflow 已接入 standalone 入口，但最近公开运行未真正执行到该步骤 |

## 当前验证统计（2026-04-23）

- 当前 `Linux x86_64` 宿主实跑通过：`make b`、`make microapp-check`、`make microapp-hosted-smoke`、`make release-clean`
- 当前 `Linux x86_64` 宿主按设计 host-gated skip：`make microapp-aarch64-runtime-check`、`make microapp-macos-runtime-check`
- 当前 Apple Silicon CI 前置修复：`.github/workflows/macos-ci.yml` 已切到 `make from-c-native` + `workflow_dispatch`，且当前分支已把 macOS seed 选择顺序改成 arch-specific 优先，待下一次 runner 实跑
- 当前 portable source / core fixture payload 耦合审计入口：`tests/verify_microapp_portable_sources.sh`，已覆盖 official source 与 `MMU / exit / fault` fixture
- 当前共享发布闸门本机统计：`4/4` 已通过
- 当前跨宿主 runtime 闸门本机统计：`0/2` 真执行、`2/2` 按设计 skip
- 风险备注：共享发布闸门当前已覆盖当前分支最新已提交快照，剩余风险集中在 arm64/macOS arm64 宿主的真实 runtime 绿灯尚未取回

---

## 版本目标

### 1. hosted 多平台真执行闭环

- 同一份 portable microapp 源码可在以下 profile 下完成 profile-aware 构建与运行时验证：
  - `linux_x86_64_hardvm`
  - `linux_aarch64_hardvm`
  - `macos_arm64_hardvm`
- `run --app microapp` 在上述 hosted hard-vm profile 下都走真实 payload 执行路径，而不是回退到对照 ELF 或未接线分支。

### 2. ABI / 结果模型冻结

- 冻结 `Portable MicroApp ABI` 最小源码子集
- 冻结 `.uapp v2` / `PayloadObj` 与 `MicroAppTargetProfile` 的对外字段口径
- 冻结 `call_gate` / `trap` bridge ABI 命名与行为
- 冻结统一 `payload result` / `fault_class` / `fault_code` / `fault_signal` 结果面

### 3. release 闸门与文档对齐

- `make microapp-check`、`make microapp-hosted-smoke`、`make microapp-aarch64-runtime-check` 与 `make microapp-macos-runtime-check` 形成“共享闸门 + 宿主专属 runtime 闸门”的稳定组合
- 文档、示例、CLI 帮助、CI、发布说明统一使用 `profile-first + portable source + hosted multi-platform native run` 口径

---

## 本版冻结口径

### 1. `Portable MicroApp ABI`

`v0.9.5` 冻结的最小 portable source 子集为：

- `export fn main() i32`
- `@syscall(...)`，但其语义统一落到 profile 对应 bridge ABI
- `std.microapp.io`
- `std.microapp.mem`
- `std.microapp.task`
- `std.microapp.time`
- 受控常量、切片、结构体、错误联合与基础控制流

不计入 portable source 子集的能力：

- 直接 `use/call libc.*`
- 直接 `use/call std.time`
- `examples/microapp/*_build.uya` / `*_load.uya` 这类宿主侧构建/加载工具源码

### 2. `MicroAppTargetProfile`

`v0.9.5` 冻结的 `MicroAppTargetProfile` 对外字段为：

- `profile_id`
- `arch_raw`
- `bridge_kind_raw`
- `name`
- `triple`
- `default_gcc`

### 3. `.uapp v2` / `PayloadObj`

`v0.9.5` 冻结的 `.uapp v2` 头字段口径为：

- `magic`
- `format_version`
- `container_api_version`
- `image_size`
- `entry_offset`
- `code_size`
- `rodata_size`
- `data_size`
- `bss_size`
- `stack_size_hint`
- `reloc_count`
- `code_offset`
- `rodata_offset`
- `data_offset`
- `reloc_offset`
- `profile_id`
- `entry_va`
- `code_va`
- `rodata_va`
- `data_va`
- `sha256`
- `required_caps`
- `flags`
- `build_mode`
- `target_arch`
- `bridge_kind`

`v0.9.5` 冻结的 `PayloadObj` 对外字段口径为：

- `target_arch`
- `bridge_kind`
- `build_mode`
- `profile_id`
- `required_caps`
- `flags`
- `entry_offset`
- `entry_va`
- `code_va`
- `rodata_va`
- `data_va`
- `code`
- `rodata`
- `data`
- `bss_size`
- `stack_size_hint`
- `relocs`
- `reloc_count`

### 4. bridge / result model

`v0.9.5` 冻结的 bridge ABI 命名为：

- `call_gate`
- `trap`

`v0.9.5` 冻结的统一结果面为：

- `ok`
- `exit`
- `fault`
- `validated`
- `unwired`

其中 `fault` 结果统一使用：

- `fault_class`
- `fault_code`
- `fault_signal`

---

## 核心变更范围

### 1. `linux_aarch64_hardvm` 真执行转正

- arm64 宿主上的 aarch64 hosted runtime 回归从“脚本存在、按宿主 gate 执行”推进到“正式 release 闸门”
- 收口：
  - mapped payload 入口跳转
  - relocation 应用
  - `hello / alloc_yield / time / bss / reloc / exit-code / fault` 运行结果
  - 非零退出码与故障结果统一输出
- 清理 aarch64 hosted `call-gate` 路径中剩余的“中间 ELF 依赖 / 过渡态实现”

### 2. `macos_arm64_hardvm` 正式接线

- `macos_arm64_hardvm` 已从“仅暴露 profile 名称”推进到：
  - Mach-O arm64 对象级 payload 提取已接通
  - `.uapp` 构建 / inspect / profile matrix 已纳入回归
  - macOS arm64 hosted runtime 已具备 host-gated 回归入口
- 继续收口：
  - runtime loader 真执行路径
  - macOS 下可执行映射、页权限、工具链与最小 trampoline 差异
  - macOS arm64 宿主上的实际 smoke / CI 绿灯

### 3. Bridge ABI 与宿主耦合进一步收口

- `@syscall` 与 `std.microapp.*` 在 hosted hard-vm profile 下统一走正式 runtime bridge ABI
- payload 不再直接依赖宿主 libc 普通符号或历史 helper 约定
- `unwired` / `validated` / `ok` / `exit` / `fault` 结果面统一到同一观测模型

### 4. profile / 发布验证升级

- profile 矩阵不再只停留在 compile-to-C / inspect 契约
- hosted hard-vm 形成“可构建、可运行、可分类结果、可 CI”的完整矩阵
- 发布前验证明确包含：
  - x86_64 hosted runtime 回归
  - aarch64 hosted runtime 回归
  - macOS arm64 hosted runtime 回归
  - `.uapp v1/v2` 兼容
  - recovery / update / structured fault

---

## 本版明确包含

- `Portable MicroApp ABI` / `.uapp v2` / `MicroAppTargetProfile` / bridge ABI 的规格冻结
- `linux_aarch64_hardvm` 真执行闭环
- `macos_arm64_hardvm` 构建链接通 + runtime host-gated 回归入口落地
- hosted hard-vm 统一 fault/result model
- microapp hosted 多平台 CI / 文档 / 发布口径同步

## 本版明确不包含

以下能力仍然重要，但不应混入 `v0.9.5` 的 release 主题：

- macOS `kqueue` / Windows `IOCP`
- HTTP 连接池与 keep-alive 复用
- TLS 会话复用
- DNS `A/AAAA` 并发聚合
- 真实 SQL driver（SQLite / MySQL / MariaDB）
- `std.yaml` / `std.protobuf`
- `build/run/test` 统一 CLI 的大规模迁移
- soft-vm 全语义对齐（`rv32` / `xtensa` 完整闭环）

这些更适合作为 `v0.9.6+` 或后续里程碑的主题，而不是打散 `v0.9.5`。

---

## 发布闸门

`v0.9.5` 发版前，至少需要满足：

共享发布闸门：

- `make b`
- `make release-clean`
- `make microapp-check`

hosted runtime 闸门：

- `make microapp-hosted-smoke`

宿主专属 runtime 闸门：

- `make microapp-aarch64-runtime-check`
- `make microapp-macos-runtime-check`

说明：

- `make release-clean` 继续承担共享发布闸门
- `aarch64` / `macos arm64` 的真实 runtime 绿灯由对应宿主 CI 单独承担，不把跨宿主验证伪装成本机 `release-clean` 结果

并满足以下结果口径：

- 同一份 portable source 在 `linux_x86_64_hardvm` / `linux_aarch64_hardvm` / `macos_arm64_hardvm` 下都能完成构建与 profile 契约验证
- 其中 `linux_x86_64_hardvm` / `linux_aarch64_hardvm` / `macos_arm64_hardvm` 在对应宿主上都应命中真实 payload 执行路径
- `hello / exit-code / fault / recovery` 结果分类一致
- CI 与文档中的 profile 名称、默认行为、示例矩阵保持一致

---

## 建议提交顺序

1. 规格冻结：`Portable MicroApp ABI` / `.uapp v2` / bridge / result model
2. `linux_aarch64_hardvm` 真执行转正
3. `macos_arm64_hardvm` 接线
4. profile 级 CI / hosted runtime 闸门升级
5. release 文档、迁移文档、README 与示例同步

---

## 一句话定义

`v0.9.5 = microapp hosted 多平台真执行闭环版`
