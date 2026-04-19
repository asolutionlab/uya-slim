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
  - [ ] 运行时还未真正以 `entry_va` 完成入口跳转
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
- [ ] v1 `.uapp` / v2 `.uapp` 双版本读取与显式 inspect/verify CLI 仍待补齐

---

## 5. 阶段 2：编译链升级

### 5.1 Target Profile

- [x] 在 [main.uya](/home/winger/uya/uya/src/main.uya) 引入正式 `MicroAppTargetProfile`
- [~] 将当前 `MICROAPP_TARGET_ARCH` 扩展为 profile 驱动
  - [x] 新增 `MICROAPP_TARGET_PROFILE`
  - [x] `.pobj` / `.uapp` 已携带 `profile_id`
  - [ ] CLI / 文档 / 默认行为还未完全切到 profile-first 心智
- [~] 建立首批 profile 常量/映射：
  - [x] `linux_x86_64_hardvm`
  - [x] `linux_aarch64_hardvm`
  - [ ] `macos_arm64_hardvm`
  - [x] `rv32_baremetal_softvm`
  - [x] `xtensa_baremetal_softvm`

### 5.2 Segment/Reloc 提取

- [x] 不再只抽 `.text/.rodata`
- [x] 提取 `.data`
- [ ] 计算 `.bss`
- [ ] 提取 relocation 表
- [x] 计算 `entry_va`

### 5.3 PIC / PIE

- [x] `hard-vm` profile 默认使用 PIC/PIE 友好参数
- [ ] `soft-vm` profile 保留现有插桩路径但统一镜像输出契约

验收标准：

- [~] 编译器能产出包含段与 relocation 信息的 `.pobj/.uapp v2`
  - [x] 已能产出包含 `data/profile/bridge/flags` 的 v2 `.pobj/.uapp`
  - [ ] relocation 仍未落地

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
  - [ ] `std.microapp.time`
- [ ] 审计并限制直接宿主 libc API 使用

验收标准：

- [~] `@syscall` 与 `std.microapp.*` 都统一走 bridge
  - [x] 直接 `@syscall`
  - [x] `std.microapp.io` wrapper
- [ ] payload 中不再出现 `write_stdout_bytes` / `posix_memalign` / `sched_yield` 这类宿主 helper 符号耦合

---

## 7. 阶段 4：Linux x86_64 hard-vm 真执行

### 7.1 Loader

- [ ] 升级 [loader.uya](/home/winger/uya/uya/lib/std/runtime/microapp/loader.uya)：
  - [ ] 不再启动 native payload 对照 ELF
  - [ ] 真正调用 runtime execution path

### 7.2 Runtime Mapping

- [ ] 在 [sim.uya](/home/winger/uya/uya/lib/kernel/sim.uya) 新增段级映射状态
- [ ] 用 `mmap/mprotect` 建立 `RX/R/RW` 映射
- [ ] 建立 stack / heap 初始区域
- [ ] 建立 call-gate 页面或 trampoline

### 7.3 真执行

- [ ] 把 `sim_exec_loaded()` 从“校验入口”升级为“跳转入口执行”
- [ ] 入口调用前应用 relocation
- [ ] 执行后能正确返回 yield / exit / error

验收标准：

- [ ] `run --app microapp examples/microapp/microcontainer_hello_source.uya`
  不再依赖 `.text.bin.elf`
- [ ] `hello microapp` 能由 `.uapp` 真执行输出

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
  - [ ] 其余示例仍待迁移
- [ ] 审计现有 microapp 示例里宿主耦合 API
- [ ] 为不允许的宿主 API 增加明确诊断
- [ ] 为“一次编写、多个 profile 编译”增加示例矩阵

验收标准：

- [ ] 官方示例不再依赖宿主特有 helper
- [ ] 用户能从示例中直接看到“源码级可移植”最佳实践

---

## 11. 阶段 8：验证与发布

- [ ] 增加 `.uapp v1/v2` 兼容回归
- [ ] 增加 profile 级 CI
- [ ] 增加真执行回归
- [ ] 增加 crash/recovery / update 回归
- [ ] 发布迁移指南

验收标准：

- [ ] 文档、示例、CLI、回归测试一致

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
