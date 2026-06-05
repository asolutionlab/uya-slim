# Uya v0.10.0 发布说明

> **类型**：**v0.10.x 发行线上的次版本**（minor）
> **发布日期**：2026-06-04

在 **v0.9.9** 将 WebSocket / HTTP/2 / HPACK 与 exec VM 回归收入口径之后，**v0.10.0** 把重点放在“开发工具链可用性 + C99 主线稳定性”上：`fmt` CLI/API 完成发布级收口，if expression 进入 parser / checker / C99 codegen 主线，同时修复多条影响自举、split-C 与大型项目 codegen 的回归。

---

## 核心变更

### 1. `fmt` CLI / API 发布级收口

- `lib/std/fmt/fmt.uya`
- `lib/std/fmt/tokenizer.uya`
- `lib/std/fmt/parser.uya`
- `lib/std/fmt/printer.uya`
- `lib/std/fmt/comments.uya`
- `lib/std/fmt/import_sort.uya`
- `lib/std/fmt/simplify.uya`
- `lib/std/fmt/rewrite.uya`
- `tools/fmt.uya`

本版本完成 `fmt` phase4 CLI 集成，并继续稳定库 API：

- `uya fmt <file>` / `tools/fmt.uya` 的命令行行为与帮助输出保持一致；
- 保留行注释、块注释、doc comment 与语句尾注释的附着关系；
- import sort、simplify、rewrite 与 printer 的组合路径具备幂等回归；
- 删除阶段性 `docs/todo_fmt.md`，将状态同步到 fmt phase 文档与开发计划。

新增或扩展验证：

- `tests/test_fmt_api.uya`
- `tests/test_fmt_api_phase3.uya`
- `tests/test_fmt_api_rewrite.uya`
- `tests/test_fmt_api_simplify.uya`
- `tests/test_fmt_comments.uya`
- `tests/test_fmt_doc_comment_attach.uya`
- `tests/test_fmt_idempotent.uya`
- `tests/test_fmt_import_sort.uya`
- `tests/test_fmt_stmt_comment_attach.uya`
- `tests/verify_fmt_cli.sh`

### 2. if expression 与 C99 codegen 路径增强

- `src/parser/primary.uya`
- `src/checker/check_expr.uya`
- `src/checker/type_from_ast.uya`
- `src/codegen/c99/expr.uya`
- `src/codegen/c99/stmt.uya`
- `src/codegen/c99/function.uya`
- `src/codegen/c99/main.uya`

本版本新增 if expression 的解析、类型检查与 C99 发射路径：

- `if cond { expr } else { expr }` 可作为表达式参与类型推断；
- 分支类型不一致时给出 checker 错误；
- C99 后端为表达式上下文生成稳定临时值与控制流；
- 同期补齐 bare `catch` statement、if block bare catch 与 extern body bare catch 的回归覆盖。

新增或扩展验证：

- `tests/test_if_expression.uya`
- `tests/error_if_expression_branch_type_mismatch.uya`
- `tests/test_catch_bare_statement.uya`
- `tests/test_if_block_bare_catch.uya`
- `tests/test_extern_body_bare_catch.uya`
- `tests/verify_function_reachability_codegen.sh`

### 3. C99 后端与 split-C 发布稳定性

- `src/codegen/c99/*.uya`
- `src/compile.sh`
- `Makefile`
- `backup/*.c`

本版本继续收口大型项目与 split-C 生成路径中的回归：

- 修复 monomorphized method、typed route generic method 与 struct array field member copy 场景；
- 修复 async frame descriptor / empty descriptor 与 zero-init empty slice codegen；
- 修复 private function name collision、C99 import main codegen 与 short payload codegen；
- 补齐 split-C cache cleanup、Makefile dependency 与发布种子刷新路径；
- 刷新 Linux / hosted / macOS 辅助 backup seeds，使 C99 种子与当前自举源码一致。

新增或扩展验证：

- `tests/verify_c99_struct_array_and_typed_route_regressions.sh`
- `tests/verify_c99_async_frame_descriptors.sh`
- `tests/verify_c99_async_frame_empty_descriptors.sh`
- `tests/verify_compile_sh_split_cache_cleanup.sh`
- `tests/verify_split_c_makefile_dependencies.sh`
- `tests/test_c99_private_fn_name_collision.uya`
- `tests/test_c99_import_main_codegen.uya`
- `tests/test_c99_vp8_short_payload_codegen.uya`
- `tests/test_c99_zero_init_empty_slice.uya`

---

## 升级指南

从 `v0.9.9` 升级到 `v0.10.0`：

```bash
git pull
git checkout v0.10.0

make clean && make release
```

如果重点验证 fmt / if expression / C99 回归，可以额外运行：

```bash
./tests/run_programs_parallel.sh test_fmt_api.uya test_fmt_idempotent.uya test_if_expression.uya test_c99_private_fn_name_collision.uya
tests/verify_fmt_cli.sh
tests/verify_c99_struct_array_and_typed_route_regressions.sh
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 `v0.9.9` | 见 `git log v0.9.9..HEAD` |
| 提交前备份 | `make clean && make backup-all` 通过（2026-06-04；Linux / hosted seed 与 macOS hosted 辅助 seed 已刷新） |
| upm 兼容检查 | `make upm-check` 通过（2026-06-04） |
| 最终 clean-tree release | `make release-clean` 通过（2026-06-04） |
| 上一标签 | `v0.9.9` |

---

## 致谢

感谢所有为本版本贡献 fmt 工具链、C99 后端稳定性、测试与发布验证的参与者。

---

**标签**：`v0.10.0`
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.10.0)
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
