# Uya v0.9.2 发布说明

> **类型**：**v0.9.x 发行线上的补丁版本**（patch）  
> **发布日期**：2026-04-12

在 **v0.9.1** 基础上改进测试基础设施：并行测试脚本支持独立输出目录、实时结果输出，并修复 `make tests` 下的缓冲与参数问题。`make check` 下 **779** 项测试通过（2026-04-12）。

---

## 核心变更

### 测试基础设施：并行测试脚本重构

#### 1. 独立输出目录（避免同名测试冲突）

- `tests/run_programs_parallel.sh`：
  - 新增 `generate_test_id()`，基于 `.uya` 文件的相对路径生成唯一 ID，将路径分隔符替换为下划线。
  - 单文件测试的编译产物（`.c`、`.bin`、`_bridge.c`、`.compiler_output.log`、`.result`）从统一的 `$BUILD_DIR` 迁移到 `$BUILD_DIR/tests/${test_id}/`。
  - 多文件测试的编译产物迁移到 `$BUILD_DIR/multifile_tests/${test_name}/${case_name}/`。
  - `run_multifile_test` 的 `case_file` 与 `result_file` 也同步迁入独立目录，消除并行执行时的写覆盖风险。

#### 2. 实时输出改进

- `tests/run_programs_parallel.sh`：
  - 新增 `process_ready_single_results()`，在 `wait -n` 每次返回后立即检测并输出已完成的后台测试结果，实现**完成一个、输出一个**的流水线式反馈。
  - 脚本顶部增加 `stdbuf -oL` 自动重载逻辑：当 stdout 不是 TTY 时（如通过 `make`/`pipe`/`CI` 运行），强制行缓冲，避免输出被块缓冲延迟。
  - 旧 Bash（不支持 `wait -n`）回退到批量模式，每批 `wait` 结束后立即输出该批结果，优于原先的全局汇总输出。

#### 3. `make tests` 参数修复

- `Makefile`：
  - 移除 `tests:`、`tests-hosted:`、`tests-uya:` 目标中硬编码的 `--hide-pass` 参数。
  - 现在 `make tests` 与直接运行 `./tests/run_programs_parallel.sh` 行为一致，通过的测试会实时显示 `✓`，不再静默等待全部结束后才打印汇总。

---

## 文件变更

- `src/main.uya`：版本字符串更新为 **v0.9.2**
- `tests/run_programs_parallel.sh`：并行测试重构（独立目录 + 实时输出）
- `Makefile`：移除 `--hide-pass`
