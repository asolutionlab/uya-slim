# Uya Bytecode / IR 执行后端 TODO

**状态**：executable TODO, implementation in progress
**更新日期**：2026-05-26
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

因此，本 TODO 的第一阶段直接目标是：

- 先为 `run/test` 提供 `exec backend`
- 先让 hosted 基础程序场景跳过 `codegen/c99 + gcc/clang`
- `uya run --vm src/main.uya` 目前视为拉伸目标，用来检验 exec backend 对编译器本体 hosted 子集的覆盖度；它不是当前第一阶段已承诺的完成标准

## 当前进度快照

截至 `2026-05-21`，仓库里的 exec backend 已经从“最小标量闭环”继续推进到基础 `match`、`!T`，以及第一批聚合值子集：

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
- 2026-05-26 实测补充：
  - 在 exec lowering 内部把“仅用于恢复表达式类型”的 `checker_infer_type(...)` 收口为“静默诊断 + 临时关闭 safety proof”之后，`./bin/uya run --vm src/main.uya` 默认 proof 路线当前已不再刷出大量二次证明噪音
  - 当前默认 `--safety-proof` 与 `--no-safety-proof` 的 exec 前沿都已收敛到同一个 blocker：
    - `src/checker/type_accessors.uya:88:17: exec: 当前仅支持单表达式 catch/match 分支块`
  - 这说明此前那批大面积 proof 报错主要来自 exec lowering 的二次类型推断副作用，而不是“默认 proof 路线本身完全不可用于观察 exec 前沿”
- 2026-05-18 已新增并跑通：
  - `tests/test_exec_vm_match_basic.uya`
  - `tests/test_exec_vm_error_union.uya`
  - `tests/test_exec_vm_aggregates.uya`
  - `tests/test_exec_vm_globals.uya`
  - `tests/test_exec_vm_global_init_fail.uya`
  - `tests/test_exec_vm_globals_multi.uya`
  - `tests/test_exec_vm_simd_unsupported.uya`
  - `tests/test_exec_vm_extern_bridge.uya`
  - `tests/test_exec_vm_extern_unsupported.uya`
  - `bash ./tests/verify_exec_backend_progress.sh`
  - `bash ./tests/verify_exec_vm_extern_bridge.sh`
  - `bash ./tests/verify_exec_vm_globals.sh`
- 2026-05-18 已用新生成编译器二进制验证通过：
  - `./bin/uya build src/main.uya -o /tmp/uya_exec_todo_bin`
  - `bash ./tests/verify_exec_vm_aggregates.sh`
  - `bash ./tests/verify_exec_vm_smoke.sh`
  - `bash ./tests/verify_exec_vm_globals.sh`
  - `tests/test_exec_vm_aggregates.uya` 的 `run --vm`
- 2026-05-18 已新增并跑通：
  - `tests/test_exec_vm_stdio_no_varargs.uya`
  - `bash ./tests/verify_exec_vm_stdio_no_varargs.sh`
  - 当前已确认固定参数、无额外 varargs 实参的 `printf(...)` 可走 exec bridge，不再在 `--vm` 下直接卡在 `extern_abi`
- 2026-05-19 已新增：
  - `tests/test_exec_vm_libc_module_global.uya`
  - 用于稳定复现 `use libc;` + `libc.stdout/libc.stderr` 这类 whole-module import 成员式全局访问路径
- 2026-05-19 已新增并跑通：
  - `tests/test_exec_vm_struct_init_zero_fill.uya`
  - `tests/test_exec_vm_bitwise.uya`
  - `bash ./tests/verify_exec_vm_smoke.sh`
  - `bash ./tests/verify_exec_vm_globals.sh`
- 2026-05-19 已向前推进：
  - `struct` 字面量缺失字段现已支持按零值补齐
  - 当前实现不会在 lowering 阶段把 `[byte: 65536]` 这类大数组缺省字段膨胀成巨型常量 pack，而是走“零值表达式 + bytecode 构造期重复填充 + VM 运行期聚合值构造”
  - 已新增 `BC_MAKE_ARRAY_REPEAT`，用于零值数组这类高重复度聚合值构造，避免编译期/bytecode 体积线性爆炸
  - exec VM 现已补上基础位运算：
    - `&`
    - `|`
    - `^`
    - `<<`
    - `>>`
  - whole-module import 的 `libc.stdout` 最小固定字符串路径现已闭环：
    - `fprintf(libc.stdout, "literal" as *byte)`
    - `fprintf(libc.stderr, "literal" as *byte)`
    - 当前做法是在 host bridge 中对 VM 内部 `&FILE` 引用提取 `fd` 后直接写字节，先打通 `stdout/stderr/普通 fd` 的最小 hosted 路径
