# 微容器文档索引

本文档用于集中整理当前仓库中的微容器相关文档，并说明它们之间的关系。

---

## 核心文档

- [requirements_v1.3.md](../../docs/microcontainer/requirements_v1.3.md)
- [runtime-architecture.md](../../docs/microcontainer/runtime-architecture.md)
- [capability_api_schema.md](../../docs/microcontainer/capability_api_schema.md)
- [backend_adapter_contract.md](../../docs/microcontainer/backend_adapter_contract.md)
- [native_mock_semantics.md](../../docs/microcontainer/native_mock_semantics.md)
- [image_validation.md](../../docs/microcontainer/image_validation.md)
- [syscall_abi.md](../../docs/microcontainer/syscall_abi.md)
- [update_recovery.md](../../docs/microcontainer/update_recovery.md)
- [platform_impl.md](../../docs/microcontainer/platform_impl.md)
- [benchmark_plan.md](../../docs/microcontainer/benchmark_plan.md)
- [source_to_uapp_pipeline.md](../../docs/microcontainer/source_to_uapp_pipeline.md)
- [microapp_source_template.md](../../docs/microcontainer/microapp_source_template.md)
- [microapp_profiles.md](../../docs/microcontainer/microapp_profiles.md)
- [portable_native_design.md](../../docs/microcontainer/portable_native_design.md)
- [portable_native_todo.md](../../docs/microcontainer/portable_native_todo.md)

---

## 术语边界

- `microapp.uya`：微应用源码文件（开发入口）
- `payload_obj`：编译器与打包器之间的中间产物，当前会保留源文件路径等 provenance 信息
- `payload code`：`target_arch` 指定的目标架构载荷码
- `.uapp`：最终加载器消费的镜像文件
- 当前 `.uapp` 可以由 `build --app microapp ... -o xxx.uapp` 直接生成，也可以先产 `.pobj` 再用 `pack-image` 打包；宿主示例仍保留用于对照和调试
- 示例 loader 现在可通过命令行参数接收任意 `.uapp` 路径，默认仍回退到示例镜像
- 热更新槽容量与示例 loader 读取缓冲已经拆成两个独立上限，便于后续分别调优
- `examples/microapp/microcontainer_hello_source.uya` 是当前推荐的可移植 microapp 源码样例
- `examples/microapp/microcontainer_hello_build.uya` / `examples/microapp/microcontainer_hello_load.uya` 是宿主侧构建/加载工具，不属于 portable source 子集
- 用户 portable microapp 源码现在会在编译期拒绝直接 `use/call libc.*` 与 `std.time`，并提示改用 `std.microapp.*`
- 当前 microapp 路径里，目标选择已经切到 `profile-first`
- 默认 profile 推导优先级是：`--microapp-profile` > `MICROAPP_TARGET_PROFILE` > `MICROAPP_TARGET_ARCH(+TARGET_OS)` > `TARGET_OS/TARGET_ARCH` > `HOST_OS/HOST_ARCH` > `linux_x86_64_hardvm`
- `MICROAPP_TARGET_GCC` 和 `TARGET_GCC` 都可以显式覆盖具体 gcc，前者优先级更高；若未覆盖，则走当前 profile 自带的默认 gcc
- `MICROAPP_TARGET_CFLAGS` / `MICROAPP_TARGET_LDFLAGS` 现在也是按 profile 给默认值：
  - `call_gate` profile 默认 `-fpie/-pie`
  - `trap` profile 默认 `-fno-pie/-no-pie`
- 当前 `microapp` 目标选择已逐步从 `arch-first` 迁移到 `profile-first`：
  - 可用 `--microapp-profile <name>` 显式指定
  - 也可用 `MICROAPP_TARGET_PROFILE`
  - CLI 优先级高于环境变量
  - 详细说明见 [microapp_profiles.md](../../docs/microcontainer/microapp_profiles.md)

默认 profile 三元组映射：

- `linux_x86_64_hardvm` -> `x86_64-linux-gnu`
- `linux_aarch64_hardvm` -> `aarch64-linux-gnu`
- `macos_arm64_hardvm` -> `arm64-apple-darwin`
- `rv32_baremetal_softvm` -> `riscv32-unknown-elf`
- `xtensa_baremetal_softvm` -> `xtensa-unknown-elf`

---

## 阅读顺序

建议先看：

1. [requirements_v1.3.md](../../docs/microcontainer/requirements_v1.3.md)
2. [runtime-architecture.md](../../docs/microcontainer/runtime-architecture.md)
3. [capability_api_schema.md](../../docs/microcontainer/capability_api_schema.md)
4. [backend_adapter_contract.md](../../docs/microcontainer/backend_adapter_contract.md)
5. [native_mock_semantics.md](../../docs/microcontainer/native_mock_semantics.md)
6. [image_validation.md](../../docs/microcontainer/image_validation.md)
7. [source_to_uapp_pipeline.md](../../docs/microcontainer/source_to_uapp_pipeline.md)
8. [microapp_profiles.md](../../docs/microcontainer/microapp_profiles.md)
9. [portable_native_design.md](../../docs/microcontainer/portable_native_design.md)
10. [portable_native_todo.md](../../docs/microcontainer/portable_native_todo.md)
