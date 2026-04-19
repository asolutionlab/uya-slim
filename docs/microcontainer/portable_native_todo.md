# Uya 微程序可移植 Native 运行 TODO

**版本**: v0.1  
**日期**: 2026-04-19  
**对应设计**: `docs/microcontainer/portable_native_design.md`

---

## 1. 目标

本待办只服务一个目标：

- 同一份 `microapp` 源码一次编写
- 在不同目标平台分别编译
- 以对应平台的 native payload 运行
- 运行时由微容器 loader 真正装载并执行 `.uapp`

本待办不追求：

- 单一二进制跨 ISA 复用
- 第一阶段覆盖全部 libc 能力
- 第一阶段统一完成所有 hosted / baremetal 平台

---

## 2. 里程碑

### M1：Linux x86_64 真执行

- `.uapp v2` 可表达真实执行所需段信息
- `linux_x86_64_hardvm` profile 可用
- `run --app microapp` 不再依赖对照 ELF
- payload 从容器虚拟地址入口真执行
- `SYS_PRINT / SYS_ALLOC / SYS_YIELD` 可用
  - 当前已有 x86_64 mapped payload 回归覆盖 `print + alloc + yield`
- `.bss` 能正确以零初始化 RW 区域参与装载和执行

### M2：Hosted 多平台

- `linux_aarch64_hardvm` 可用
- `macos_arm64_hardvm` 可用
- 同一份源码可在多个 hosted profile 编译并 native 运行

### M3：Soft-VM 对齐

- `rv32_baremetal_softvm` 可用
- `xtensa_baremetal_softvm` 可用
- hard-vm / soft-vm 对上层暴露统一虚拟地址语义

---

## 3. 阶段 0：规格冻结

- [ ] 冻结 `Portable MicroApp ABI` 最小源码子集
- [ ] 冻结 `MicroAppTargetProfile` 字段集合
- [ ] 冻结 `.uapp v2` header / segment / relocation 基本格式
- [ ] 冻结 syscall bridge 形式：
  - `trap bridge`
  - `call-gate bridge`
- [ ] 明确 `hard-vm` / `soft-vm` 的统一语义边界

验收标准：

- [ ] 术语、字段、运行模式在设计文档中不再反复改名
- [ ] 后续实现 PR 不再重新定义镜像头和 profile 结构

---

## 4. 阶段 1：镜像格式升级

### 4.1 `PayloadObj`

- [x] 为 [payload.uya](/home/winger/uya/uya/lib/kernel/payload.uya) 新增：
  - `profile_id`
  - `data`
  - `bss_size`
  - `stack_size_hint`
  - `relocations`
  - `flags`
- [~] 将 `entry_offset` 升级为正式 `entry_va`
  - [x] `.pobj v7` / `.uapp v2` 已携带 `entry_va`
  - [x] `sim_exec_loaded()` 已按 `entry_va` 完成 x86_64 call-gate 入口跳转
  - [ ] 其他 profile / bridge 仍未统一到同一入口语义
- [x] 保持 v1/v2 打包入口能并存

### 4.2 `ImageHeader`

- [x] 升级 [image.uya](/home/winger/uya/uya/lib/kernel/image.uya) 支持 v2
- [x] 增加段偏移与段大小字段
- [x] 增加 relocation 区描述
- [x] 增加 profile / bridge 元数据
- [x] 增加 `entry_va` 校验

### 4.3 打包与校验

- [x] `pack-image` 支持 v2 生成
- [x] `image_validate()` 支持 v2 结构检查
- [x] 增加 `.uapp v2` roundtrip 测试

验收标准：

- [x] v1 / v2 `.pobj` 打包入口兼容读取
- [~] v1 `.uapp` / v2 `.uapp` 双版本读取与显式 inspect/verify CLI
  - [x] 已新增 `inspect-image` CLI，可直接查看 `.pobj/.uapp` 头信息
  - [x] 已新增 `verify-image` CLI，可直接校验 `.pobj/.uapp`
  - [x] 已补齐 `v1 .uapp / v2 .uapp / v5-v8 .pobj` CLI 回归覆盖

---

## 5. 阶段 2：编译链升级