- 2026-05-19 已继续收口并通过回归：
  - exec VM 已补上 `byte/i8/u8` 小元素数组的原生连续缓冲表示
  - `stream.buffer[...]` / `ctx.buf[...]` / `&stream.buffer[0]` / `&buf[0]` 这类 hosted stdio 真实命中的地址与下标路径已在 builder + VM 两侧闭环
  - `fprintf -> vfprintf -> _vfprintf_impl -> snprintf` 的 exec VM 路径现已完整跑通
  - `exec_lower_expr_type(...)` 在临时推断时现已同步维护 `current_return_type`
  - `AST_TRY_EXPR` / `AST_CATCH_EXPR` 已在 exec lowering 入口前置处理，避免再次触发 checker 误报
  - 新增并通过：
    - `tests/test_exec_vm_stdio_varargs.uya`
    - `bash ./tests/verify_exec_vm_stdio_varargs.sh`
    - `tests/test_exec_vm_compiler_typed_catch_local.uya`
    - `tests/test_exec_vm_compiler_field_pointer_index.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 2026-05-19 已向前推进：
  - exec lowering 现已不再依赖 `checker.import_table` 才能识别 whole-module import 的模块别名
  - 当前已补：
    - 从当前文件 `use` 语句恢复模块别名
    - 按 AST 实际命中的 `module_alias.field` 收集 whole-module import 需要的导出全局
    - `&expr` 走 `exec_lower_make_ref_expr(...)`
  - 这意味着 `libc.stdout` 这类“模块别名.导出全局访问”不再是当前最前面的 blocker
- 2026-05-20 已继续收口：
  - bytecode 已新增 `BC_LOAD_LOCAL` / `BC_STORE_LOCAL`
  - local rvalue 读取、`var init`、local 赋值与 catch 绑定现已走显式 local opcode，而不再借道 `MOV`
  - 针对 local/global/field/index 的地址型路径已统一收口到 `ADDR_*`，避免“先拷贝聚合值再写回”导致的伪写入
  - `@size_of/@align_of` 的 struct layout 现已按字段对齐与整体补齐计算，`run` 与 `run --vm` 对 `Nested { pair: Pair, flag: bool }` 这类嵌套 struct 的输出已收敛为一致的 `8 / 4 / 12 / 4`
  - 新增并通过：
    - `tests/test_exec_vm_local_load_store.uya`
    - `tests/test_exec_vm_layout_consistency.uya`
    - `bash ./tests/verify_exec_backend_progress.sh`
    - `./bin/uya test tests/test_async_fn_local_fixed_array.uya`
- 2026-05-21 已继续收口：
  - `_ = expr;` 这类 discard assignment 已在 exec lowering 中直接降成“保留 RHS 副作用、丢弃结果”的表达式语句，不再误走 lvalue assign 路径
  - `catch { side_effects...; value; }` 与 `catch { side_effects...; return ...; }` 这类“前缀副作用 + 最终值/return”块现已在 catch lowering + builder 两侧闭环
  - 新增并通过：
    - `tests/test_exec_vm_discard_assign.uya`
    - `tests/test_exec_vm_catch_block_prefix.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - `./bin/uya run --vm src/main.uya` 的前沿已继续前推，当前不再卡在 `_ = ...;` 或多语句 catch block，而是前移到 `./lib/kernel/payload.uya:165:9: exec: 当前不支持 slice.ptr`
- 2026-05-26 已继续收口 `!void` catch / return 路径：
  - `!void` 函数中的裸 `return;` 现已在 exec lowering 中正确视为“返回 `ok(void)`”，不再在 builder 阶段误报 `exec: 非 void 函数缺少返回值`
  - `fail() catch { side_effects...; assign_stmt; }` 这类“`!void` catch + void 尾语句”现已闭环；error 分支会执行整块副作用，再产出稳定的 void 值
  - 新增并通过：
    - `tests/test_exec_vm_catch_void_tail.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 2026-05-21 已继续收口：
  - `array-of-pointer` 的 inline 成员访问/写回现已闭环，不再在 lowering 阶段把 `nodes[idx].field` 这类链路掉成 `void`
  - file-local import / whole-module alias 的“裸标识符全局读写”现已闭环：
    - `use libc.errno; errno = ENOENT;`
    - `use module.submodule; submodule = ...` 这类“模块别名恰好与导出全局同名”的 self-named global 路径
  - exec lowering 的 imported global 解析与 global slot 收集，当前已不再只依赖 `checker.import_table`：
    - 会从当前文件 `use module.item` 恢复 direct imported global
    - 也会从当前文件 `use module.submodule;` 恢复 whole-module alias 对同名导出全局的访问
  - 新增并通过：
    - `tests/test_exec_vm_compiler_array_ptr_member.uya`
    - `tests/test_exec_vm_compiler_imported_global_ident.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - `./bin/uya run --vm src/main.uya` 的最新 exec 前沿已继续前推：
    - 不再卡在 `programs[i].program_decl_count`
    - 不再卡在 `errno = ENOENT`
    - 当前最新 blocker 已前移到 `./lib/libc/stdlib.uya:1083:38: exec: 当前仅支持局部变量/参数/全局标识符`
    - 对应真实代码形态是 `&opendir_storage[j]` 这类“数组元素取地址”路径
