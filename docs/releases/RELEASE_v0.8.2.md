# Uya v0.8.2 发布说明

> **类型**：**v0.8.x 发行线上的补丁版本**（patch）  
> **发布日期**：2026-03-31

在 **v0.8.1** 基础上调整**主线程堆栈上限**策略：`std.runtime.entry` 的 C `main` **不再**隐式将 `RLIMIT_STACK` 设为固定 16MB；改为导出 **`set_process_stack_limit_bytes`**，由应用在 `main_main` 开头按需调用。自举编译器在解析 `--stack-size` 后于 **`main_main` 内**调用该函数，与 CLI 默认（65536 KB）一致。`make check` 下 **698** 项测试通过（2026-03-31）。

---

## 核心变更

### 运行时入口（`std.runtime.entry`）

- **移除**：C `main` 内对堆栈的强制 `setrlimit` / syscall。
- **新增**：`export fn set_process_stack_limit_bytes(limit_bytes: u64) void`（x86_64 Linux 走 `@syscall`，否则 `setrlimit`；失败忽略）。

### 编译器（`src/main.uya`）

- **`use std.runtime.entry.set_process_stack_limit_bytes`**，在 `stack_size > 0` 时调用，与 **`--stack-size`**（KB）对齐。

### 应用侧

- 需要更大主线程栈时：`use std.runtime.entry.set_process_stack_limit_bytes;`，在 `export fn main` 体开头调用，例如 `set_process_stack_limit_bytes(16 * 1024 * 1024)`。

---

## 升级指南

从 v0.8.1 升级到 v0.8.2：

```bash
git pull
git checkout v0.8.2   # 发布打 tag 后

make clean && make check   # 或 make backup-all 完整验证与种子
```

若依赖单文件种子：提交中包含 **`backup/uya.c`** 时与仓库保持一致，或使用 `make from-c` / `make backup-seed` 按文档重建。

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 v0.8.1 | 见 `git log v0.8.1..HEAD` |
| 回归测试 | `make check`（发布流程中 `make backup-all` 内含完整验证） |
| 上一标签 | `v0.8.1` |

---

## 致谢

感谢所有为本版本贡献代码、测试与文档的参与者。

---

**标签**：`v0.8.2`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.8.2)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