### 5.1 Target Profile

- [x] 在 [main.uya](/home/winger/uya/uya/src/main.uya) 引入正式 `MicroAppTargetProfile`
- [~] 将当前 `MICROAPP_TARGET_ARCH` 扩展为 profile 驱动
  - [x] 新增 `MICROAPP_TARGET_PROFILE`
  - [x] `.pobj` / `.uapp` 已携带 `profile_id`
  - [x] CLI / 文档 / 默认行为已切到 profile-first 心智
    - [x] 已新增 `--microapp-profile` CLI 覆盖
    - [x] 默认行为与帮助文本已优先围绕 profile 与 target tuple 推导
- [~] 建立首批 profile 常量/映射：
  - [x] `linux_x86_64_hardvm`
  - [x] `linux_aarch64_hardvm`
  - [ ] `macos_arm64_hardvm`
  - [x] `rv32_baremetal_softvm`
  - [x] `xtensa_baremetal_softvm`

### 5.2 Segment/Reloc 提取

- [x] 不再只抽 `.text/.rodata`
- [x] 提取 `.data`
- [x] 计算 `.bss`
- [x] 提取 relocation 表
- [x] 计算 `entry_va`

### 5.3 PIC / PIE

- [x] `hard-vm` profile 默认使用 PIC/PIE 友好参数
- [ ] `soft-vm` profile 保留现有插桩路径但统一镜像输出契约

验收标准：

- [x] 编译器能产出包含段与 relocation 信息的 `.pobj/.uapp v2`
  - [x] 已能产出包含 `data/profile/bridge/flags/reloc` 的 v2 `.pobj/.uapp`

---

## 6. 阶段 3：Bridge ABI 正式化

### 6.1 Codegen

- [~] 收敛 [main.uya](/home/winger/uya/uya/src/codegen/c99/main.uya) 中现有 `uya_microapp_syscall*` helper
  - [x] `lib/std/microapp/*` 内部 `@syscall` 已强制走 microapp bridge
  - [ ] helper 仍是过渡形态，尚未升级为最终 runtime bridge ABI
- [~] 把宿主 helper 符号依赖升级为正式 bridge ABI
  - [x] 当前 hosted helper 已不再依赖仓库私有 `write_stdout_bytes`
  - [ ] 仍未切到真正 runtime call-gate / trap bridge
- [ ] `microapp` payload 不再直接依赖宿主 libc 普通符号

### 6.2 Source ABI

- [~] 定义 `std.microapp.*` 最小 API：
  - [x] `std.microapp.io`
  - [x] `std.microapp.mem`
  - [x] `std.microapp.task`
  - [x] `std.microapp.time`
- [ ] 审计并限制直接宿主 libc API 使用

验收标准：

- [~] `@syscall` 与 `std.microapp.*` 都统一走 bridge
  - [x] 直接 `@syscall`
  - [x] `std.microapp.io` wrapper
  - [x] `std.microapp.mem` / `std.microapp.task` wrapper
  - [x] `std.microapp.time` wrapper
- [x] kernel/runtime 侧 syscall ABI 已补齐 `SYS_TIME`
- [~] payload 中不再出现 `write_stdout_bytes` / `posix_memalign` / `sched_yield` 这类宿主 helper 符号耦合
  - [x] 当前 codegen 回归已覆盖 `posix_memalign / sched_yield / gettimeofday` 不直接出现在 microapp payload 里
  - [ ] 仍未切到真正 runtime call-gate / trap bridge

---

## 7. 阶段 4：Linux x86_64 hard-vm 真执行

### 7.1 Loader

- [~] 升级 [loader.uya](/home/winger/uya/uya/lib/std/runtime/microapp/loader.uya)：
  - [x] `linux_x86_64_hardvm + call-gate` 路径不再启动 native payload 对照 ELF
  - [x] 已真正调用 runtime execution path
  - [~] 其他 profile 仍保留 fallback / 未接线路径
    - [x] 未接线路径已改为显式报错，不再静默 `done`

### 7.2 Runtime Mapping

