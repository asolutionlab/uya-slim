# Uya v0.9.5 发布收口 TODO

**日期**：2026-04-23  
**状态**：进行中  
**对应发布说明**：`docs/releases/RELEASE_v0.9.5.md`  
**对应主线待办**：`docs/microcontainer/portable_native_todo.md`

---

## 1. 目的

这份待办只记录 `v0.9.5` 发版前还需要收口的事项。

它不重复展开所有 microapp 历史背景，只服务一个目标：

- 把 `v0.9.5` 从“目标草案”推进到“可发布结论”
- 明确哪些项已经完成，哪些项仍然缺最终验收
- 把 release 闸门、CI 闸门、文档口径统一起来

---

## 2. 当前基线（已确认）

以下结论已经在当前分支或本地环境确认，可视为 `v0.9.5` 的现有基线：

- [x] `make b` 当前可通过
- [x] `make release-clean` 当前可通过（基于 Git HEAD 干净快照）
- [x] `make microapp-check` 当前可通过
- [x] `make microapp-hosted-smoke` 当前可通过
- [x] `tests/verify_microapp_aarch64_object_extract.sh` 当前可通过
- [x] `tests/verify_microapp_macos_object_extract.sh` 当前可通过
- [x] `tests/verify_microapp_macos_profile_guard.sh` 当前可通过
- [x] `tests/verify_microapp_profile_example_matrix.sh` 当前可通过
- [x] `tests/verify_microapp_profile_default_resolution.sh` 当前可通过
- [x] `linux_x86_64_hardvm` 真执行主链路已成立
- [x] `linux_aarch64_hardvm` 已具备 host-gated runtime 回归入口
- [x] `macos_arm64_hardvm` 已具备 Mach-O arm64 对象提取与 host-gated runtime 回归入口
- [x] `make microapp-check` 已覆盖 `.uapp v1/v2`、trap result、recovery/update 等聚合回归

当前基线的限制也需要明确：

- [x] 当前本地宿主为 `Linux x86_64`
- [x] `make microapp-aarch64-runtime-check` 在本机只会按设计 skip，不构成 arm64 真执行证明
- [x] `make microapp-macos-runtime-check` 在本机只会按设计 skip，不构成 macOS arm64 真执行证明
- [x] `make microapp-hosted-smoke` 中对 `aarch64` / `macos arm64` runtime 的覆盖，当前也只是脚本存在且可被宿主 gate，不等于对应宿主已经实跑绿灯
- [x] `make release-clean` 当前只验证 Git HEAD 快照，不覆盖工作树里尚未提交的新脚本/新文档

---

## 3. P0：发布阻塞项

### 3.1 规格冻结

- [x] 冻结 `Portable MicroApp ABI` 最小源码子集
- [x] 冻结 `MicroAppTargetProfile` 对外字段集合与命名
- [x] 冻结 `.uapp v2` header / segment / relocation 基本格式
- [x] 冻结 `call_gate` / `trap` bridge ABI 命名与行为
- [x] 冻结统一 `payload result` / `fault_class` / `fault_code` / `fault_signal` 结果面
- [x] 明确 `hard-vm` / `soft-vm` 的统一语义边界

验收口径：

- [x] `portable_native_design.md` / `portable_native_todo.md` / `RELEASE_v0.9.5.md` 对上述术语不再反复改名
- [x] 后续实现不再继续变更镜像头、profile 字段和结果字段口径

### 3.2 `linux_aarch64_hardvm` 真执行签收

