# Uya Bytecode / IR 执行后端 TODO

**状态**：executable TODO, implementation in progress
**更新日期**：2026-05-18
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

## 当前进度快照

截至 `2026-05-18`，仓库里的 exec backend 已经从“最小标量闭环”继续推进到基础 `match`、`!T`，以及第一批聚合值子集：

- 已新增 `src/exec/` 目录与首批文件：`main/hir/lower/bytecode/builder/vm/value/frame/debug`
- 已在 `src/main.uya` 中接入 `use exec;`
- 已为 `run/test` 接入 CLI 开关：
  - `--exec`
  - `--vm`
  - `--dump-exec-hir`
  - `--dump-bytecode`
  - `--trace-vm`
- 已接入第一版 fallback 语义：
  - `--exec` 遇到“不支持”时回退 C99
  - `--vm` 遇到“不支持”时直接失败
- 已有最小 HIR / bytecode / VM 闭环代码，但覆盖面仍很窄：
  - 标量常量
  - 局部变量
  - 一元/二元算术与比较
  - `if`
  - `while`
  - `break` / `continue`
  - 基础 `struct` / `array` / `slice` / `tuple`
    - `struct init`
    - 字段读取 / 字段写入
    - 数组字面量 / 下标读取 / 下标写入
    - slice 构造与 `@len`
    - tuple 字面量与 `.0/.1/...` 读取
  - `match` 基本分支（当前仅 literal/else/wildcard，且仅覆盖标量 subject）
  - 直接函数调用
  - `!T` 运行时表示
  - `try`
  - `catch`（当前仅无 `|err|` 绑定的基础恢复路径）
  - `return`
  - `@print` / `@println`
  - 第一版 top-level global init / global load-store（已覆盖单文件 hosted 与多模块 exported global 基础子集）

当前限制也必须明确记录：

- 这批代码目前仍属于“第一阶段骨架 + 最小执行路径”，不是可提交完成态
- 目前已验证：
  - `./bin/uya build src/main.uya -o /tmp/uya_exec_backend_smoke.c --no-safety-proof`
  - `./bin/uya build src/main.uya -o /tmp/uya_exec_default_smoke.c`
  - 上述两条命令都可以成功重新生成编译器的 C99 输出，说明主模块接线、类型链路、代码生成集成，以及默认安全证明下的 exec 模块边界检查都已打通
  - 用新生成的编译器二进制可直接跑通最小 smoke：
    - `./build/uya_exec_default_smoke_bin run --vm tests/test_main_only.uya`
- 目前尚未验证：
  - 在默认 `--safety-proof` 配置下完整自举
- 2026-05-18 已新增并跑通：
  - `tests/test_exec_vm_match_basic.uya`
  - `tests/test_exec_vm_error_union.uya`
  - `tests/test_exec_vm_aggregates.uya`
  - `tests/test_exec_vm_globals.uya`
  - `tests/test_exec_vm_global_init_fail.uya`
  - `tests/test_exec_vm_globals_multi.uya`
  - `tests/test_exec_vm_simd_unsupported.uya`
  - `tests/test_exec_vm_extern_unsupported.uya`
  - `bash ./tests/verify_exec_backend_progress.sh`
  - `bash ./tests/verify_exec_vm_globals.sh`
- 2026-05-18 已用新生成编译器二进制验证通过：
  - `./bin/uya build src/main.uya -o /tmp/uya_exec_todo_bin`
  - `bash ./tests/verify_exec_vm_aggregates.sh`
  - `bash ./tests/verify_exec_vm_smoke.sh`
  - `bash ./tests/verify_exec_vm_globals.sh`
  - `tests/test_exec_vm_aggregates.uya` 的 `run --vm`
- 2026-05-18 已加强回归脚本，避免“只看退出码”的假绿：
  - `verify_exec_vm_smoke.sh`
  - `verify_exec_vm_aggregates.sh`
  - `verify_exec_backend_progress.sh`
  - `verify_exec_vm_globals.sh`
  - 现在都会显式校验 `后端类型: EXEC`、`exec backend 构建完成` 或 fallback 原因
