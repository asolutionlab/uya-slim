# Uya v0.8.0 里程碑发布说明

> **类型**：自 v0.7.4 起的里程碑版本（minor）  
> **发布日期**：2026-03-25

本版本汇总 **v0.7.4 标签之后**约 **379** 次提交，覆盖异步运行时、标准库 HTTP、C99 多文件输出、编译器性能与工具链体验等重大进展；`make check` 下 **658** 项测试通过。

---

## 核心亮点

### 异步运行时与并发

- **@async_fn 状态机**：近似状态机大小计算、转换正确性验证、await 绑定纳入状态机结构体等。
- **调度与通道**：多 fd 并发调度、`MpscChannel<T>`、运行时 `RingQueue<T>`、`ThreadPool` worker/pending 上限提升。
- **泛型异步**：泛型异步 API 与 C99 单态/codegen 修复；`async_compute<T>` 与 future 路径整理。

### 标准库：`std.http` 与密码学

- **HTTP**：分阶段实现 TCP 基础、类型与解析、路由（Phase 4）、阻塞服务器（Phase 5）、Keep-alive / 流水线、multipart、错误路径与示例服务器。
- **JWT / SHA-256**：无 OpenSSL 的 SHA-256 与 JWT HS256；JWT `exp` 校验；Bearer 与请求头辅助。
- **压测**：`benchmarks/http_bench.uya` 与 Go 参考实现 `benchmarks/http_bench.go`（便于对照）。

### C99 后端与构建

- **默认多文件 C 输出**：镜像翻译单元、`.uyacache` 与 `--no-split-c`；vtable 外链与自举对比对齐。
- **切片形参**：C99 按值传递与调用约定一致化。
- **性能**：标识符/声明缓存、缓冲与计时、`@vector.reduce_*` 等 SIMD 路径与按需发射。

### 工具链与默认行为

- **`--nostdlib`**：默认自举构建路径支持；Makefile 与种子构建流程同步。
- **体验**：`uya build` / `run` / `test` 子命令与包装脚本；默认堆栈增大（含 entry 侧设置）；默认启用内存安全证明（`--safety-proof`）；帮助文本补全。
- **其它**：字符串/字符字面量 `\xHH`、`\uXXXX` 等转义；`-Werror` 与告警清理。

### 标准库其它

- **`IAllocator` / `Arena` / `Vec` / `HashMap`** 等与分配器接口联动；`std.json` 编码性能（如 `JsonWriter.write_bytes`、字符串 `@vector` 块）。

---

## 升级指南

从 v0.7.4 升级到 v0.8.0：

```bash
git pull
git checkout v0.8.0   # 发布打 tag 后

make clean && make check   # 或按你方 CI 等价流程
```

若依赖单文件种子：确保仓库内 **`backup/uya.c`** 与当前发行一致，或使用 `make from-c` / `make backup-seed` 按文档重建。

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 v0.7.4 | ~379 commits |
| 回归测试 | 658 通过（`make check`，2026-03-25） |
| 上一标签 | `v0.7.4` |

---

## 后续方向（概要）

- HTTP / 异步：持续完善边界场景与文档。
- 编译期优化：内联、循环展开等（参见既有优化路线图文档）。
- 平台与 libc：继续补齐宿主与交叉场景。

---

## 致谢

感谢所有为本里程碑贡献代码、测试与文档的参与者。

---

**标签**：`v0.8.0`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.8.0)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