- [ ] 在 arm64 宿主或 arm64 CI 上实际执行一次 `make microapp-aarch64-runtime-check`
- [ ] 保留一次真实绿灯记录，作为 release 证据
- [ ] 确认 `hello / alloc_yield / time / bss / reloc / reloc_data / exit-code / fault` 都命中真实 payload 执行路径
- [ ] 确认运行日志命中 `executed mapped payload`
- [ ] 确认运行日志没有回退到 `launching native payload`
- [ ] 确认 `fault_class / fault_code / fault_signal` 输出口径与 x86_64 一致
  - 当前阻塞：需 arm64 宿主或 arm64 CI 的真实执行结果；本地 `Linux x86_64` 环境只能看到 host-gated skip
  - 当前进展：已于 `2026-04-23` 在本机补跑 `make microapp-aarch64-runtime-check`，输出 `microapp aarch64 hosted runtime skipped (host_arch=x86_64)`，再次确认当前缺口是宿主签收而不是脚本入口缺失
  - 当前进展：已核对公开 `macos-ci` 历史记录，当前 `origin/main` 对应的 `macos-15` workflow 仍在 `Bootstrap seed compiler from hosted backup` 处提前失败，`Run microapp aarch64 hosted runtime` 还没有真正执行到
  - 当前进展：已在当前分支把 `.github/workflows/macos-ci.yml` 的 bootstrap 入口从 `make from-c` 修正为 `make from-c-native`，并补了 `workflow_dispatch`，为后续 arm64 CI 真执行解锁前置条件
  - 当前进展：新一轮公开 `macos-ci` 已确认跑到 `Bootstrap seed compiler from native hosted seed`；当前分支已继续修正 `from-c-native` 的 macOS seed 选择顺序为 `backup/uya-hosted-macos-<arch>.c` 优先，并刷新了 `backup/uya-hosted-macos-arm64.c` / `backup/uya-hosted-macos-x86_64.c` 以消除 `char* -> uint8_t*` 的 `-Werror` 构建失败
  - 当前进展：`tests/verify_microapp_aarch64_hosted_runtime.sh` 已把 `hello / alloc_yield / time / bss / reloc / reloc_data / exit-code / fault` 全部写入真执行断言
  - 当前进展：脚本已要求日志命中 `executed mapped payload`、不出现 `launching native payload`
  - 当前进展：脚本已要求 `fault_class / fault_code / fault_signal` 结果口径对齐当前 `x86_64` hosted loader

### 3.3 `macos_arm64_hardvm` 真执行签收

- [ ] 在 macOS arm64 宿主或 CI 上实际执行一次 `make microapp-macos-runtime-check`
- [ ] 保留一次真实绿灯记录，作为 release 证据
- [ ] 确认 `hello / alloc_yield / time / bss / reloc / reloc_data / exit-code / fault` 都命中真实 payload 执行路径
- [ ] 确认运行日志命中 `executed mapped payload`
- [ ] 确认运行日志没有回退到 `launching native payload`
- [ ] 确认 macOS 下的页权限 / 映射 / trampoline 差异没有再引出 profile 特例错误
  - 当前阻塞：需 macOS arm64 宿主或 CI 的真实执行结果；本地环境无法完成最终签收
  - 当前进展：已于 `2026-04-23` 在本机补跑 `make microapp-macos-runtime-check`，输出 `microapp macos arm64 hosted runtime skipped (host_os=Linux)`，再次确认当前缺口是宿主签收而不是脚本入口缺失
  - 当前进展：`tests/verify_microapp_macos_arm64_hosted_runtime.sh` 已把 `hello / alloc_yield / time / bss / reloc / reloc_data / exit-code / fault` 全部写入真执行断言
  - 当前进展：脚本已要求日志命中 `executed mapped payload`、不出现 `launching native payload`
  - 当前进展：脚本已要求 `fault_class / fault_code / fault_signal` 维持和当前 hosted fault/result model 一致

### 3.4 Release / CI 闸门对齐

- [x] 决定 `make release` / `make release-clean` 是否直接串入以下命令
  - `make microapp-hosted-smoke`
  - `make microapp-aarch64-runtime-check`
  - `make microapp-macos-runtime-check`
- [x] 如果 release 不直接串入上述命令，则在发布说明中明确“平台专属 runtime 闸门由对应 CI 单独承担”
- [x] 在 `macos-ci` 中显式增加 standalone `make microapp-macos-runtime-check`
- [x] 确认 `ubuntu-ci` / `macos-ci` 的职责边界和发布说明一致
- [x] 确认新脚本、新文档、新 Makefile 入口都已提交到 Git，避免 `make release-clean` 仍在验证旧快照
  - 当前进展：已将 `docs/releases/*`、`Makefile`、`.github/workflows/macos-ci.yml`、`docs/microcontainer/*`、`src/main.uya` 与新增/更新的 hosted runtime 回归脚本纳入当前 Git HEAD
  - 当前进展：`macos-ci` 的 seed bootstrap 已修正为 `make from-c-native`，并补 `workflow_dispatch`，避免 Apple Silicon runner 继续卡在过时的 `make from-c` 入口
  - 当前进展：已于 `2026-04-23` 在当时最新的 Git HEAD 上补跑 `make release-clean`，确认当前已提交快照可发布

