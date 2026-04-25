# Uya fmt Phase 4 TodoList

> 基于 `docs/fmt_development_plan.md` 的方案 B，Phase 4 聚焦 `uya fmt` 命令、输出模式与工程集成。

**Goal**: 提供接近 `gofmt` 工作流的命令行体验，并能接入项目开发流程。

---

## Status

- [x] Not started
- [ ] Done

---

## Phase 4 Goals

- [ ] 提供 `uya fmt` 命令
- [ ] 支持 stdout / write-back / list / diff
- [ ] 支持 simplify 与 rewrite 的 CLI 选项
- [ ] 支持文件、目录、stdin 输入
- [ ] 集成到 Makefile / CI 工作流

---

## Main Pipeline

- [ ] 打通 `cli args -> collect inputs -> read source -> format_with_options -> compare original/formatted -> stdout | write back | list | diff`

---

## File Tasks

### `tools/fmt.uya`

- [x] 实现最小参数解析
- [x] 实现单文件输入
- [x] 实现 stdout 输出路径
- [x] 实现 `-w` 写回路径
- [x] 实现错误码返回
- [ ] 实现目录遍历
- [ ] 实现 stdin 输入
- [ ] 实现 `-d` 显示差异
- [ ] 实现 `-l` 列出未格式化文件
- [ ] 实现 `-r "rule"` 应用 rewrite 规则
- [ ] 实现 `-s` 应用 simplify
- [ ] 验证单文件格式化运行时可用
- [ ] 验证多文件输入可用
- [ ] 验证无参数时支持 stdin

### `lib/std/fmt/fmt.uya`

- [x] 暴露适合 CLI 的统一入口
- [x] 新增 `format_ptr_len(arena, ptr, len)`，绕过工具层 slice 构造问题
- [x] 保持 `format(source)` 可用
- [x] 保持 `format_with_options(source, options)` 可用
- [x] 保持 `is_formatted(source)` 可用
- [ ] 返回格式化结果与是否变更的信息

### `Makefile`

- [ ] 增加 `make fmt`
- [ ] 增加 `make check-fmt`
- [ ] 验证可批量格式化仓库源码
- [ ] 验证可在 CI 中检查格式化状态

---

## Runtime Blocker

### 当前阻塞结论

- [x] `tools/fmt.uya` 已可编译链接
- [x] Phase 4 的主要阻塞已从 CLI 逻辑收敛为底层 runtime 问题
- [x] 当前已确认：`arena_alloc(...)` 返回的内存在运行时写入即可能触发 segfault

### 最小复现文件

- [x] `tools/fmt_smoke.uya`
- [x] `tools/fmt_tokenize_smoke.uya`
- [x] `tools/arena_struct_array_smoke.uya`
- [x] `tools/arena_byte_smoke.uya`
- [x] `tools/arena_scalar_smoke.uya`
- [x] `tools/arena_struct_single_smoke.uya`
- [x] `tools/arena_struct_array_index_smoke.uya`

### 当前定位结果

- [x] CLI 编译问题已解决（slice 构造通过 `format_ptr_len` 绕过）
- [x] fmt AST 类型名冲突已解决（`File` -> `FmtFile`）
- [x] 运行时 segfault 可在不依赖 fmt 的 arena smoke 中复现
- [x] 当前阻塞不再属于 fmt 业务逻辑，而属于 arena/runtime 层

---

## Tests

### `tests/test_fmt_api.uya`
- [ ] 验证 CLI 依赖的 API 行为稳定
- [ ] 验证选项组合不冲突

### CLI 集成测试
- [ ] 验证 `uya fmt file.uya`
- [ ] 验证 `uya fmt -w file.uya`
- [ ] 验证 `uya fmt -l file.uya`
- [ ] 验证 `uya fmt -d file.uya`
- [ ] 验证 `uya fmt -s file.uya`
- [ ] 验证 `uya fmt -r "foo.bar -> bar" file.uya`
- [ ] 验证 `cat file.uya | uya fmt`

### 工程级验证
- [ ] 验证 `make fmt` 可执行
- [ ] 验证 `make check-fmt` 可报告未格式化文件

---

## Definition of Done

- [ ] `uya fmt` 可处理单文件、目录、stdin
- [ ] `-w/-d/-l/-r/-s` 全部可用
- [ ] CLI 返回码符合预期
- [ ] `make fmt` / `make check-fmt` 可用
- [ ] CLI 行为与库层 API 保持一致

---

## Notes

- 当前 Phase 4 为 **进行中**，尚未完成。
- `tools/fmt.uya` 的最小 CLI 原型已经能成功编译链接。
- 当前运行时阻塞已经被压缩到 arena/runtime 层，而不是 fmt/CLI 逻辑本身。
- 在修复 `std.mem.arena` 或相关后端问题前，Phase 4 无法完成运行级验收。
