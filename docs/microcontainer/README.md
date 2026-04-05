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
- `payload_obj`：编译器与打包器之间的中间产物
- `payload code`：`target_arch` 指定的目标架构载荷码
- `.uapp`：最终加载器消费的镜像文件
- 当前 `.uapp` 主要由 `examples/microapp/microcontainer_hello_build.uya` 这类宿主打包器示例生成；`build --app microapp` 还没有直接接入 `.uapp` pack 后端

---

## 阅读顺序

建议先看：

1. [requirements_v1.3.md](/home/winger/uya-asm/docs/microcontainer/requirements_v1.3.md)
2. [image_validation.md](/home/winger/uya-asm/docs/microcontainer/image_validation.md)
3. [source_to_uapp_pipeline.md](/home/winger/uya-asm/docs/microcontainer/source_to_uapp_pipeline.md)
