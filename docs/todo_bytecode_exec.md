# Uya Bytecode / IR 执行后端 TODO

**状态**：executable TODO, implementation pending  
**更新日期**：2026-05-17  
**配套设计**：`docs/bytecode_exec_design.md`

---

## 当前基线

当前 `uya run/test` 仍走：

```text
lexer -> parser -> checker -> optimizer -> codegen/c99 -> gcc/clang -> run
```

已知热点：

- `parse` 约 `230 ms`
- `check` 约 `2206 ms`
- `opt` 约 `563 ms`
- `gen c` 约 `13169 ms`
- `gcc/link` 额外时间尚未计入上述 `13169 ms`

因此，本 TODO 的直接目标是：

- 先为 `run/test` 提供 `exec backend`
- 让 hosted 场景跳过 `codegen/c99 + gcc/clang`

---

## 执行原则

- 先读 [bytecode_exec_design.md](bytecode_exec_design.md)、[uya_ai_prompt.md](uya_ai_prompt.md) 和相邻实现。
- 不臆造 Uya 语法、内置函数或运行时语义。
- 按 TDD 推进：先加最小测试，再做最小实现。
- 不要一开始把 `build` 路径切到 exec backend；先服务 `run/test`。
- 不要第一版直接做 native JIT；先把 `HIR -> bytecode -> VM` 跑通。
- 不要让 VM 自己“猜语义”；能在 checker/lower 提前决定的都尽量前移。

---

## Phase 0：基线确认

- [ ] 查看工作树：`git status --short`
- [ ] 阅读入口：`src/main.uya` 中 `COMMAND_RUN` / `COMMAND_TEST` 主路径
- [ ] 阅读 parser / checker / codegen 边界：
  - [ ] `src/parser/*`
  - [ ] `src/checker/*`
  - [ ] `src/codegen/c99/*`
- [ ] 跑一次最小性能基线，记录 `run/test` 当前 wall time
- [ ] 确认统计口径：`生成耗时` 不含 gcc/link
- [ ] 收集第一批 exec backend 目标测试：
  - [ ] 纯算术 / 分支 / 循环
  - [ ] 纯函数调用
  - [ ] 基础 struct/array/slice
  - [ ] `!T` / `try/catch`

---

## Phase 1：目录与骨架

- [ ] 新建 `src/exec/` 目录
- [ ] 新建骨架文件：
  - [ ] `src/exec/main.uya`
  - [ ] `src/exec/hir.uya`
  - [ ] `src/exec/lower.uya`
  - [ ] `src/exec/bytecode.uya`
  - [ ] `src/exec/builder.uya`
  - [ ] `src/exec/vm.uya`
  - [ ] `src/exec/value.uya`
  - [ ] `src/exec/frame.uya`
  - [ ] `src/exec/debug.uya`
- [ ] 在 `src/main.uya` 中 `use exec;`
- [ ] 设计导出入口：
  - [ ] `exec_build_program(...)`
  - [ ] `exec_run_program(...)`
  - [ ] `exec_dump_hir(...)`
  - [ ] `exec_dump_bytecode(...)`
- [ ] 所有新增公共 `export fn` 前写 `///` 注释

---

## Phase 2：CLI 接线

- [ ] 为 `run/test` 增加显式开关：
  - [ ] `--exec`
  - [ ] `--exec-only`
  - [ ] `--dump-exec-hir`
  - [ ] `--dump-bytecode`
  - [ ] `--trace-vm`
- [ ] `parse_args()` 或等价 driver 识别这些开关
- [ ] `COMMAND_RUN` / `COMMAND_TEST` 中增加 exec backend 分支
- [ ] 第一版策略：
  - [ ] `--exec`：失败时允许回退 C99
  - [ ] `--exec-only`：失败时直接退出非 0
- [ ] 保持默认 `run/test` 语义不变

---

## Phase 3：Exec HIR

- [ ] 在 `hir.uya` 定义：
  - [ ] `HIRModule`
  - [ ] `HIRFunction`
  - [ ] `HIRBlock`
  - [ ] `HIRStmtKind`
  - [ ] `HIRExprKind`
  - [ ] `HIRTypeRef`
  - [ ] `HIRLocalSlot`
- [ ] 确定每个 HIR 节点都挂：
  - [ ] 源位置
  - [ ] 最终类型
  - [ ] 绑定符号 / 目标函数 / field id
- [ ] 先只支持最小节点集：
  - [ ] const / local / assign
  - [ ] unary / binary / compare
  - [ ] if / while / break / continue
  - [ ] call / return