- 当前仍有一个已知残留：
  - `tests/test_exec_vm_error_union.uya` 在 exec 路径可运行通过，但前端仍会打印两条历史诊断 `try 只能在函数中使用`；这属于 checker 现有诊断链路问题，尚未在本轮收敛
  - 当前 global 路径已打通单文件 hosted，以及多模块 `use module.item` 导出的 exec-VM-可表示 global 基础子集；更复杂全局类型与更大覆盖面回归仍待继续扩大

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

- [x] 查看工作树：`git status --short`
- [x] 阅读入口：`src/main.uya` 中 `COMMAND_RUN` / `COMMAND_TEST` 主路径
- [x] 阅读 parser / checker / codegen 边界：
  - [x] `src/parser/*`
  - [x] `src/checker/*`
  - [x] `src/codegen/c99/*`
- [x] 跑一次最小性能基线，记录 `run/test` 当前 wall time
- [x] 确认统计口径：`生成耗时` 不含 gcc/link
- [x] 收集第一批 exec backend 目标测试：
  - [x] 纯算术 / 分支 / 循环
  - [x] 纯函数调用
  - [x] 基础 struct/array/slice
  - [x] `!T` / `try/catch`

备注：

- 已记录最小基线：`./bin/uya run tests/test_if_return_simple.uya`，wall time 约 `0.124s`
- 当前仅完成测试样本收集与 smoke 入口梳理，尚未形成 exec backend 回归集
- `tests/test_main_only.uya` 已成为当前最小 `--vm` smoke，后续应继续补算术、分支、循环、函数调用的独立回归

---

## Phase 1：目录与骨架

- [x] 新建 `src/exec/` 目录
- [x] 新建骨架文件：
  - [x] `src/exec/main.uya`
  - [x] `src/exec/hir.uya`
  - [x] `src/exec/lower.uya`
  - [x] `src/exec/bytecode.uya`
  - [x] `src/exec/builder.uya`
  - [x] `src/exec/vm.uya`
  - [x] `src/exec/value.uya`
  - [x] `src/exec/frame.uya`
  - [x] `src/exec/debug.uya`
- [x] 在 `src/main.uya` 中 `use exec;`
- [x] 设计导出入口：
  - [x] `exec_build_program(...)`
  - [x] `exec_run_program(...)`
  - [x] `exec_dump_hir(...)`
  - [x] `exec_dump_bytecode(...)`
- [x] 所有新增公共 `export fn` 前写 `///` 注释

---

## Phase 2：CLI 接线

- [x] 为 `run/test` 增加显式开关：
  - [x] `--exec`
  - [x] `--vm`
  - [x] `--dump-exec-hir`
  - [x] `--dump-bytecode`
  - [x] `--trace-vm`
- [x] `parse_args()` 或等价 driver 识别这些开关
- [x] `COMMAND_RUN` / `COMMAND_TEST` 中增加 exec backend 分支
- [x] 第一版策略：
  - [x] `--exec`：失败时允许回退 C99
  - [x] `--vm`：失败时直接退出非 0
- [x] 保持默认 `run/test` 语义不变

备注：

- 当前仍未改动默认无开关时的 `run/test` 主路径，默认行为依旧是 C99 + 宿主工具链
- 现阶段 fallback 的“不支持”判定主要依赖 exec backend 内部错误码与错误消息，后续仍需收敛成更稳定的原因码体系

---

## Phase 3：Exec HIR

- [x] 在 `hir.uya` 定义：
  - [x] `HIRModule`
  - [x] `HIRFunction`
  - [x] `HIRBlock`
  - [x] `HIRStmtKind`
  - [x] `HIRExprKind`
  - [x] `HIRTypeRef`
  - [x] `HIRLocalSlot`
- [x] 确定每个 HIR 节点都挂：
  - [x] 源位置
  - [x] 最终类型
  - [x] 绑定符号 / 目标函数 / field id
- [x] 先只支持最小节点集：
  - [x] const / local / assign
  - [x] unary / binary / compare
  - [x] if / while / break / continue
  - [x] call / return
- [x] 新增 HIR dump
- [x] 测试：
  - [x] 一个函数 + 一条 return
  - [x] if/else
  - [x] while
  - [x] 多函数调用

---

## Phase 4：checked AST -> HIR lowering

