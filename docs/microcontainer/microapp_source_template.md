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
- 真正的 `source(.uya) -> payload_obj -> .uapp` 链路已经开始落地，但编译器的完整微应用后端仍在继续完善。
- 当前 `build --app microapp` 还不会直接产出 `.uapp`；现在可用的最短路径仍是 `examples/microapp/microcontainer_hello_build.uya` 这样的宿主打包器示例。
- 这份模板可以先看成“未来微应用源码入口”，而不是当前 `build` 的直接产物入口。
