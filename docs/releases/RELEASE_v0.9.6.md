# Uya v0.9.6 发布说明

> **类型**：**v0.9.x 发行线上的补丁版本**（patch）  
> **发布日期**：2026-05-12

在 **v0.9.5** 的 microapp hosted 多平台闭环基础上，**v0.9.6** 继续做发布线收口：统一 trap/runtime bridge ABI 与 loader 结果面，正式让 `.uapp` 的 `required_caps` 参与 `SYS_IO` 白名单判定，并把 Linux toolchain / payload symbol / CLI 设计文档同步到同一条发行线上。

---

## 核心变更

### 1. microapp 结果面与 trap/runtime bridge ABI 统一

- `lib/kernel/sim.uya`：
  - trap runtime 路径统一到当前 bridge ABI 约定；
  - `ok / exit / fault / validated / unwired` 结果面继续收口；
  - 保持 `fault class / code / signal` 与 hosted loader 输出一致。
- `lib/std/runtime/microapp/loader.uya`：
  - loader / native fallback / unwired 路径统一输出单行 `payload result=...`；
  - 旧的分叉 fault 诊断输出继续收缩，减少脚本与宿主口径不一致。
- 回归与锁定：
  - 新增 `tests/verify_microapp_result_surface.sh`
  - 扩展 `tests/verify_microapp_trap_runtime.sh`
  - 扩展 `tests/verify_microapp_trap_bridge_result.sh`
  - 扩展 `tests/verify_microapp_loader_unwired_profile.sh`

### 2. `.uapp required_caps` 正式映射到 `SYS_IO` 白名单

- 新增 `lib/kernel/capability.uya`：
  - 定义 `KERNEL_CAP_IO_UART`、`KERNEL_CAP_IO_GPIO`、`KERNEL_CAP_IO_TIMER`
  - 提供 `kernel_required_caps_validate(required_caps)` 校验未知 capability bit
- `lib/kernel/dispatch.uya`：
  - 根据 `.uapp` 头部 `required_caps` 建立当前槽位 `SYS_IO` 设备与操作白名单
  - 未声明 capability 的设备不会被放通
  - 含未知 capability bit 的镜像会被明确拒绝
- `lib/kernel/sim.uya`：
  - 补齐宿主桩对 capability -> device/op 授权面的联动
- 新增 / 扩展测试：
  - 新增 `tests/test_kernel_dispatch.uya`
  - 扩展 `tests/test_kernel_sim.uya`

### 3. Linux toolchain / payload symbol 合约继续锁定

- 新增 `tests/verify_microapp_payload_symbols.sh`，持续拒绝 payload C 直接泄漏宿主 libc 普通符号，并锁定 Linux microapp runtime P0 合约。
- `tests/verify_microapp_fault_runtime.sh`、`tests/verify_microapp_aarch64_hosted_runtime.sh`、`tests/verify_microapp_macos_arm64_hosted_runtime.sh` 继续对齐统一结果面与诊断输出。
- `docs/microcontainer/microapp_profiles.md`、`docs/microcontainer/portable_native_design.md`、`docs/microcontainer/syscall_abi.md` 同步当前 profile / result / capability 契约。

### 4. CLI 子命令拆分设计文档同步

- `docs/cmd_subcommand_split_design.md`
- `docs/todo_cmd_subcommand_split.md`

这两份文档已按当前实现状态重排设计与 TODO，作为后续 `build` / `run` / `test` / image 相关子命令收口的统一基线。`v0.9.6` 本身不引入新的 CLI 破坏性语法变更，但把下一阶段拆分工作的文档口径整理到可继续推进的状态。

---

## 升级指南

从 `v0.9.5` 升级到 `v0.9.6`：

```bash
git pull
git checkout v0.9.6

make clean && make check
make microapp-check
make microapp-hosted-smoke
```

如果你在对应宿主上验证 hosted runtime，建议额外执行：

```bash
make microapp-aarch64-runtime-check
make microapp-macos-runtime-check
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 `v0.9.5` | 见 `git log v0.9.5..HEAD` |
| 全量回归 | `make backup-all` 通过（2026-05-12；含 `make check` 与 seed / backup 刷新） |
| microapp 聚合验证 | `make microapp-check` 通过；`make microapp-hosted-smoke` 通过 |
| 宿主专属 runtime | 当前 `Linux x86_64` 宿主上，`make microapp-aarch64-runtime-check` 按设计输出 `skip (host_arch=x86_64)`；`make microapp-macos-runtime-check` 按设计输出 `skip (host_os=Linux)` |
| 最终 clean-tree release | 发布提交落库后执行 `make release` 作为最终干净树复核 |
| 上一标签 | `v0.9.5` |

---

## 致谢

感谢所有为本版本贡献代码、测试、CI 与文档整理的参与者。

---

**标签**：`v0.9.6`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.9.6)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