- 2026-05-23 已继续收口：
  - 语句级 `match` 不再被通用 expr-stmt 分支提前吞掉；“arm block 里直接 `return ...;`”现已优先走 returning-match lowering
  - `catch/match` 单语句块提取现已识别 `return expr;` 这一最小形态，不再把它误当成“不支持的表达式节点”
  - 这使得 union payload 绑定后的 struct 字段返回路径已闭环，例如：
    - `.payload(payload) => { return payload.name; }`
    - `.struct_generic(sg) => { return sg.name; }`
  - 新增并通过：
    - `tests/test_exec_vm_compiler_match_return_struct_field.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - `./bin/uya run --vm src/main.uya --no-safety-proof` 的最新 exec 前沿已继续前推：
    - 不再卡在 `src/checker/type_accessors.uya:86:27: exec: 尚未支持的表达式节点`
    - 当前最新 blocker 已前移到 `src/checker/type_accessors.uya:88:17: exec: 当前仅支持单表达式 catch/match 分支块`
    - 对应真实代码形态是 returning `match` 的 `else` arm 内含多语句块：
      - `if t.struct_name != null { return t.struct_name; }`
      - `return null as &byte;`
- 2026-05-26 已继续收口 `src/main.uya --vm` staged smoke：
  - returning `match` 的多语句 arm block 现已闭环，不再卡在 `src/checker/type_accessors.uya:88:17`
  - `catch |err| { ... }` 错误绑定现已闭环，不再卡在 `src/exec/vm.uya:1002:34`
  - 新增并通过：
    - `tests/test_exec_vm_compiler_match_return_block_multi_stmt.uya`
    - `tests/test_exec_vm_catch_error_bind.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - 基于当前源码重编的新编译器二进制继续验证后，`./bin/uya run --vm src/main.uya` 与 `./bin/uya run --vm src/main.uya --no-safety-proof` 当前最新前沿已共同前移到：
    - `src/codegen/c99/expr.uya:4289:19: exec: 当前仅支持局部变量/参数/全局标识符`
  - 对应真实代码形态是：
    - `const wm8e: i32 = lanes - lane_off;`
    - `else if wm8e >= 8 { ... }`
    这类“同一作用域内局部标识符在 `else if` 条件中的读取”路径
