# Uya v0.9.4 发布说明

> **类型**：**v0.9.x 发行线上的功能版本**  
> **发布日期**：2026-04-22

## 概要

v0.9.4 继续围绕 “**microapp / 微容器链路可发布、可验证、可移植**” 这条主线推进，同时把近几轮已经落地的语言与标准库能力真正收口到 release 质量：

- microapp 侧：mapped payload、reloc / bss / trap / fault / recovery / update、profile 默认解析、镜像检查 CLI 与样例源码运行链路全部纳入统一验证。
- 编译器侧：新增 `@embed` / `@embed_dir`，完成 `@c_import` 构建集成，修复 macro 展开切片表达式 codegen 崩溃，并继续加固 release / zig / gcc / hosted cross-build 路径。
- 标准库侧：新增 `std.sql`、`std.mqtt.async`，并为 `std.crypto` 增补 BLAKE2b / BLAKE2s / MD5 / CRC32。

这一版适合作为 **v0.9.0 里程碑线** 上的下一次补丁发行：功能面继续扩展，但重点已经从“单点可用”转到“整链路能稳定跑完并被 release 流程验证”。

---

## 核心变更

### 1. microapp / 微容器运行时链路继续收口

- `build --app microapp`、`pack-image`、`inspect-image`、`verify-image` 这条产物链路进一步稳定化。
- loader 侧补齐并验证了：
  - mapped payload 执行
  - relocation
  - BSS 初始化
  - exit-code / fault / trap 结果分类
  - host API 诊断
  - recovery / update 路径
- profile 解析改成更偏 “profile-first” 的默认行为：
  - 支持 CLI 覆盖
  - 支持按目标平台自动推导默认 profile
  - 样例矩阵和 unwired profile 路径都已纳入回归
- 示例源码链路已补齐：
  - `examples/microapp/microcontainer_hello_source.uya`
  - `examples/microapp/microcontainer_alloc_yield_source.uya`
  - `examples/microapp/microcontainer_time_source.uya`
  - `examples/microapp/microcontainer_bss_source.uya`
  - `examples/microapp/microcontainer_reloc_source.uya`
  - `examples/microapp/microcontainer_reloc_data_source.uya`

### 2. `@embed` / `@embed_dir` 与 `@c_import` 构建链路完成接入

- 新增 `@embed(...)` / `@embed_dir(...)`：
  - 支持将单文件或目录资源嵌入编译产物
  - 覆盖 empty dir、too large、symlink rejected、multifile reuse、split-C reuse 等边界路径
- `@c_import` 从语法支持推进到**完整构建集成**：
  - 单文件 C 输出会生成 sidecar
  - `tests/link_cimports_posix.sh` 负责把 sidecar 中记录的 C 源 / `cflags` / `ldflags` 串起来
  - split-C 路径直接把导入的 C object 接进生成的 Makefile

### 3. 编译器与 release / hosted 工具链加固

- 修复并加固：
  - macro-expanded slice expr codegen SIGSEGV
  - codegen regular file buffering
  - async / split-build 的回归路径
  - zig / gcc 下的 release 构建
- CLI 补齐 `-v` / `--version`，版本查询现在与帮助和文档保持一致。
- `run` / `test` 在需要时强制回到单文件 C 路径，减少临时 build 工作流中的不稳定因素。
- hosted 侧补齐 host-specific C seeds，并支持通过 `zig cc` 辅助刷新 macOS hosted 交叉种子。
- `make release` / `make release-clean` / `make backup-all-seed` 的工作流继续收口到“一键最终验证 + tracked seeds 同步”的模式。

### 4. 标准库扩展

#### `std.sql`

- 新增 `lib/std/sql/db.uya`
- 新增 `lib/std/sql/driver.uya`
- 新增 `lib/std/sql/sql.uya`
- 新增 `lib/std/sql/types.uya`
- 配套新增 `docs/std_sql.md` 与回归 `tests/test_std_sql.uya`

#### `std.mqtt.async`

- 新增 `lib/std/mqtt/async.uya`
- 支持 CONNECT / SUBSCRIBE / QoS0 PUBLISH 等基础 async 语义
- 配套新增 `docs/std_mqtt_async.md` 与回归 `tests/test_std_mqtt_async.uya`

#### `std.crypto`

- 新增 `lib/std/crypto/blake2b.uya`
- 新增 `lib/std/crypto/blake2s.uya`
- 新增 `lib/std/crypto/md5.uya`
- 新增 `lib/std/crypto/crc32.uya`
- 配套新增 / 扩展 crypto 回归

---

## 升级指南

从 `v0.9.3` 升级到 `v0.9.4`：

```bash
git pull
git checkout v0.9.4

make release-clean
```

如果你主要关注新增能力，可以额外验证：

```bash
./tests/verify_microapp_suite.sh
./tests/verify_c_import_split_sidecar.sh
./tests/verify_embed_multifile_reuse.sh
./tests/verify_embed_dir_multifile_reuse.sh
bin/uya --version
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 `v0.9.3` | 见 `git log v0.9.3..HEAD` |
| 单文件 / 多文件回归 | `./tests/run_programs_parallel.sh --uya --c99` **828** 项全部通过 |
| 自举验证 | `make b` 通过，主编译器与自举编译器生成的可执行文件字节一致 |
| 发布验证 | `make release-clean` 通过 |
| 上一标签 | `v0.9.3` |

---

## 致谢

感谢所有为本版本贡献代码、测试、样例与文档整理的参与者。

---

**标签**：`v0.9.4`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.9.4)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
