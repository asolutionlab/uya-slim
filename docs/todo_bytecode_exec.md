# Uya Bytecode / IR 执行后端 TODO

**状态**：executable TODO, implementation in progress
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

## 当前进度快照

截至 `2026-05-17` 晚间，仓库里已经有第一批可编译的 exec backend 骨架与主链路接线：

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
  - 直接函数调用
  - `return`
  - `@print` / `@println`

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
- [ ] 统一 `match` 的执行型表示
- [x] 对每个函数生成结构化 HIR block
- [x] 第一版先跳过或拒绝：
  - [x] async
  - [x] `@c_import`
  - [x] inline asm
  - [ ] SIMD
  - [x] microapp 特化
- [x] 对不支持节点返回稳定错误信息：
  - [x] 节点种类
  - [x] 文件、行、列
  - [x] 是否允许 fallback

备注：

- 目前 lowering 还没有完整枚举所有不支持路径；已显式拒绝的一部分特性有稳定报错，`SIMD` 与更细粒度 extern ABI 原因码仍需补全
- 当前 `for` / `match` / 聚合值 / `try/catch` 都还没有进入可运行子集

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
- [ ] 验证每个函数：
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
- [ ] 支持 `match` 基本分支
- [x] 增加 trace：
  - [x] 函数进入
  - [x] 指令序号
  - [x] 分支跳转

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

- [x] `COMMAND_TEST` 接入 exec backend
- [x] 保持当前测试摘要格式基本一致
- [x] 失败退出码一致
- [x] `--vm` 下禁用 C99 fallback
- [ ] 用现有快速测试集做 smoke：
  - [x] 算术类
  - [x] 控制流类
  - [ ] struct/array/slice 类
  - [ ] error 类

备注：

- 已新增 `tests/verify_exec_backend_progress.sh`，覆盖 `uya test --vm` 基本链路、const pool dump，以及 `catch` / `@c_import` unsupported 原因

---

## Phase 15：fallback 机制

- [x] 定义“不支持原因码”
- [ ] 定义 fallback 条件：
  - [x] `@c_import`
  - [x] async
  - [x] asm
  - [ ] SIMD
  - [ ] unsupported extern ABI
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