- [x] 新建 lowering 入口：`exec_lower_module(...)`
- [x] 降级局部变量定义为稳定 slot
- [x] 降级方法调用为普通调用
- [x] 降级 `for` 为规范 loop
- [x] 统一 `match` 的执行型表示
- [x] 对每个函数生成结构化 HIR block
- [x] 第一版先跳过或拒绝：
  - [x] async
  - [x] `@c_import`
  - [x] inline asm
  - [x] SIMD
  - [x] microapp 特化
- [x] 对不支持节点返回稳定错误信息：
  - [x] 节点种类
  - [x] 文件、行、列
  - [x] 是否允许 fallback

备注：

- 目前 lowering 还没有完整枚举所有不支持路径；已显式拒绝的一部分特性有稳定报错，更细粒度 extern ABI 白名单仍需后续补全
- 当前 `for`、基础 `match`、基础 `try/catch` 已进入可运行子集
- 当前 `match` 仍只支持 literal/else/wildcard 分支，不支持 enum/union/error/bind 等更完整模式
- 当前 `catch` 仍只支持无 `|err|` 绑定、且 catch 块可被收敛为单表达式结果的基础形式

---

## Phase 5：Bytecode 结构体与编码

- [x] 在 `bytecode.uya` 定义：
  - [x] `BCProgram`
  - [x] `BCFunction`
  - [x] `BCInstr`
  - [x] `BCOpcode`
  - [x] `BCConstPool`
  - [x] `BCSourceMap`
- [x] 选定寄存器化格式
- [x] 为指令定义统一字段布局
- [x] 增加 bytecode pretty printer
- [x] 增加基础 opcode：
  - [x] `LOAD_CONST`
  - [x] `MOV`
  - [ ] `LOAD_LOCAL`
  - [ ] `STORE_LOCAL`
  - [x] `ADD/SUB/MUL/DIV/REM`
  - [x] `CMP_*`
  - [x] `MAKE_OK/MAKE_ERR/IS_ERR/UNWRAP_OK/UNWRAP_ERR`
  - [x] `JMP/JMP_IF_*`
  - [x] `RET`
  - [x] `CALL`

备注：

- 第一版 builder 目前把 local 读写折叠进寄存器槽位和 `MOV`，尚未单独引入 `LOAD_LOCAL/STORE_LOCAL`

---

## Phase 6：HIR -> Bytecode builder

- [x] 新建 `exec_build_bytecode(...)`
- [x] block label 分配
- [x] local / temp 槽位分配
- [x] 生成常量池
- [x] 生成函数 bytecode
- [x] 验证每个函数：
  - [x] 所有跳转目标存在
  - [x] 所有读取槽位已初始化
  - [x] 所有返回路径类型一致
- [x] 测试：
  - [x] 字节码打印稳定
  - [x] 同一输入多次构建结果一致

---

备注：

- 2026-05-17 已把重复标量/字符串常量收敛到共享 `const pool`，避免在 bytecode 指令流里重复内联同值常量

---

## Phase 7：VM 最小可运行闭环

- [x] 在 `value.uya` 定义标量值表示
- [x] 在 `frame.uya` 定义 `ExecFrame`
- [x] 在 `vm.uya` 实现：
  - [x] `vm_run_program`
  - [x] `vm_call_function`
  - [x] `vm_step`
- [x] 支持最小 opcode 闭环：
  - [x] const
  - [x] local
  - [x] arithmetic
  - [x] compare
  - [x] branch
  - [x] call
  - [x] return
- [x] 让 `export fn main() i32` 程序能跑通
- [x] 测试：
  - [x] `uya run --exec tests/...`
  - [x] 与 C99 路径退出码一致

---

## Phase 8：控制流与作用域

- [x] 支持 block scope 栈
- [x] 支持 `break`
- [x] 支持 `continue`
- [x] 支持嵌套循环
- [x] 支持短路 `&&` / `||`
- [x] 支持 `match` 基本分支
- [x] 增加 trace：
  - [x] 函数进入
  - [x] 指令序号
  - [x] 分支跳转

---

## Phase 9：聚合值与内存模型