- [ ] 新增 HIR dump
- [ ] 测试：
  - [ ] 一个函数 + 一条 return
  - [ ] if/else
  - [ ] while
  - [ ] 多函数调用

---

## Phase 4：checked AST -> HIR lowering

- [ ] 新建 lowering 入口：`exec_lower_module(...)`
- [ ] 降级局部变量定义为稳定 slot
- [ ] 降级方法调用为普通调用
- [ ] 降级 `for` 为规范 loop
- [ ] 统一 `match` 的执行型表示
- [ ] 对每个函数生成结构化 HIR block
- [ ] 第一版先跳过或拒绝：
  - [ ] async
  - [ ] `@c_import`
  - [ ] inline asm
  - [ ] SIMD
  - [ ] microapp 特化
- [ ] 对不支持节点返回稳定错误信息：
  - [ ] 节点种类
  - [ ] 文件、行、列
  - [ ] 是否允许 fallback

---

## Phase 5：Bytecode 结构体与编码

- [ ] 在 `bytecode.uya` 定义：
  - [ ] `BCProgram`
  - [ ] `BCFunction`
  - [ ] `BCInstr`
  - [ ] `BCOpcode`
  - [ ] `BCConstPool`
  - [ ] `BCSourceMap`
- [ ] 选定寄存器化格式
- [ ] 为指令定义统一字段布局
- [ ] 增加 bytecode pretty printer
- [ ] 增加基础 opcode：
  - [ ] `LOAD_CONST`
  - [ ] `MOV`
  - [ ] `LOAD_LOCAL`
  - [ ] `STORE_LOCAL`
  - [ ] `ADD/SUB/MUL/DIV/REM`
  - [ ] `CMP_*`
  - [ ] `JMP/JMP_IF_*`
  - [ ] `RET`
  - [ ] `CALL`

---

## Phase 6：HIR -> Bytecode builder

- [ ] 新建 `exec_build_bytecode(...)`
- [ ] block label 分配
- [ ] local / temp 槽位分配
- [ ] 生成常量池
- [ ] 生成函数 bytecode
- [ ] 验证每个函数：
  - [ ] 所有跳转目标存在
  - [ ] 所有读取槽位已初始化
  - [ ] 所有返回路径类型一致
- [ ] 测试：
  - [ ] 字节码打印稳定
  - [ ] 同一输入多次构建结果一致

---

## Phase 7：VM 最小可运行闭环

- [ ] 在 `value.uya` 定义标量值表示
- [ ] 在 `frame.uya` 定义 `ExecFrame`
- [ ] 在 `vm.uya` 实现：
  - [ ] `vm_run_program`
  - [ ] `vm_call_function`
  - [ ] `vm_step`
- [ ] 支持最小 opcode 闭环：
  - [ ] const
  - [ ] local
  - [ ] arithmetic
  - [ ] compare
  - [ ] branch
  - [ ] call
  - [ ] return
- [ ] 让 `export fn main() i32` 程序能跑通
- [ ] 测试：
  - [ ] `uya run --exec tests/...`
  - [ ] 与 C99 路径退出码一致

---

## Phase 8：控制流与作用域

- [ ] 支持 block scope 栈
- [ ] 支持 `break`
- [ ] 支持 `continue`
- [ ] 支持嵌套循环
- [ ] 支持短路 `&&` / `||`
- [ ] 支持 `match` 基本分支
- [ ] 增加 trace：
  - [ ] 函数进入
  - [ ] 指令序号
  - [ ] 分支跳转

---

## Phase 9：聚合值与内存模型

- [ ] 定义运行时聚合值存储策略
- [ ] 支持：
  - [ ] struct init / field load / field store
  - [ ] array init / index load / index store
  - [ ] slice `(ptr, len)`
  - [ ] tuple
- [ ] 统一布局来源，避免和 C99 backend 漂移
- [ ] 若需要，提取共享布局模块
- [ ] 测试：
  - [ ] struct 字段读写
  - [ ] 数组遍历
  - [ ] slice 长度与切片

---

## Phase 10：错误联合与 `try/catch`

- [ ] 定义 `!T` 运行时表示
- [ ] 支持：
  - [ ] `MAKE_OK`
  - [ ] `MAKE_ERR`
  - [ ] `IS_ERR`
  - [ ] `UNWRAP_OK`
  - [ ] `UNWRAP_ERR`
- [ ] lowering 支持：
  - [ ] `try`
  - [ ] `catch`
  - [ ] 错误返回路径
