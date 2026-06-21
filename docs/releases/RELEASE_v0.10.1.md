# Uya v0.10.1 发布草案

> **类型**：v0.10.x 发行线上的补丁版本草案
> **状态**：未发布
> **草案日期**：2026-06-20

本草案记录 core 编译器重构在发布口径上的新增边界。它不是已发布版本说明；正式发布前仍需要按仓库规则完成 `make clean && make backup-all` 或 `make release-clean`。

## Core 编译器入口

本轮重构新增 `uya-core`，作为迁移期的精简编译器入口：

- `make uya-core` 构建 `bin/uya-core`，覆盖普通语言用户需要的 `check`、`build`、`run`、`test` 路径。
- `make check-core` 是 core 门禁，覆盖 core 构建、错误诊断、多文件、package mode、`@c_import` 和 split-C smoke。
- `make install-core` 只安装 `uya-core` 和 `lib/`，不构建或安装 `bin/cmd/*`。

迁移期继续保留 full 入口：

- `make uya` 构建现有 full 兼容入口 `bin/uya`，保留 release、UPM、formatter、microapp、exec VM 和专项测试能力。
- `make check` 继续作为完整仓库门禁，覆盖 full 自举、主测试集和非 core 专项能力。
- `make release` / `make release-clean` 仍是 full 发布验证入口，不被 `make check-core` 取代。

## Seed 与发布边界

本阶段不维护独立 core seed。

- `backup/uya.c`、host/arch `backup/uya-*.c`、`backup/uya-hosted*.c` 和 `backup/uyacache/` 继续表示 full `src/main.uya` 编译器 seed 与备份。
- `bin/uya-core.c` 由 `make uya-core` 派生生成，是本地构建产物。
- `bin/uya-core-stage2` 只作为 core 自举 smoke 产物，不安装、不发布、不作为 seed 提交。
- 只有当 `uya-core` 被明确提升为默认发布入口，或需要独立冷启动 core 编译器时，才新增 `backup/uya-core.c` 及 host/arch 变体。

## 发布前验证建议

普通 core 变更应至少运行：

```bash
make check-core
```

涉及 full 入口、非 core 能力、seed、release 或安装布局的变更仍应运行：

```bash
make check
make clean && make backup-all
```

正式发布前的最终验证仍以：

```bash
make release-clean
```

为准。