- [x] 定义第一版运行时聚合值存储策略
- [x] 支持：
  - [x] struct init / field load / field store
  - [x] array init / index load / index store
  - [x] slice 第一版视图表示与 `@len`
  - [x] tuple
- [ ] 统一布局来源，避免和 C99 backend 漂移
- [ ] 若需要，提取共享布局模块
- [x] 测试：
  - [x] struct 字段读写
  - [x] slice 长度与切片
  - [x] tuple 读取
  - [x] 数组遍历

备注：

- 当前第一版聚合值实现选择“聚合值 owning storage + slice 共享 backing store 视图”：
  - array / struct / tuple 按值持有元素槽
  - slice 记录 `(aggregate, start, len)`，避免切片时复制整段元素
- 当前目标是先打通 `run/test` 的基础 hosted 子集，不追求与 C99 backend 完整共享布局元数据
- 当前 `slice.ptr`、更复杂聚合值嵌套语义、以及与 extern ABI 对齐仍未进入支持面

---

## Phase 10：错误联合与 `try/catch`

- [x] 定义 `!T` 运行时表示
- [x] 支持：
  - [x] `MAKE_OK`
  - [x] `MAKE_ERR`
  - [x] `IS_ERR`
  - [x] `UNWRAP_OK`
  - [x] `UNWRAP_ERR`
- [x] lowering 支持：
  - [x] `try`
  - [x] `catch`
  - [x] 错误返回路径
- [x] 测试：
  - [x] 成功路径
  - [x] 错误传播
  - [x] catch 恢复

备注：

- 当前仅覆盖标量 payload 的 `!T`
- 当前 `catch` 仍不支持 `|err|` 绑定
- 当前已验证 exec backend 运行时语义闭环，但 checker 侧仍有残留误报诊断待后续清理

---

## Phase 11：`defer` / `errdefer` / drop

- [ ] 在 HIR 明确 scope enter/exit
- [x] 实现 defer 栈
- [x] 实现 errdefer 栈
- [x] 规范执行顺序：
  - [x] 正常返回：`defer`
  - [x] 错误返回：`errdefer -> defer`
- [ ] 设计 drop 元数据前移：
  - [ ] 哪些局部需 drop
  - [ ] 在何 scope 退出时 drop
- [x] 测试：
  - [x] 单层 defer
  - [x] 嵌套 defer
  - [x] return 提前退出
  - [x] error 提前退出

备注：

- 2026-05-18 已接通 `defer/errdefer` 的 exec 路径，不再在 lowering 阶段直接报 unsupported
- 当前实现选择“builder 期 cleanup scope 栈 + 显式出口清理”：
  - 在 HIR 中保留 `HIR_STMT_DEFER` / `HIR_STMT_ERRDEFER`
  - 在 bytecode builder 中按 block scope 收集 cleanup
  - 在 `return` / `break` / `continue` / `try` 错误传播出口前展开清理
- 当前实现刻意没有给 VM 增加运行时 defer 栈，优先复用现有 bytecode/VM 闭环，减少 dispatch 与解释执行额外开销
- 当前已验证：
  - 正常返回仅执行 `defer`
  - 错误返回先执行 `errdefer`，再执行 `defer`
  - `break` / `continue` 会触发当前作用域 `defer`
- 当前尚未完成：
  - drop 自动析构元数据前移
  - “纯 HIR 层显式 scope enter/exit 节点”建模
  - 更完整的嵌套 `defer` 回归集

---

## Phase 12：全局与启动流程

- [x] 支持全局常量初始化（当前先覆盖单文件 hosted 子集）
- [x] 支持全局变量初始化（当前先覆盖单文件 hosted 子集）
- [x] 冻结全局初始化顺序（当前按 merged AST 顶层声明顺序）
- [x] `main` 启动前执行 global init list
- [x] 测试：
  - [x] 多模块全局初始化
  - [x] 全局初始化失败

备注：

- 2026-05-18 已接入第一版 global runtime 模型：
  - HIR 已新增 `HIRGlobalSlot` 与 `HIR_EXPR_GLOBAL`
  - bytecode 已新增 `LOAD_GLOBAL` / `STORE_GLOBAL`
  - VM 已新增 global 存储区与 `global_init_function_index`
  - 入口执行顺序已变为“先 global init，再 `main`”
