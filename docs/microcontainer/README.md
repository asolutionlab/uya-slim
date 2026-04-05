# 微容器文档索引

本文档用于集中整理当前仓库中的微容器相关文档，并说明它们之间的关系。

---

## 核心文档

- [requirements_v1.3.md](/home/winger/uya-asm/docs/microcontainer/requirements_v1.3.md)
- [image_validation.md](/home/winger/uya-asm/docs/microcontainer/image_validation.md)
- [syscall_abi.md](/home/winger/uya-asm/docs/microcontainer/syscall_abi.md)
- [update_recovery.md](/home/winger/uya-asm/docs/microcontainer/update_recovery.md)
- [platform_impl.md](/home/winger/uya-asm/docs/microcontainer/platform_impl.md)
- [benchmark_plan.md](/home/winger/uya-asm/docs/microcontainer/benchmark_plan.md)
- [source_to_uapp_pipeline.md](/home/winger/uya-asm/docs/microcontainer/source_to_uapp_pipeline.md)
- [microapp_source_template.md](/home/winger/uya-asm/docs/microcontainer/microapp_source_template.md)

---

## 术语边界

- `microapp.uya`：微应用源码文件（开发入口）
- `payload_obj`：编译器与打包器之间的中间产物，当前会保留源文件路径等 provenance 信息
- `payload code`：`target_arch` 指定的目标架构载荷码
- `.uapp`：最终加载器消费的镜像文件
- 当前 `.uapp` 可以由 `build --app microapp ... -o xxx.uapp` 直接生成，也可以先产 `.pobj` 再用 `pack-image` 打包；宿主示例仍保留用于对照和调试
- 当前 microapp 路径里，`payload code` 默认由 `MICROAPP_TARGET_ARCH` 决定目标架构；`MICROAPP_TARGET_GCC` 和 `TARGET_GCC` 都可以显式覆盖具体 gcc，前者优先级更高；默认是 `x86_64-linux-gnu-gcc`

默认目标三元组映射：

- `rv32` -> `riscv32-unknown-elf`
- `x86_64` -> `x86_64-linux-gnu`
- `aarch64` -> `aarch64-linux-gnu`
- `xtensa` -> `xtensa-unknown-elf`

---

## 阅读顺序

建议先看：

1. [requirements_v1.3.md](/home/winger/uya-asm/docs/microcontainer/requirements_v1.3.md)
2. [image_validation.md](/home/winger/uya-asm/docs/microcontainer/image_validation.md)
3. [source_to_uapp_pipeline.md](/home/winger/uya-asm/docs/microcontainer/source_to_uapp_pipeline.md)
