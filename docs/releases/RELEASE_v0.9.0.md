# Uya v0.9.0 发布说明

> **类型**：**v0.9.x 发行线上的主版本**  
> **发布日期**：2026-04-06

本版本把 **microapp / 微容器** 这条链路从“能试”推进到“可发布、可验证、可持续收缩”的状态：

- `build --app microapp` 现在可以直接产出 `.pobj` 或 `.uapp`
- `pack-image` 已经接入标准 `PayloadObj` 打包路径
- 示例 loader 已经通用化，可以直接从命令行读取任意 `.uapp`
- 默认 `microapp` 目标工具链改成了更偏体积优化的链路，样例 `.uapp` 体积显著下降

`make release` / `make b-hosted` / `microapp` 回归脚本均已通过。

---

## 核心变更

### 1. 微程序产物链路打通

- `build --app microapp ... -o xxx.pobj` 现在会生成二进制 payload 对象
- `build --app microapp ... -o xxx.uapp` 现在可以直出镜像
- `pack-image xxx.pobj -o xxx.uapp` 继续保留，作为显式打包入口

### 2. 通用 loader

- `examples/microapp/microcontainer_hello_load.uya` 现已改成通用 loader
- 运行时可通过命令行参数指定 `.uapp` 路径
- 未传参时仍回退到示例镜像，便于快速演示

### 3. 体积优化

- `microapp` 默认目标 gcc 旗标改为偏体积优化的预设
- 默认打开 `-ffunction-sections -fdata-sections -flto`
- 默认链接打开 `-Wl,--gc-sections -flto`
- 默认示例 `.uapp` 体积从约 `37 KB` 压到约 `25 KB`

### 4. 文档与验证

- 微容器相关文档已同步更新
- 增加了 loader 通用化回归测试
- `make release` 流程下的发布前检查保持可用

---

## 升级指南

从 `v0.8.2` 升级到 `v0.9.0`：

```bash
git pull
git checkout v0.9.0

make release-clean   # 或 make release / make b-hosted
```

如果你需要验证 microapp 链路：

```bash
./tests/verify_microapp_pobj_manifest.sh
./tests/verify_microapp_pack_image.sh
./tests/verify_microapp_build_uapp.sh
./tests/verify_microapp_loader_generic.sh
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对上一发行线 | 见 `git log v0.8.2..HEAD` |
| 回归测试 | `make release`、`make b-hosted`、microapp 回归脚本 |
| 上一标签 | `v0.8.2` |

---

## 致谢

感谢所有参与代码、测试与文档整理的人。

---

**标签**：`v0.9.0`