- [~] 在 [sim.uya](/home/winger/uya/uya/lib/kernel/sim.uya) 新增段级映射状态
  - [x] 已按 `code_va/rodata_va/data_va` 建立段级页权限映射
  - [x] `.bss` 已作为 `data_va + data_size` 之后的零初始化 RW 区域参与映射
  - [x] 已记录 `base_vpn/page_count` 级别的运行时加载元数据
- [~] 用 `mmap/mprotect` 建立 `RX/R/RW` 映射
  - [x] hosted loader 已分配可执行 backing，并由页表保留 `RX/R/RW` 语义
  - [x] x86_64 hosted loader 已按页表权限对宿主页执行 `mprotect`
- [~] 建立 stack / heap 初始区域
  - [x] `SYS_ALLOC` 已从镜像末尾之后的 heap 区顺序分配
  - [x] `stack_size_hint` 已在 sim 中保留高地址栈页
  - [x] 真实 microapp 构建产物已默认写入 `stack_size_hint`
  - [x] x86_64 call-gate 真执行已切到容器私有栈页
- [~] 建立 call-gate 页面或 trampoline
  - [x] 已新增最小 x86_64 trampoline helper，并有内核级单测覆盖
  - [ ] 其余架构 / 真正的 per-profile trampoline 仍待补齐

### 7.3 真执行

- [~] 把 `sim_exec_loaded()` 从“校验入口”升级为“跳转入口执行”
  - [x] `linux_x86_64_hardvm + ibk_call_gate` 已跳转执行 mapped payload
  - [~] trap bridge / 其他架构仍停留在校验或过渡态
    - [x] trap bridge 路径已显式写入 `validated` 结果面，不再隐式折叠为 `exit 0`
    - [ ] 其他架构仍待补齐真正执行路径
- [~] 入口调用前应用 relocation
  - [x] `linux_x86_64_hardvm` 已在入口前应用最小 `RELATIVE` relocation
  - [ ] 其余架构 / relocation 类型仍待继续规范化与接线
- [~] 执行后能正确返回 yield / exit / error
  - [x] 当前已覆盖 `yield`
  - [x] `linux_x86_64_hardvm` 已透传非零 `main()` exit code
  - [x] `linux_x86_64_hardvm` 已覆盖 fault/error 路径的可观测信号退出状态
  - [~] 崩溃/故障到统一错误模型仍待继续细化
    - [x] x86_64 hosted 路径已统一到 `fault_class / fault_code / fault_signal`
    - [x] sim/recovery 路径已把 structured fault 写入 crash log
    - [ ] 其他后端 / bridge 仍待接入同一结果模型

验收标准：

- [~] `run --app microapp examples/microapp/microcontainer_hello_source.uya`
  不再依赖 `.text.bin.elf`
  - [x] x86_64 hard-vm 运行时已不再依赖对照 ELF
  - [ ] 构建期仍依赖 ELF 提取 section/VMA
- [x] `hello microapp` 能由 `.uapp` 真执行输出
- [x] `alloc + yield` 能在 x86_64 mapped payload 路径中执行
- [x] `time` 能在 x86_64 mapped payload 路径中执行
- [x] `bss` 能在 x86_64 mapped payload 路径中正确零初始化并执行

---

## 8. 阶段 5：Hosted 多平台扩展

### 8.1 Linux aarch64

- [ ] 实现 `linux_aarch64_hardvm`
- [ ] 增加 aarch64 trampoline
- [ ] 增加 aarch64 hosted 回归

### 8.2 macOS arm64

- [ ] 实现 `macos_arm64_hardvm`
- [ ] 处理 macOS 下可执行映射与签名/权限差异
- [ ] 增加 macOS hosted 回归

验收标准：

- [ ] 同一份源码在 x86_64 / aarch64 / macOS arm64 可分别编译运行

---

## 9. 阶段 6：Soft-VM 后端

### 9.1 RV32

- [ ] 定义 `rv32_baremetal_softvm` profile
- [ ] 将现有 trap/页表模型收口到统一 profile
- [ ] 统一 segment 装载与地址模型

### 9.2 Xtensa

- [ ] 定义 `xtensa_baremetal_softvm` profile
- [ ] 对齐 trap / bridge / 调度行为

### 9.3 统一语义

