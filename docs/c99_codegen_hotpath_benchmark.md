# C99 热路径 Benchmark 记录

**更新日期**：2026-03-23

## 复现入口

- `make bench-compile-stats`
- `make bench-compile-stats ARGS="--runs 3"`

脚本位置：`scripts/bench_compile_stats.sh`

默认基准命令：

```bash
cd src && ./compile.sh --c99 -e -v --nostdlib
```

统计来源为编译器 stderr 中的 `=== 编译统计 ===` 段落，抓取以下字段：

- `文件数`
- `解析耗时`
- `合并耗时`
- `检查耗时`
- `优化耗时`
- `生成耗时`
- `总耗时`

## 复现环境（本轮）

| 项 | 值 |
|----|-----|
| 仓库 commit | `6d5f8198e8bb61e0e2a75df35b168add41ef38db` |
| 内核 / 架构 | `Linux ... 6.12.65-amd64 ... x86_64 GNU/Linux`（主机名略） |
| 默认构建 | `CFLAGS ?= -std=c99 -O0 -g -fno-builtin -Werror`（见根目录 `Makefile`） |

## 本轮实现（与「生成耗时」相关）

- **SIMD**：`emit_simd_x86_sse_runtime_helpers` 中取消 `simd_vector_struct_reg_count==0 → simd_emit_all=1` 全开；对「仅有 mask、且各 lane 族均为 0」场景由 `c99_simd_mask_only_ensure_lane_flags` 将 i32/u32/f32 族至少标为 4 lane，使 `c99_simd_need_emit_*` 按需发射。
- **可选子计时**：设置环境变量 `UYA_PROFILE_CODEGEN` 为非空时，在 **stderr** 打印一行：`[UYA_PROFILE_CODEGEN] simd_ms=... rest_ms=... total_ms=...`（`clock()`，与主程序「生成耗时」同语义）。
- **libc stdio**：`fflush` 实际调用 `flush_buffer`；`fclose` 在关闭 fd 前刷新缓冲。**未**合并 `fopen` 槽位重置（在自举对比中曾导致生成 C 损坏，已回退）。**未**在 `main` 中调用 `setvbuf`、**未**为 `FILE` 增加 1MiB 用户缓冲：在自举验证中，`main` 侧 `setvbuf` 或 `fopen` 槽位重置曾与损坏的 `uya.c` 同时出现；1MiB `ext_buf` 路径亦未再启用，待后续单独隔离原因后再做。

## 对比基线（历史）

本轮热路径收束前的基线样本：

| 阶段 | 基线（ms） |
|------|-----------:|
| parse | 927 |
| check | 2589 |
| codegen | 13766 |
| total | 17476 |

## 当前结果（默认 `-O0` 构建的 `bin/uya`）

三次平均（`make bench-compile-stats ARGS="--runs 3"`，2026-03-23）：

| 阶段 | 当前平均（ms） |
|------|---------------:|
| parse | 542 |
| check | 695 |
| codegen | 3477 |
| total | 4872 |

**说明**：`codegen` 列对应 stderr「生成耗时」，为 `clock()` 计量的 CPU 时间量级，不是纯磁盘 I/O wall time。

## 可选：`-O2` 编译 `bin/uya`（工具链优化，非算法改动）

仅用于对比「二进制优化」对数字的影响，**不**替代 codegen 算法优化：

```bash
CFLAGS='-std=c99 -O2 -g -fno-builtin -Werror' make from-c
make bench-compile-stats ARGS="--runs 3"
```

同机同脚本下样本：codegen 三次平均约 **2919 ms**（总耗时约 **4000 ms**），仍高于 1s 目标。

## 结论与 KPI

- 默认 `-O0` 下 **codegen ≈ 3.5s**，**未达到**「同一基准下 codegen &lt; 1000ms」的激进 KPI。
- 主要收益来自 **SIMD 辅助 C 按需发射**；`UYA_PROFILE_CODEGEN` 便于区分 SIMD 块与其余 codegen 时间。
- 进一步压缩需第二梯队（如类型/表达式热路径、arena 小分配等），或接受 `-O2` 等工具链优化并单独记账。