---

## 4. P1：文档与口径同步

- [x] 更新 `docs/microcontainer/README.md` 中关于 `aarch64` hosted 构建链“仍依赖中间 ELF”的旧表述
- [x] 在 `docs/microcontainer/README.md` 中补充 `make microapp-macos-runtime-check`
- [x] 在 `docs/microcontainer/migration_guide.md` 中补充 macOS arm64 runtime 检查入口
- [x] 在 `docs/microcontainer/microapp_source_template.md` 中补充多平台 hosted runtime 闸门说明
- [x] 更新 `docs/microcontainer/portable_native_todo.md`，把已完成的 object extract / profile / gate 状态改成当前真实状态
- [x] 更新 `docs/releases/RELEASE_v0.9.5.md`，把“版本目标”和“当前事实”拆开写
- [ ] 发版前补齐发布日期、验证统计、宿主矩阵结果
  - 当前进展：已补 `2026-04-23` 本机验证统计；`make b` / `make microapp-check` / `make microapp-hosted-smoke` 已于当日复核通过，`make release-clean` 已于当日在当前分支最新已提交快照上通过
  - 当前进展：`make microapp-aarch64-runtime-check` / `make microapp-macos-runtime-check` 在本机 `Linux x86_64` 上按设计 host-gated skip，相关矩阵已写入 release 草案
  - 当前剩余：最终发布日期以及 arm64 / macOS arm64 宿主真执行统计，仍待最后一次发版前整理

---

## 5. P1：剩余实现收口

这些项不一定都阻塞首版发布，但至少要明确是否延期，而不是保持模糊状态：

- [x] 审计其余 hosted helper / bridge 误用路径
  - 当前已确认：`verify_microapp_example_codegen.sh` 持续检查官方 portable source 生成代码不直接出现 `UYA_HOST_SYS_*` / `posix_memalign` / `sched_yield` / `gettimeofday` / `malloc` / `free` / `fprintf` / `getenv` / `abort`
  - 当前已确认：`verify_microapp_example_codegen.sh` / `verify_microapp_syscall_codegen.sh` 持续检查 microapp 生成代码不回退到历史 `uya_microapp_syscall` helper，而是统一走 `uya_microapp_bridge_dispatch*`
  - 当前已确认：`verify_microapp_host_api_diagnostics.sh` 持续检查 microapp 模式下直接导入 `libc.*` / `std.time` 会被 `E4004` 拒绝
- [x] 继续减少 payload 对宿主 libc 普通符号的直接耦合
  - 当前已确认：`tests/verify_microapp_portable_sources.sh` 现已把官方 portable source、`test_microapp_mmu_codegen.uya`、`test_microapp_mmu_runtime.uya`、`test_std_microapp_exit_nonzero.uya`、`test_std_microapp_fault_segv.uya` 一并纳入 `--app microapp` 编译与 payload C 输出审计
  - 当前已确认：上述源码生成的 payload C 持续拒绝 `UYA_HOST_SYS_*`、历史 `uya_microapp_syscall` helper、以及 `posix_memalign / sched_yield / gettimeofday / malloc / free / fprintf / getenv / abort` 这类宿主 libc 普通符号
- [x] 评估 trap bridge / 其他 backend 接入统一 ABI 的切分计划
  - 第一刀：继续保持 `Portable MicroApp ABI` / `PayloadObj` / `.uapp v2` / `payload result` 口径统一，不在 soft-vm 侧再发散新字段
  - 第二刀：先以 `rv32_baremetal_softvm` 为唯一 trap bridge 主验证目标，对齐 `std.microapp.* -> @syscall -> bridge` 的源码层入口
  - 第三刀：把 trap bridge 的完成标准限定为“同样输出 `ok / exit / fault / validated / unwired` 结果面”，不要求先做完整 hosted 级映射能力
  - 第四刀：`xtensa_baremetal_softvm` 放在 `rv32` 之后，只复用同一结果模型、镜像字段和 bridge 命名，不单独发明新 ABI
