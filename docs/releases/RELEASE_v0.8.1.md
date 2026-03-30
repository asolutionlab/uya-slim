# Uya v0.8.1 发布说明

> **类型**：**v0.8.0 发行线上的补丁版本**（patch；与里程碑 v0.8.0 同一大版本，汇总其后累积改进）  
> **发布日期**：2026-03-30

v0.8.0 聚焦异步、`std.http`、多文件 C99 等里程碑能力；**v0.8.1** 在其后合并 **TFLM 标准库与多后端**、**epoll / 非阻塞 HTTP** 路径、压测与编译器稳定性修复等，不改变「v0.8 发行线」的定位。`make check` 下 **697** 项测试通过。

---

## 核心亮点

### TFLM（纯 Uya 标准库）

- **TFLM 纯 Uya 实现**：在标准库侧提供 TFLM 相关接口与类型。
- **多后端与 CMSIS-NN**：完成多后端支持，新增 **ARM CMSIS-NN** 后端实现。

### `std.http` 与 epoll

- **非阻塞与 epoll 协同**：`ReadWouldBlock` 解析路径、非阻塞 listen/accept 排空、双连接测试；非阻塞写、`EPOLLOUT` 与 `SO_SNDBUF`；`read`/`write`/`accept` 遇 **EINTR** 重试。
- **路由与槽位**：epoll 客户端 fd 注册、GET 路由集成测试；槽位缓冲与流水线双 GET、`slot_for_fd` 等阶段性能力。
- **语义与测例修复**：`!T` 上 `match` 绑定修正；epoll 测例使用 `epoll_wait(-1)`、栈与并行限流等稳定性调整。

### 压测与基准

- **`http_bench_async.uya`**：基于 epoll 的简化 HTTP 服务压测；**BufferStream**、Keep-Alive / **Connection** 头、主进程参与 accept、**SO_REUSEPORT**、多进程（`SO_REUSEADDR` + `fork`）等迭代修复。
- **`run_bench.sh`**：改用 `http_bench_async`，改进子进程清理与编译输出。

### 语言与编译器

- **全局数组**：支持用**字符串字面量**初始化全局 `byte` 数组。
- **字符串与切片**：字符串字面量赋 `byte` 数组/切片；**const 切片**赋值检查。
- **C99 / 异步**：`!Future` 无 `await` 时的包装器前言与 async 程序测例修复。
- **自举对比**：多文件自举对比在 **`-g`** 下对比较归一化。
- **原子**：C99 对结构体**原子成员读**的修复。

### 运行时与 libc

- **`--nostdlib`**：**CompilerArena** 与标准库 **Arena** 分离，修复静态链接相关行为。
- **pthread**：`clone` 汇编操作数顺序修复；`test_pthread` **SIGSEGV** 与 **Makefile** 链接问题修复。
- **backup 种子类型**：精简不必要的结构体与错误联合体定义；增加 **LinuxEpoll** 相关结构与接口（与 epoll 路径配套）。

### 工具链与工程

- **CI**：新增 **Ubuntu**、**macOS** 工作流（C/C++ 项目类）。
- **`uya test`**：退出码等行为修正。
- **JWT 测试**：补全 `get_bearer_token` 空 token 的 **InvalidToken** 路径。

---

## 升级指南

从 v0.8.0 升级到 v0.8.1：

```bash
git pull
git checkout v0.8.1   # 发布打 tag 后

make clean && make check   # 或按你方 CI 等价流程
```

若依赖单文件种子：确保仓库内 **`backup/uya.c`** 与当前发行一致，或使用 `make from-c` / `make backup-seed` 按文档重建。

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 v0.8.0 | 见 `git log v0.8.0..HEAD` |
| 回归测试 | 697 通过（`make check`，2026-03-30） |
| 上一标签 | `v0.8.0` |

---

## 后续方向（概要）

- HTTP / epoll：继续完善边界场景、文档与生产向配置。
- TFLM：更多后端与示例、与宿主构建流程的文档化。
- 下一**次版本**（如 v0.9.0）可在发行说明中单独定义为新的里程碑，避免与 v0.8.x 补丁线混淆。

---

## 致谢

感谢所有为本版本贡献代码、测试与文档的参与者。

---

**标签**：`v0.8.1`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.8.1)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