- [ ] 测试：
  - [ ] 成功路径
  - [ ] 错误传播
  - [ ] catch 恢复

---

## Phase 11：`defer` / `errdefer` / drop

- [ ] 在 HIR 明确 scope enter/exit
- [ ] 实现 defer 栈
- [ ] 实现 errdefer 栈
- [ ] 规范执行顺序：
  - [ ] 正常返回：`defer`
  - [ ] 错误返回：`errdefer -> defer`
- [ ] 设计 drop 元数据前移：
  - [ ] 哪些局部需 drop
  - [ ] 在何 scope 退出时 drop
- [ ] 测试：
  - [ ] 单层 defer
  - [ ] 嵌套 defer
  - [ ] return 提前退出
  - [ ] error 提前退出

---

## Phase 12：全局与启动流程

- [ ] 支持全局常量初始化
- [ ] 支持全局变量初始化
- [ ] 冻结全局初始化顺序
- [ ] `main` 启动前执行 global init list
- [ ] 测试：
  - [ ] 多模块全局初始化
  - [ ] 全局初始化失败

---

## Phase 13：builtin bridge

- [ ] 编译期可折叠 builtin 前移，不进入 VM
- [ ] VM 内支持：
  - [ ] `@print`
  - [ ] `@println`
  - [ ] `@len`
  - [ ] `@error_id`
  - [ ] `@error_name`
- [ ] 错误信息与当前运行体验对齐
- [ ] 测试输出文本与现有路径一致

---

## Phase 14：`uya test --exec`

- [ ] `COMMAND_TEST` 接入 exec backend
- [ ] 保持当前测试摘要格式基本一致
- [ ] 失败退出码一致
- [ ] `--exec-only` 下禁用 C99 fallback
- [ ] 用现有快速测试集做 smoke：
  - [ ] 算术类
  - [ ] 控制流类
  - [ ] struct/array/slice 类
  - [ ] error 类

---

## Phase 15：fallback 机制

- [ ] 定义“不支持原因码”
- [ ] 定义 fallback 条件：
  - [ ] `@c_import`
  - [ ] async
  - [ ] asm
  - [ ] SIMD
  - [ ] unsupported extern ABI
- [ ] `--exec` 时自动回退 C99
- [ ] `--exec-only` 时直接失败
- [ ] 打印清晰原因，不要静默切换

---

## Phase 16：extern/libc bridge

- [ ] 设计 extern ABI 白名单
- [ ] 支持最小类型集：
  - [ ] `i32/u32/i64/u64`
  - [ ] `bool`
  - [ ] `*byte`
  - [ ] `&byte` / `&const byte`
- [ ] 支持返回标量
- [ ] 对复杂 ABI 先报不支持
- [ ] 测试：
  - [ ] 常见 libc 调用
  - [ ] `printf` 类是否需要白名单或禁用 varargs

---

## Phase 17：性能与缓存

- [ ] 增加 exec backend 子计时：
  - [ ] lowering
  - [ ] bytecode build
  - [ ] VM run
- [ ] 对比 C99 run/test 的 wall time
- [ ] 查找热点：
  - [ ] Value 拷贝
  - [ ] 聚合值构造
  - [ ] 调用分发
  - [ ] 指令 dispatch
- [ ] 评估 bytecode cache：
  - [ ] 文件 hash
  - [ ] 模块依赖 hash
  - [ ] checker 输出版本号

---

## Phase 18：覆盖率扩大

- [ ] interface / 间接调用
- [ ] union 更完整语义
- [ ] 更复杂标准库程序
- [ ] 更大回归测试集
- [ ] `uya test` 默认优先 exec backend 的可行性评估

---

## 暂缓项

- [ ] async / `@async_fn` / `@await`
- [ ] `@frame`
- [ ] `@c_import` 直接接入 exec backend
- [ ] SIMD
- [ ] inline asm
- [ ] microapp / softvm / hosted 以外目标
- [ ] native JIT

这些项不是“不做”，而是**不应阻塞第一阶段交付**。

---

## 完成标准（第一阶段）

达到以下条件，可认为 exec backend 第一阶段完成：

- [ ] `uya run --exec` 能稳定运行一批 hosted 基础程序
- [ ] 跳过 `codegen/c99 + gcc/clang`
- [ ] 基础控制流、函数调用、struct/array/slice、`!T`、`defer` 已可用
- [ ] 不支持特性能清晰报错并可按需 fallback
- [ ] 相比现有 `run`，总耗时有明显下降