- [ ] hard-vm / soft-vm 对同一源码给出一致错误模型
- [ ] 相同 syscall / capability 行为一致

验收标准：

- [ ] 同一份源码在 hosted hard-vm 和 baremetal soft-vm 上语义一致

---

## 10. 阶段 7：源码可移植子集收敛

- [~] 用 `std.microapp.*` 重写当前示例
  - [x] `examples/microapp/microcontainer_hello_source.uya`
  - [x] `examples/microapp/microcontainer_alloc_yield_source.uya`
  - [x] `examples/microapp/microcontainer_time_source.uya`
  - [x] `examples/microapp/microcontainer_bss_source.uya`
  - [x] `examples/microapp/microcontainer_reloc_source.uya`
  - [~] `microcontainer_hello_build/load` 仍是宿主侧工具示例，不属于 portable source 子集
- [~] 审计现有 microapp 示例里宿主耦合 API
  - [x] 已区分 portable source 与 hosted build/load 工具示例
  - [x] 当前 portable source 样例已纳入无 `libc/std.time` 依赖回归
  - [x] 当前 portable source 官方示例已纳入 codegen bridge 回归
- [~] 为不允许的宿主 API 增加明确诊断
  - [x] 用户 microapp 直接 `use/call libc/*` / `std.time` 现在会在编译期报 `E4004`
  - [x] 已增加专门的 host API 诊断回归覆盖
  - [ ] 其余 hosted helper / bridge 误用仍待继续审计
- [x] 为“一次编写、多个 profile 编译”增加示例矩阵

验收标准：

- [~] 官方示例不再依赖宿主特有 helper
  - [x] 当前 portable source 示例集已不依赖宿主 helper
  - [ ] host-side build/load 工具示例仍保留宿主依赖
- [x] 用户能从示例中直接看到“源码级多 profile 编译”最佳实践

---

## 11. 阶段 8：验证与发布

- [x] 增加 `.uapp v1/v2` 兼容回归
- [~] 增加 profile 级 CI
  - [x] 已新增 `make microapp-check` 聚合 microapp 回归入口
  - [x] `ubuntu-ci` 已接入 `make microapp-check`
  - [x] `macos-ci` 已接入 `make microapp-hosted-smoke`
- [~] 增加真执行回归
  - [x] 当前已覆盖 x86_64 `hello/alloc_yield/time/bss/reloc/exit-code/fault` 真执行回归
  - [x] trap bridge 已补充 `validated` 结果面 smoke
  - [ ] 其余 profile 真执行仍待补齐
- [~] 增加 crash/recovery / update 回归
  - [x] 已新增 `make microapp-recovery-check` 入口
  - [x] 当前已覆盖 `test_kernel_update.uya` 与 `test_kernel_sim.uya`
  - [x] crash log 已回归 `fault_class / fault_code / fault_signal`
- [x] 发布迁移指南

验收标准：

- [~] 文档、示例、CLI、回归测试一致
  - [x] 当前已统一到 `make microapp-check` 聚合入口
  - [x] Ubuntu CI / README / Makefile help / 官方示例 / microapp 回归清单已对齐
  - [x] `.uapp v1/v2` 兼容回归已具备独立入口 `make microapp-compat-check`
  - [x] 当前已补充 `migration_guide.md` 收敛旧路径 -> 新路径迁移说明
  - [x] `microapp_source_template.md` / `source_to_uapp_pipeline.md` 已切到 `profile-first + portable source` 心智
  - [x] `README.md` / `update_recovery.md` 已补齐 structured fault 与 recovery log 现状说明
  - [ ] 其余平台与发布文档仍待继续对齐

---

## 12. 当前优先级

建议当前按这个顺序开工：

1. `阶段 0：规格冻结`
2. `阶段 1：镜像格式升级`
3. `阶段 2：编译链升级`
4. `阶段 3：Bridge ABI 正式化`
5. `阶段 4：Linux x86_64 hard-vm 真执行`

原因：

- 这是最短路径
- 也是最容易先交付一个“真的虚拟地址执行”的平台样板
- 成功后，其他 hosted / soft-vm 平台都可以沿同一框架扩展