- 2026-05-26 已继续收口 `src/main.uya --vm` staged smoke：
  - 深 `else if` 链里的同作用域局部读取当前已闭环：
    - exec lowering scope depth 上限已扩到 `512`
    - builder cleanup scope depth 也已同步扩到 `512`
  - 新增并通过：
    - `tests/test_exec_vm_compiler_else_if_local.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
  - 基于当前源码重编的新编译器二进制继续验证后，`./bin/uya run --vm src/main.uya` 与 `./bin/uya run --vm src/main.uya --no-safety-proof` 的最新前沿已继续共同前推：
    - 不再卡在 `src/codegen/c99/expr.uya:4289:19: exec: 当前仅支持局部变量/参数/全局标识符`
    - 中间曾短暂前移到 `src/codegen/c99/main.uya:1670:1: exec: const pool 超出上限`
    - 在把 `EXEC_MAX_CONST_POOL_VALUES` 扩到 `8192` 后，当前最新 blocker 已进一步前移到：
      - `src/codegen/c99/main.uya:1670:1: exec: frame slot 超出上限`
- 2026-05-18 已加强回归脚本，避免“只看退出码”的假绿：
  - `verify_exec_vm_smoke.sh`
  - `verify_exec_vm_aggregates.sh`
  - `verify_exec_backend_progress.sh`
  - `verify_exec_vm_globals.sh`
  - 现在都会显式校验 `后端类型: EXEC`、`exec backend 构建完成` 或 fallback 原因
- 2026-05-18 已直接验证：
  - `./bin/uya run --vm src/main.uya`
  - 当前并非卡在 CLI 接线、VM 启动、也不再卡在最早的 `fprintf/2` varargs ABI，而是在 lowering 阶段继续向前推进后，命中“模块别名.导出全局访问”这类标识符覆盖缺口
- 当前已知最新 blocker：
  - `src/codegen/c99/main.uya:1670:1: exec: frame slot 超出上限`
  - 当前观测点已从：
    - `fprintf(..., "%s -> %s", ...)` 这类 varargs `extern`
    - `_ = expr;` discard assignment
    - `catch { fprintf(...); return ...; }` 这类带前缀副作用的 catch block
    - `slice.ptr`
    - `programs[i].program_decl_count`
    - `errno = ENOENT`
    - `&opendir_storage[j]` 这类“数组元素取地址”路径
    - `src/checker/type_accessors.uya:86:27` 的 returning match arm `payload.name`
    - `src/checker/type_accessors.uya:88:17` 的 returning `match` 多语句 arm block
    - `src/codegen/c99/utils.uya:552:21` 的 direct `extern` `mkdir/2`
    - `src/parser/main.uya:54:28` 的 file-local direct `extern` `lexer_next_token/2`
    - `src/exec/vm.uya:1002:34` 的 `catch |err| { ... }` 错误绑定
    - `src/codegen/c99/expr.uya:4289:19` 的局部标识符读取路径
    - `src/codegen/c99/main.uya:1670:1` 的 `const pool` 容量上限
    继续前移到 `src/codegen/c99/main.uya:1670:1` 的 `frame slot` 容量上限
  - 这说明 indexed address-of、atomic global、repeat array literal、`@asm_target()`、error union `.value`、union payload struct-field returning match、`catch |err|` 错误绑定、direct `extern` `mkdir/rmdir` 宿主桥，以及 parser/lexer 的 file-local direct `extern` 调用这批阻塞都已继续后移；新的缺口已从深 `else if` 局部读取语义转向编译器本体 C99 backend 路径上的更大 bytecode frame 容量
- 当前 global 路径已打通单文件 hosted、多模块 `use module.item` 导出的 exec-VM-可表示 global 基础子集，以及 `use libc; libc.stdout` 这类 whole-module import 成员式访问的识别/解析链；`struct init` 的“缺失字段按零值补齐”基础语义也已收口，但更复杂全局类型、变参 `extern` 与更大覆盖面回归仍待继续扩大

---

## 当前阶段目标与 `src/main.uya` 缺口

- 第一阶段交付目标：`uya run/test --exec` 能稳定覆盖一批 hosted 基础程序，并在支持路径上真正跳过 `codegen/c99 + gcc/clang`
- 拉伸目标：`uya run --vm src/main.uya` 能直接执行编译器本体 hosted 路线；这更适合作为“第二阶段覆盖率扩大”的收口目标，而不是当前最小交付门槛
- 当前观测：
  - `./bin/uya run --vm src/main.uya` 在默认 `--safety-proof` 配置下，当前已不再刷出大量 proof 噪音；在继续补上 returning `match` 多语句 arm block 与 `catch |err|` 绑定之后，最新前沿已与 `--no-safety-proof` 收敛到同一个新 blocker：
    - `./src/codegen/c99/expr.uya:4289:19: exec: 当前仅支持局部变量/参数/全局标识符`
  - `./bin/uya run --vm src/main.uya --no-safety-proof` 已能通过 parse / check / opt，并且已越过最早的 `u16` 全局常量缺口、`libc.stdout` 这类模块别名导出全局访问识别问题、`FILE{...}` 缺失字段补零、`stdio` 常量旗标中的位运算、`_ = expr;` discard assignment、“前缀副作用 + return/value”的 catch block、`slice.ptr`、`programs[i].program_decl_count`、`errno = ENOENT` 这类 imported global bare identifier 路径、`&opendir_storage[j]` 这类 indexed address-of 语义、`src/checker/type_accessors.uya:88:17` 的 returning `match` 多语句 arm block，以及 `src/exec/vm.uya:1002:34` 的 `catch |err|` 错误绑定；基于当前源码重编的新编译器二进制继续验证后，最新前沿已前推到 `./src/codegen/c99/expr.uya:4289:19: exec: 当前仅支持局部变量/参数/全局标识符`
- 缺口：扩 exec VM 可表示的基础值类型，至少补齐 `u8/u16/usize/isize` 这一批编译器本体会立即命中的类型，并同步放通 global / local / param / return 的统一类型 gate
- 缺口：扩通用指针值表示；当前只把 `&byte` / `&const byte` 当作字符串指针支持，距离编译器本体实际需要的 `&T/*T`、`&void/*void`、arena / AST / FILE / parser 等普通指针仍有明显差距
- 缺口：接通 `@usize_from_ptr` / `@ptr_from_usize` 这类地址型 builtin 的 exec 路径；编译器运行时和 hosted 标准库广泛依赖它们做指针换算与 buffer 访问
- 缺口：补齐 `&arr[i]` / `&slice[i]` / `const slot: &T = &storage[idx]` 这类 indexed address-of 路径；当前 `src/main.uya --vm` 最新前沿已明确落在这一类语义上
- 缺口：把 `extern` / `extern "libc"` 收敛到最终通用执行模型；对“有 Uya 函数体的 extern 实现”按普通函数 lower/执行，仅对真正无函数体或宿主专属符号保留最小 host bridge，避免继续扩编译器主路径的单函数白名单
- 缺口：为 `fprintf/snprintf/printf` 这类 varargs 接口明确最终策略；普通 fixed-arity extern 应归入统一调用模型，varargs 需单独收敛到专用 bridge、builtin helper 或明确 fallback，不能长期依赖“碰到再报 unsupported”
- 缺口：继续扩大面向编译器本体路径的 staged regressions，并收口 parser/lexer 这类 file-local direct `extern` 调用
- 缺口：为 `struct` 字面量补齐“缺失字段按零值初始化”的 exec 语义，并且要避免把 `FILE.buffer: [byte: 65536]` 这种大字段在 lowering 阶段膨胀成巨型常量 pack
- 推荐推进顺序：先补基础数值类型与通用指针表示，再补地址型 builtin，然后补 `extern/libc` 通用执行模型与最小 host bridge，最后用 `src/main.uya` 的 `run --vm` / 更大 hosted 程序回归收口

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
  - [x] `LOAD_LOCAL`
  - [x] `STORE_LOCAL`
  - [x] `ADD/SUB/MUL/DIV/REM`
  - [x] `CMP_*`
  - [x] `MAKE_OK/MAKE_ERR/IS_ERR/UNWRAP_OK/UNWRAP_ERR`
  - [x] `JMP/JMP_IF_*`
  - [x] `RET`
  - [x] `CALL`

备注：

- 2026-05-20 已把 local 读写从通用 `MOV` 中拆出：
  - `HIR_EXPR_LOCAL` 现在会显式生成 `BC_LOAD_LOCAL`
  - `HIR_STMT_VAR_INIT`、local 赋值与 catch 绑定现在会显式生成 `BC_STORE_LOCAL`
  - 对 local/global/field/index 聚合值的可寻址写入路径已统一走 `ADDR_*`，避免因为 local rvalue 先复制后再写字段/下标而丢失写回

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
- [x] 统一布局来源，避免和 C99 backend 漂移
- [x] 若需要，提取共享布局模块
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
- 当前 byte slice `slice.ptr`、编译器回归里真实命中的 `tail.ptr[0]` / `view.ptr` 路径，以及 `array-of-pointer` 的 inline 成员访问/写回已进入支持面；剩余聚合值缺口已继续收敛到 `&arr[i]` 这类 indexed address-of 语义，以及更复杂聚合值嵌套场景
- 2026-05-20 已把 tuple / struct / `!T` / tagged union 的 size/align 规则收敛到“字段对齐 + 字段间 padding + 整体补齐”模型：
  - exec lowering 的 `@size_of/@align_of` 不再把嵌套 struct 误算成纯字段大小求和
  - C99 async frame 估算里的 `get_type_size_bytes_resolved(...)` / `get_type_align_bytes_resolved(...)` 也已同步成同一套 padding 规则
  - `tests/test_exec_vm_layout_consistency.uya` 已加入默认 `run` 与 `run --vm` 的直接输出比对，持续防止 layout 漂移回归

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

- [x] 在 HIR 明确 scope enter/exit
- [x] 实现 defer 栈
- [x] 实现 errdefer 栈
- [x] 规范执行顺序：
  - [x] 正常返回：`defer`
  - [x] 错误返回：`errdefer -> defer`
- [x] 设计 drop 元数据前移：
  - [x] 哪些局部需 drop
  - [x] 在何 scope 退出时 drop
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
- 2026-05-20 已把作用域边界前移到 HIR：
  - `HIR_STMT_SCOPE_ENTER` / `HIR_STMT_SCOPE_EXIT` 已进入 dump 与 builder 主路径
  - 嵌套 block 不再通过 `if const true` 伪装作用域
  - 新增并通过：
    - `tests/test_exec_vm_hir_scope.uya`
    - `bash ./tests/verify_exec_vm_hir_scope.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 2026-05-20 已把 local drop 清理接入 exec cleanup scope：
  - `HIRLocalSlot` 现已携带 `decl/scope_id/needs_drop/drop_decl` 元数据
  - bytecode builder 会在 `HIR_STMT_VAR_INIT` 后登记当前作用域的 drop local
  - scope exit / `return` / `break` / `continue` / `try` 错误传播都会在 `defer/errdefer` 之后按逆序发出 local drop 调用
  - drop 方法会进入 exec reachable 函数集，不再依赖手写显式调用
  - 新增并通过：
    - `tests/test_exec_vm_drop_local.uya`
    - `bash ./tests/verify_exec_vm_drop_local.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 当前尚未完成：
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
  - file-local import / whole-module alias 的 imported global bare identifier 读写路径
  - 多模块全局初始化顺序基础回归
- 当前尚未完成：
  - 更复杂全局类型（当前仍以 exec VM 可表示子集为准）
  - 更大规模多模块 global 回归矩阵

---

## Phase 13：builtin bridge

- [x] 编译期可折叠 builtin 前移，不进入 VM
- [x] VM 内支持：
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
- [x] 定义 fallback 条件：
  - [x] `@c_import`
  - [x] async
  - [x] asm
  - [x] SIMD
  - [x] unsupported extern ABI
- [x] `--exec` 时自动回退 C99
- [x] `--vm` 时直接失败
- [x] 打印清晰原因，不要静默切换

备注：

- 2026-05-18 已把 fallback 判定集中到 `exec_backend_reason_allows_fallback()`，避免用“任意 unsupported 都默认回退”的隐式策略。
- 当前所有 builder/lower 主路径里的 unsupported 分支都会带稳定 reason code；`test --vm` / `test --exec` / `run --vm` / `run --exec` 现在都会打印原因码，便于回归脚本精确断言。
- `BC_CALL` 已把 callee 解析前移到 bytecode build 阶段，VM 热路径不再按函数名线性扫描，减少解释执行时的调用分发开销。

---

## Phase 16：最小 hostcall 边界（过渡）

- [x] 设计 hostcall ABI 边界
- [x] 支持最小类型集：
  - [x] `i32/u32/i64/u64`
  - [x] `bool`
  - [x] `*byte`
  - [x] `&byte` / `&const byte`
- [x] 支持返回标量
- [x] 对复杂 ABI 先报不支持
- [x] 测试：
  - [x] 常见 libc 调用
  - [x] `printf` 类是否需要白名单或禁用 varargs

备注：

- 2026-05-18 已把最初的固定白名单 extern bridge 收敛为 `body-first + compile-time hostcall registry + runtime BC_HOSTCALL`：
  - lowering 默认优先走 extern 自带函数体；只有函数体当前不可执行、或命中少量 hostcall override 时，才落到 hostcall
  - builder 会在编译期把 hostcall site intern 到 `BCProgram.host_calls`
  - VM 热路径按数值 `host_call_id` 分发，不再按函数名线性扫描，也不再为调用额外克隆参数数组
- 当前 hostcall 仍覆盖 `puts` / `atoi` / `atoll` / `isqrt` / `strcmp` / `llabs` 这批稳定签名；其中：
  - `atoi` / `isqrt` / `strcmp` 已可在“有函数体”的路径上走普通 lowering/VM
  - 当用户程序显式声明同名无函数体 `extern` stub 时，仍会优先走最小 hostcall bridge
- 2026-05-18 已把 `i64/u64` 数字字面量放通到 exec lowering / const pool / VM value，保证宽整数 extern 参数与返回值不会在 lowering 阶段被误判 unsupported。
- 2026-05-18 已新增第一版“固定参数、无额外 varargs 实参”的 stdio hostcall 过渡路径：
  - 当前已覆盖 `printf(format_only)` 与 `fprintf/sprintf/snprintf` 的 fixed/no-varargs 形式
  - 新增 `tests/test_exec_vm_stdio_no_varargs.uya` 与 `tests/verify_exec_vm_stdio_no_varargs.sh`
  - 当前仍未把更一般的 stdio varargs 语义纳入 exec，只是把最先挡住 `src/main.uya --vm` 的最小 hosted 路径向前推进了一步
- 该阶段只是过渡里程碑；最终目标不是继续扩函数名白名单，而是让“带函数体的 `extern` / `extern "libc"` 实现”进入统一 lowering/VM 路径，仅对真正宿主边界保留最小 hostcall。

---

## Phase 17：性能与缓存

- [x] 增加 exec backend 子计时：
  - [x] lowering
  - [x] bytecode build
  - [x] VM run
- [x] 对比 C99 run/test 的 wall time
- [x] 记录最小 wall time 对比样本（当前先补 smoke 级样本）
- [x] 查找热点：
  - [x] Value 拷贝
  - [x] 聚合值构造
  - [x] 调用分发
  - [x] 指令 dispatch
- [x] 评估 bytecode cache：
  - [x] 文件 hash
  - [x] 模块依赖 hash
  - [x] checker 输出版本号

备注：

- 2026-05-18 已补一条最小 wall time 对比样本：
  - `./bin/uya run tests/test_exec_vm_multi_fn.uya`：约 `0.08s`
  - `./bin/uya run --vm tests/test_exec_vm_multi_fn.uya`：约 `0.01s`
- 2026-05-23 已补 `tests/test_exec_vm_if_else.uya` 的 `run/test` 本地 wall time 对比（新生成编译器二进制，warm-cache，3 次采样中位数）：
  - `run`（C99）：约 `0.082s`
  - `run --vm`：约 `0.025s`
  - `test`（C99）：约 `0.088s`
  - `test --vm`：约 `0.025s`
- 同一用例的编译统计中：
  - C99 路径 `总耗时` 约 `9 ms`，随后仍需宿主工具链链接
  - exec 路径 `总耗时` 约 `8 ms`，`exec lowering` 约 `1 ms`，`VM run` 约 `0 ms`
- 2026-05-23 已做第一轮静态热点盘点（未接入采样 profiler，以下为当前实现的代码路径结论）：
  - `Value` 拷贝：`exec_vm_store_slot()` 几乎覆盖所有 local/global/field/index/call-result 写回；其内部统一走 `exec_value_clone()`，而后者会递归深拷贝 `struct/array/tuple/error-union` payload
  - 聚合值构造：`BC_MAKE_STRUCT/ARRAY/TUPLE` 与 `BC_MAKE_ARRAY_REPEAT` 都是“先分配 aggregate，再逐元素 `exec_value_set_index(...)`”，每个元素写入又会再次 clone
  - 调用分发：`BC_CALL` / `BC_CALL_INDIRECT` 会先把实参 clone 到临时 `call_args`，随后 `exec_vm_call_function()` 每次调用都清空整帧 `4096` 个 slots 与 `32` 个 vararg 槽
  - 指令 dispatch：`vm_step()` 当前仍是约 `69` 个 `instr.opcode == ...` 分支串行匹配，并在多数 opcode 分支里重复做 slot lookup / bounds check / clone
- 2026-05-23 已做第一轮 bytecode cache 评估（仅设计评估，未实现）：
  - 文件 hash：可直接基于最终 `file_list[]` 输入文件集合的文件内容做 hash；当前主流程已经在 `collect_module_dependencies(...)` 后拿到稳定输入列表
  - 模块依赖 hash：`collect_module_dependencies(...)` 已递归展开 `project_root/UYA_ROOT` 下的传递依赖，适合作为模块图层级的 cache key 输入，而不必再从 checker 结果反推
  - checker 输出版本号：当前仓库只有 `main.uya` 里的编译器版本字符串 `v0.9.7`，还没有独立的 checker/exec IR schema version；若后续落缓存，应新增显式 `cache schema version`，不要只复用 `--version`
- 这组数据只说明“跳过宿主工具链”方向正确，不代表已经完成系统化性能评估；后续仍需扩大样本并拆解 `Value` 拷贝、聚合值构造与 dispatch 热点

---

## Phase 18：覆盖率扩大

- [x] 编译器本体所需基础值类型：`u8/u16/usize/isize`
- [x] 通用指针值表示：`&T/*T`、`&void/*void`，而不只 `&byte`
- [x] 地址型 builtin：`@usize_from_ptr` / `@ptr_from_usize`
- [x] `extern` / `extern "libc"` 最终通用执行：带函数体的实现按普通函数 lower/执行，仅对无函数体或宿主专属符号保留最小 host bridge
- [x] varargs extern 最终策略：`fprintf/snprintf/printf` 等单独收敛到专用 bridge、builtin helper 或明确 fallback
- [x] interface / 间接调用
- [x] union 更完整语义
- [x] 更复杂标准库程序
- [x] 更大回归测试集
- [ ] `src/main.uya` 的 `run --vm` staged smoke
- [ ] `uya test` 默认优先 exec backend 的可行性评估

备注：

- 2026-05-18 已把 `u8/u16/usize/isize` 放通到 exec lowering / const pool / VM 算术与比较路径；其中 `isize` 继续遵循当前 checker 的既有实现，内部沿用 `TYPE_I64` 映射，而不是额外引入一套平行类型枚举。
- 2026-05-18 已新增通用 pointer value kind，并支持 pointer/null 比较、pointer cast、`ptr[idx]` 的 byte/整数 pointee 读写，以及 `@ptr_from_usize` / `@usize_from_ptr` 的运行期执行。
- 2026-05-18 已让一批“带函数体且非 varargs”的 `extern "libc"` 走普通 lowering/VM 路径，当前已用回归覆盖 `atoi` / `isqrt` / `strcmp`；并且当程序显式声明同名无函数体 `extern` stub 时，exec 现在会优先按 stub 走最小 host bridge，而不是误把 stdlib 里的实现体也拉进 reachable 队列。
- 2026-05-26 已继续收口：
  - `use libc.puts;` / `use libc.atoll;` / `use libc.llabs;` 这类“命中库内有函数体实现”的调用，当前已默认走普通 lowering/VM 路径，不再强制退回 hostcall
  - 当用户程序显式声明同名无函数体 `extern "libc"` stub 时，仍保持最小 host bridge，不会误把标准库实现体硬拉进 reachable 队列
- 2026-05-26 已把 stdio varargs 策略收口为稳定规则：
  - `use libc.printf;` / `use libc.fprintf;` / `use libc.snprintf;` / `use libc.sprintf;` 这类命中库内 Uya 函数体实现的 varargs 调用，当前已直接走普通 lowering/VM；`--dump-bytecode` 回归中不再出现 `BC_HOSTCALL`
  - 仅“显式声明、无函数体”的 varargs `extern` 继续保留为 `extern_abi` unsupported：`--vm` 下直接失败，`--exec` 下保持既有 fallback 语义
  - 已补强并通过：
    - `bash ./tests/verify_exec_vm_stdio_varargs.sh`
    - `bash ./tests/verify_exec_vm_extern_bridge.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 2026-05-26 已继续收口更复杂标准库程序 / direct extern 宿主桥：
  - direct `extern fn mkdir(pathname: *byte, mode: i32) i32;`
  - direct `extern fn rmdir(pathname: *byte) i32;`
  - 已新增并通过：
    - `tests/test_exec_vm_extern_mkdir_bridge.uya`
    - `tests/test_exec_vm_stdlib_unistd.uya`
    - `bash ./tests/verify_exec_vm_extern_bridge.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - 基于当前源码重编的新编译器二进制继续验证后，`./bin/uya run --vm src/main.uya --no-safety-proof` 的最新前沿已从 `src/codegen/c99/utils.uya:552:21` 的 `mkdir/2` 推进到 `src/parser/main.uya:54:28` 的 `lexer_next_token/2`
- 2026-05-26 已继续收口 `--vm` 默认 proof 路线噪音：
  - exec lowering 内部“仅为恢复类型而再次调用 checker”的路径，当前已统一切到“静默诊断 + 临时关闭 safety proof”模式
  - 这使得 `./bin/uya run --vm src/main.uya` 默认 proof 路线不再被二次 proof 报错淹没，而是直接收敛到和 `--no-safety-proof` 相同的 exec blocker
  - 当前实现点主要位于：
    - `src/exec/lower.uya`
- 2026-05-26 已继续收口面向编译器本体的 staged smoke：
  - 同模块 file-local `extern fn ...;` 声明当前会优先命中另一文件中的真实函数体，不再因为当前文件里的无函数体 stub 直接判成 `extern_abi`
  - 已新增并通过：
    - `tests/exec_vm_compiler_file_local_extern/main.uya`
    - `tests/exec_vm_compiler_file_local_extern/helper.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
  - 基于当前源码重编的新编译器二进制继续验证后，`./bin/uya run --vm src/main.uya --no-safety-proof` 的最新前沿已从 `src/parser/main.uya:54:28` 的 `lexer_next_token/2` 推进到 `src/checker/type_accessors.uya:88:17` 的 returning `match` 多语句 arm block
- 2026-05-26 已继续收口面向编译器本体的 staged smoke：
  - returning `match` 多语句 arm block 与 `catch |err|` 错误绑定当前都已补上
  - 已新增并通过：
    - `tests/test_exec_vm_compiler_match_return_block_multi_stmt.uya`
    - `tests/test_exec_vm_catch_error_bind.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
  - 基于当前源码重编的新编译器二进制继续验证后，`./bin/uya run --vm src/main.uya` 与 `./bin/uya run --vm src/main.uya --no-safety-proof` 的最新前沿已共同从 `src/checker/type_accessors.uya:88:17` / `src/exec/vm.uya:1002:34` 推进到 `src/codegen/c99/expr.uya:4289:19`
- 2026-05-26 已继续收口面向编译器本体的 staged smoke：
  - 深 `else if` 链里的同作用域局部读取当前已补上
  - 已新增并通过：
    - `tests/test_exec_vm_compiler_else_if_local.uya`
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
  - 基于当前源码重编的新编译器二进制继续验证后：
    - `./bin/uya run --vm src/main.uya`
    - `./bin/uya run --vm src/main.uya --no-safety-proof`
    已共同从 `src/codegen/c99/expr.uya:4289:19` 继续推进到 `src/codegen/c99/main.uya:1670:1`
  - 中间前沿变化：
    - 先命中 `exec: const pool 超出上限`
    - 在把 `EXEC_MAX_CONST_POOL_VALUES` 扩到 `8192` 后，当前继续卡在 `exec: frame slot 超出上限`
- 2026-05-18 已把 `printf(format_only)` 这类“固定参数、无额外 varargs 实参”的最小路径接入过渡 bridge；该桥接当前主要保留给“显式 no-body stub / 宿主边界”场景，stdio 主线路径以上述 body-first 规则为准。
- 2026-05-19 已把 `fprintf(file, "literal")` 这类“有 `FILE` 参数、无额外格式化实参”的最小路径接通到 VM/host bridge；其中 VM 内部 `&FILE` 引用会先提取 `fd` 再直接写字节，避免把 exec 内部聚合值地址误当成宿主 `FILE*`，这同样属于 body-first 之外保留的最小宿主桥接补位。
- 2026-05-18 已新增第一版 tagged union 子集：
  - `union` 值现在可进入 exec VM 表示
  - `UnionName.variant(payload)` 构造已接通 lowering / bytecode / VM
  - `match union_value { .Variant(x) => ..., else => ... }` 基础路径已可执行
  - 新增 `tests/test_exec_vm_union_dispatch.uya`
- 2026-05-26 已继续收口 union `match` 路径：
  - exec lowering 现已在补做表达式类型推断时临时回灌当前活跃局部绑定，并为 `AST_MATCH_EXPR` 走一条基于 lowering 作用域的结果类型合一逻辑，不再依赖“离开函数检查现场后”的裸 `checker_infer_type(...)`
  - `tests/test_exec_vm_union_dispatch.uya`
  - `tests/test_exec_vm_compiler_union_field_match.uya`
  - `tests/test_exec_vm_compiler_match_return_struct_field.uya`
  - 上述三条 union 路径在 `run --vm` / `run --exec` 下都已不再打印历史误诊断 `match 所有分支的返回类型必须一致`
  - 已补强并通过：
    - `bash ./tests/verify_exec_vm_compiler_regressions.sh`
    - `bash ./tests/verify_exec_backend_progress.sh`
- 2026-05-18 已打通第一版 interface / 间接调用：
  - 结构体实例方法 `obj.method(...)` 现在会在 lowering 阶段改写为带 receiver 引用的普通调用
  - VM 新增内部引用地址与 `CALL_INDIRECT`，interface 值运行时保存“方法表函数索引 + data 引用”
  - `self.field` / `self.field = ...` 已可透过 `&Self` receiver 在 VM 中读写
  - `tests/test_exec_vm_interface_dispatch.uya` 与 `tests/test_exec_vm_interface_stateful.uya` 已在 `--vm/--exec` 下通过，并纳入 `tests/verify_exec_vm_smoke.sh`
- 2026-05-18 继续把编译器本体 hosted 子集往前推了一段：
  - exec VM 现已补上 `i8/i16` 值表示、算术/比较、聚合值与全局路径，新增回归 `tests/test_exec_vm_scalar_pointer.uya`
  - enum 常量/全局值现已可进入 exec lowering / const pool / VM，新增 `tests/test_exec_vm_enum_value.uya`
  - `@max/@min` (`AST_INT_LIMIT`) 已接通到 exec lowering 的常量折叠与全局初始化，新增 `tests/test_exec_vm_int_limit.uya`
  - `EXEC_MAX_GLOBALS` 已扩到 `1024`，`EXEC_MAX_CALL_ARGS` 已扩到 `32`，避免编译器本体在全局槽位和 `parse_args(...)` 这类大签名调用上过早卡死
  - `bash ./tests/verify_exec_backend_progress.sh` 已同步覆盖上述新增能力并通过
- 当前仍有一个明确残留：
  - 以当前源码重编的新编译器二进制直接运行 `env UYA_ROOT=./lib/ /tmp/uya_exec_stage_smoke_bin run --vm src/main.uya` 或 `env UYA_ROOT=./lib/ /tmp/uya_exec_stage_smoke_bin run --vm src/main.uya --no-safety-proof`，最新观测点都已继续前推到 `./src/codegen/c99/main.uya:1670:1`；在补上深 `else if` 链里的局部读取、并把 `EXEC_MAX_CONST_POOL_VALUES` 扩到 `8192` 之后，当前最新 blocker 已收敛到 `exec: frame slot 超出上限`。这说明此前的 `src/codegen/c99/expr.uya:4289:19` 局部读取缺口已不再是当前最前 blocker，下一步应转向更大 frame/临时槽位占用的收口

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

补充说明：

- 第一阶段完成标准默认不包含 `uya run --vm src/main.uya`
- `uya run --vm src/main.uya` 更适合作为后续“覆盖率扩大 + 编译器本体 hosted 路径 smoke”阶段的拉伸目标
