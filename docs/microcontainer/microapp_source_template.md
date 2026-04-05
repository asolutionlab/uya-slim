# 微应用源码模板

本文给出一份当前阶段可参考的微应用源码形状。

## 目的

这个模板不是最终编译后端产物，而是帮助读者理解：

- 微应用源码应该长什么样
- microapp 模式下允许哪些入口风格
- 后续如何从源码走到 `payload_obj` 和 `.uapp`

## 示例

```uya
use std.runtime.entry;

export fn main() i32 {
    return 0;
}
```

## 说明

- 这份模板现在主要用于说明源码层的意图。
- 真正的 `source(.uya) -> payload_obj -> .uapp` 链路已经开始落地，并且 `build --app microapp -o xxx.uapp` 现在可以直接走通。
- 现阶段 `microapp` 的 `code` 来源是目标 gcc 的 `.text` 输出，目标架构由 `MICROAPP_TARGET_ARCH` 决定，默认是 `x86_64`；`MICROAPP_TARGET_GCC` 优先于 `TARGET_GCC`，都可显式指定具体工具链。
- 默认目标三元组映射和编译器选择见 `README.md`，目前按 `rv32 / x86_64 / aarch64 / xtensa` 预置。
- 当前仍保留 `payload_obj` 作为中间边界，便于单独测试和调试；它现在还会携带源文件路径等 provenance 信息，宿主打包器示例也仍然可用。
- 这份模板可以先看成“未来微应用源码入口”，而不是当前 `build` 的直接产物入口。
