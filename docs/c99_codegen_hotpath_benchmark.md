# C99 热路径 Benchmark 记录

**更新日期**：2026-03-23（含 64KiB FILE 缓冲与子计时字段修订）

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
| 仓库 commit | `48c66b291469cb16b676213880f679b87e5bc2f5`（示例；以 `git rev-parse HEAD` 为准） |
| 内核 / 架构 | `Linux ... 6.12.65-amd64 ... x86_64 GNU/Linux`（主机名略） |
| 默认构建 | `CFLAGS ?= -std=c99 -O0 -g -fno-builtin -Werror`（见根目录 `Makefile`） |

## 本轮实现（与「生成耗时」相关）

- **SIMD**：`emit_simd_x86_sse_runtime_helpers` 中取消 `simd_vector_struct_reg_count==0 → simd_emit_all=1` 全开；对「仅有 mask、且各 lane 族均为 0」场景由 `c99_simd_mask_only_ensure_lane_flags` 将 i32/u32/f32 族至少标为 4 lane，使 `c99_simd_need_emit_*` 按需发射。
- **可选子计时**：设置环境变量 `UYA_PROFILE_CODEGEN` 为非空时，在 **stderr** 打印一行：  
  `[UYA_PROFILE_CODEGEN] simd_ms=... prelude_ms=... body_ms=... total_ms=...`（`clock()`，与主程序「生成耗时」同语义）。  
  - `prelude_ms`：从进入 `c99_codegen_generate` 到**即将生成函数前向声明**（第七步前）的累计时间；若存在 SIMD 辅助块，其时间**含在 prelude 内**。  
  - `body_ms` = `total_ms - prelude_ms`（约等于前向声明、函数体、测试与尾部字符串常量等）。
- **自举编译器（`src/` → `uya.c`）**：编译器实现**不使用** `@vector` / SIMD 结构体（源码中无相关类型），因此自举时 **`simd_struct_count` 为 0**，**`simd_ms=0` 是预期**，并非 SIMD 优化未生效。`make bench-compile-stats` 的 codegen 瓶颈在 **`body_ms`**（函数体等生成），与 SIMD 辅助块无关；SIMD 按需发射类优化**主要作用于**含 SIMD 的用户程序与测试，**不**指望拉高自举 bench 的 codegen 数字。
- **libc stdio**：`FILE` 内置缓冲由 **4KiB 扩至 64KiB**，减少大块 C 写出时的 `write` 次数；`fflush` 实际调用 `flush_buffer`；`fclose` 在关闭 fd 前刷新缓冲。**未**合并 `fopen` 槽位重置（在自举对比中曾导致生成 C 损坏，已回退）。**未**在 `main` 中调用 `setvbuf`、**未**为 `FILE` 增加独立 1MiB 用户缓冲（曾触发自举不稳定）。

## 对比基线（历史）

本轮热路径收束前的基线样本：

| 阶段 | 基线（ms） |
|------|-----------:|
| parse | 927 |
| check | 2589 |
| codegen | 13766 |
| total | 17476 |

## 当前结果（默认 `-O0` 构建的 `bin/uya`）

**测试硬件**（与下表同次测量，2026-03-23）：Intel Core **i7-14700**（Raptor Lake，1 插槽，**20C / 28T**，x86_64）；系统内存约 **32 GiB**（`free` 报告总计 31Gi）；单 NUMA。未记录固定电源策略与后台负载，**数值会随睿频、温度与其它进程占用波动**。

三次平均（`make bench-compile-stats ARGS="--runs 3"`，2026-03-23，**64KiB FILE 缓冲**、`bin/uya` 默认 `-O0`）：

| 阶段 | 当前平均（ms） |
|------|---------------:|
| parse | 525 |
| check | 646 |
| codegen | 3359 |
| total | 4682 |

**说明**：`codegen` 列对应 stderr「生成耗时」，为 `clock()` 计量的 CPU 时间量级，不是纯磁盘 I/O wall time。

## 可选：`-O2` 编译 `bin/uya`（工具链优化，非算法改动）

仅用于对比「二进制优化」对数字的影响，**不**替代 codegen 算法优化：

```bash
CFLAGS='-std=c99 -O2 -g -fno-builtin -Werror' make from-c
make bench-compile-stats ARGS="--runs 3"
```

同机同脚本下（历史样本）：codegen 三次平均约 **2919 ms**；在 **64KiB 缓冲** 与 **`-O2` 重链 `bin/uya`** 组合下，样本约 **3014 ms**（仍远高于 1s）。

## 结论与 KPI

- 默认 `-O0` 下 **codegen ≈ 3.3～3.5s**（视机器与负载），**未达到**「同一基准下 codegen &lt; 1000ms」的激进 KPI。
- **bench 自举路径**上 SIMD 块常为 0ms，主要耗时在 **`body_ms`**（函数体等）；要进一步逼近 1s，需**算法级**削减函数体生成/类型查询，或 **`-O2`/`-O3` 二进制优化**单独记账； SIMD 按需发射对**带 SIMD 的程序**更有意义。
- `UYA_PROFILE_CODEGEN` 现可区分 **prelude / body** 与 **simd** 子段，便于下一刀落点。
