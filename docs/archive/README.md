# 文档归档索引

**建立日期**：2026-06-20

本目录用于记录已经完成、只保留版本证据、或不再作为当前开发入口的 TODO / PLAN / REPORT 文档。

当前只建立索引，不物理移动原文件。原因是早期文档、release notes、测试说明和设计文档之间存在交叉引用；移动文件前必须先修正引用路径，避免文档断链。

## 已完成或历史归档候选

| 文档 | 类型 | 当前处理 | 说明 |
|------|------|----------|------|
| [`../ASM_TODO.md`](../ASM_TODO.md) | TODO | 保留原位，索引归档 | `@asm` 实施 TODO 已标记项目完成；旧 `compiler-c/` 路径仅为版本记录。 |
| [`../ASM_STAGE3_COMPLETION_REPORT.md`](../ASM_STAGE3_COMPLETION_REPORT.md) | REPORT | 保留原位，索引归档 | `@asm` 阶段 3 完成报告。 |
| [`../ASM_FIXES_REPORT.md`](../ASM_FIXES_REPORT.md) | REPORT | 保留原位，索引归档 | `@asm` 修复报告。 |
| [`../ASM_STATUS_REPORT.md`](../ASM_STATUS_REPORT.md) | REPORT | 保留原位，索引归档 | `@asm` 阶段性状态快照，后续状态以当前源码和测试为准。 |
| [`../ASM_IMPLEMENTATION_PROGRESS.md`](../ASM_IMPLEMENTATION_PROGRESS.md) | REPORT | 保留原位，索引归档 | `@asm` 实施进度记录。 |
| [`../todo_async_full_language_dynamic_resources_completed.md`](../todo_async_full_language_dynamic_resources_completed.md) | TODO | 保留原位，索引归档 | 异步完整语法与动态资源相关完成记录；后续权威任务以未带 `_completed` 的 TODO 为准。 |

## 历史参考但暂不归档

| 文档 | 类型 | 当前处理 | 原因 |
|------|------|----------|------|
| [`../todo_mini_to_full.md`](../todo_mini_to_full.md) | TODO | 保留原位 | 仍有大量历史路线和实现语义可查，但顶部已标注旧路径仅用于版本记录。 |
| [`../extern_var_impl_plan.md`](../extern_var_impl_plan.md) | PLAN | 保留原位 | 作为 extern 变量实现历史依据，顶部已标注旧路径仅用于版本记录。 |
| [`../number_literals_enhancement.md`](../number_literals_enhancement.md) | PLAN | 保留原位 | 作为数字字面量演进说明，顶部已标注旧路径仅用于版本记录。 |
| [`../syscall_design.md`](../syscall_design.md) | PLAN | 保留原位 | 作为 `@syscall` 设计文档继续被引用。 |
| [`../uya_nostdlib_plan.md`](../uya_nostdlib_plan.md) | PLAN | 保留原位 | 仍描述 nostdlib 构建背景和约束。 |

## 归档规则

- 已完成 TODO / PLAN / REPORT 先加入本索引，再决定是否物理移动。
- 物理移动前必须运行引用搜索，并同步修正文档链接。
- 当前开发指导、语言规范、测试说明和 release 草案不归档。
- release notes 保留在 [`../releases/`](../releases/)；目录级历史路径说明见 [`../releases/README.md`](../releases/README.md)。
- 正在执行中的 [`../todo_core_compiler_refactor.md`](../todo_core_compiler_refactor.md) 和 [`../core_compiler_refactor_plan.md`](../core_compiler_refactor_plan.md) 暂不归档，待完成后再加入本索引。