- [x] 继续区分 portable source 示例与 host-side build/load 工具示例
  - 已新增 `tests/verify_microapp_example_boundary.sh`
  - 已接入 `make microapp-check` 与 `make microapp-hosted-smoke`

---

## 6. 建议执行顺序

1. 先冻结 `Portable MicroApp ABI` / `.uapp v2` / profile / bridge / result model 文档口径
2. 再在 arm64 宿主上拿到 `linux_aarch64_hardvm` 的一次真实 runtime 绿灯
3. 再在 macOS arm64 宿主上拿到 `macos_arm64_hardvm` 的一次真实 runtime 绿灯
4. 然后把 release / CI 闸门责任边界写死
5. 最后统一 README、迁移文档、发布说明和 TODO 状态

---

## 7. 发版前最小验收清单

- [x] `make b`
- [x] `make release-clean`
- [x] `make microapp-check`
- [x] `make microapp-hosted-smoke`
- [ ] `make microapp-aarch64-runtime-check`
- [ ] `make microapp-macos-runtime-check`

并满足以下结论：

- [x] 同一份 portable source 在 `linux_x86_64_hardvm` / `linux_aarch64_hardvm` / `macos_arm64_hardvm` 下都能完成构建与 profile 契约验证
  - 当前依据：`tests/verify_microapp_profile_example_matrix.sh` 已覆盖三套 hosted hard-vm profile 的 compile-to-C 与 `.uapp` inspect 契约
- [ ] `linux_x86_64_hardvm` / `linux_aarch64_hardvm` / `macos_arm64_hardvm` 在对应宿主上都命中真实 payload 执行路径
  - 当前进展：`linux_x86_64_hardvm` 已在本机真执行成立
  - 当前进展：`linux_aarch64_hardvm` / `macos_arm64_hardvm` 的 runtime 脚本已经把真实 payload 执行路径断言写死，但仍缺对应宿主上的最终绿灯
- [ ] `hello / exit-code / fault / recovery` 结果分类一致
  - 当前进展：`linux_x86_64_hardvm` hosted loader 与 `recovery/update` 链路已经统一输出 `ok / exit / fault / validated / unwired` 结果面
  - 当前进展：`linux_aarch64_hardvm` / `macos_arm64_hardvm` runtime 脚本已要求 `hello / exit-code / fault` 与现有结果面一致，但仍缺对应宿主实跑签收
- [x] CI、README、迁移文档、发布说明中的 profile 名称和默认行为一致
  - 当前依据：`tests/verify_microapp_profile_default_resolution.sh` 持续检查默认 profile 推导；README / 迁移文档 / release 草案 / `macos-ci` 已同步到当前入口与命名

---

## 8. 当前判断

如果只看代码和本地可跑回归，`v0.9.5` 已经不再是“从零开始接线”的阶段。

当前已经完成的收口：

- `规格冻结` 已正式落文
- `release / CI / 文档` 已完成第一轮对齐
- `Linux x86_64` 本机共享闸门已于 `2026-04-23` 实跑通过：`make b` / `make microapp-check` / `make microapp-hosted-smoke` / `make release-clean`
- `三套 hosted hard-vm profile` 的构建与 profile 契约验证已通过当前矩阵回归
- `payload` 对宿主 libc 普通符号的 codegen 审计已扩到 official source + MMU/exit/fault fixture
- `v0.9.5` 当前脚本、文档、Makefile 与 CI 入口已纳入 Git HEAD

当前剩余的主要缺口：

- `linux_aarch64_hardvm` 还缺对应 arm64 宿主上的最终真执行签收
- `macos_arm64_hardvm` 还缺对应 macOS arm64 宿主上的最终真执行签收
- 发布前仍需补齐发布日期、验证统计、宿主矩阵结果，并在最新提交上拿到对应宿主绿灯

因此，下一阶段最合适的推进方式不是继续扩功能，而是围绕“对应宿主绿灯证据 + 最终发布材料”做最后收口。