- 当前 global 收集会过滤 `UYA_ROOT` 下 runtime 自身的顶层全局，避免把当前 VM 不可表示的 runtime state 误拉进用户程序的 global init list，也避免无意义扩大 const pool / init 开销
- 当前已验证：
  - `tests/test_exec_vm_globals.uya`
  - `tests/test_exec_vm_global_init_fail.uya`
  - `tests/test_exec_vm_globals_multi.uya`
  - `bash ./tests/verify_exec_vm_globals.sh`
- 当前已完成：
  - 跨模块 `use module.item` 导出的 global 访问基础路径
  - 多模块全局初始化顺序基础回归
- 当前尚未完成：
  - 更复杂全局类型（当前仍以 exec VM 可表示子集为准）
  - 更大规模多模块 global 回归矩阵

---

## Phase 13：builtin bridge

- [x] 编译期可折叠 builtin 前移，不进入 VM
- [ ] VM 内支持：
  - [x] `@print`
  - [x] `@println`
  - [x] `@len`
  - [x] `@error_id`
  - [x] `@error_name`
- [x] 错误信息与当前运行体验对齐
- [x] 测试输出文本与现有路径一致

备注：

- `@len` 已随第一版 array/slice lowering 与 bytecode/VM 路径接通
- `@print` / `@println` 已有最小 VM bridge，可覆盖当前 exec smoke 与 defer/errdefer 顺序回归
- `@error_id` / `@error_name` 已接通命名错误字面量的 exec lowering、bytecode、VM 查表路径，并新增：
  - `tests/test_exec_vm_error_builtin.uya`
  - `tests/verify_exec_vm_error_builtin.sh`
- `@size_of` / `@align_of` / `@src_name` / `@src_path` / `@src_line` / `@src_col` 已在 exec lowering 前折叠；`@len(array)`、`@error_id(error.X)`、`@error_name(error.X)` 不再生成 VM opcode
- 新增 `tests/test_exec_vm_builtin_bridge.uya` 与 `tests/verify_exec_vm_builtin_bridge.sh`，覆盖 builtin bridge 输出与 bytecode 折叠断言
- 其余 builtin bridge 仍未系统整理到统一模块

---

## Phase 14：`uya test --exec`

- [x] `COMMAND_TEST` 接入 exec backend
- [x] 保持当前测试摘要格式基本一致
- [x] 失败退出码一致
- [x] `--vm` 下禁用 C99 fallback
- [x] 用现有快速测试集做 smoke：
  - [x] 算术类
  - [x] 控制流类
  - [x] struct/array/slice 类
  - [x] error 类

备注：

- 已新增 `tests/verify_exec_backend_progress.sh`，覆盖 `uya test --vm` 基本链路、const pool dump、`try/catch` 错误联合路径、聚合值基础路径，以及 `@c_import` unsupported 原因
- 已新增 `tests/test_exec_vm_match_basic.uya`、`tests/test_exec_vm_error_union.uya`、`tests/test_exec_vm_aggregates.uya`
- 已新增 `tests/test_exec_vm_defer.uya`
- 已新增 `tests/test_exec_vm_simd_unsupported.uya`、`tests/test_exec_vm_extern_unsupported.uya`
- 已新增 `tests/verify_exec_vm_aggregates.sh`
- 已新增 `tests/verify_exec_vm_defer.sh`
- `tests/verify_exec_vm_smoke.sh` 已纳入 `for range` 与聚合值用例，并已在新生成编译器二进制下恢复全绿
- 相关 verify 脚本现已强制校验真实 EXEC 路径与 fallback 原因，避免“空 bytecode dump / 仅退出码一致”的假阳性

---

## Phase 15：fallback 机制

- [x] 定义“不支持原因码”
- [ ] 定义 fallback 条件：
  - [x] `@c_import`
  - [x] async
  - [x] asm
  - [x] SIMD
  - [x] unsupported extern ABI
- [x] `--exec` 时自动回退 C99
- [x] `--vm` 时直接失败
- [x] 打印清晰原因，不要静默切换

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
  - [x] lowering
  - [x] bytecode build
  - [x] VM run
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
