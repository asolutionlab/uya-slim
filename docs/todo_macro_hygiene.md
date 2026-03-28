# Uya 卫生宏实现待办

**参考**：[macro_hygiene_design.md](macro_hygiene_design.md)（详细设计）、[uya.md](uya.md) §25 宏系统

实现时遵循项目 TDD 流程：先添加测试（或先实现再补测）→ 实现代码 → `make check` 验证。

---

## Phase 1：数据结构与预处理

### 1.1 上下文与旁表

- [ ] 在 [src/checker/macro_expand.uya](../src/checker/macro_expand.uya) 中定义 `HygieneUseEntry`、`HygieneBindingEntry`（或等价结构），字段见设计文档 §3.1。
- [ ] 扩展 `MacroExpandContext`：增加 `hygiene_use_sites`、`hygiene_use_count`、`hygiene_binding_sites`、`hygiene_binding_count`、`hygiene_rename_map`、`hygiene_rename_count`（类型与设计文档 §3.2–§3.3 一致）。

### 1.2 收集 local_binding 声明节点

- [ ] 实现 `collect_local_binding_decls(body: &ASTNode, arena: &Arena)`（或等价签名）：遍历宏体顶层，对 `const x = @mc_eval(...)` 和 `const x = @mc_type(...)` 收集**声明节点本身**，返回节点集合（可用固定大小数组或 arena 分配的表）。
- [ ] 可选：在 `extract_macro_output_with_params` 内复用该函数，替代内联的 local_bindings 收集逻辑，避免重复。

### 1.3 build_hygiene_data

- [ ] 从 `macro_decl.macro_decl_params[i].var_decl_name` 收集 `param_names`，在两处展开入口调用 `build_hygiene_data` 时传入。
- [ ] 实现 `build_hygiene_data(body, param_names, local_binding_decls, arena, expansion_id)`（或通过 ctx 传入 param 名）：
  - [ ] 第一遍：遍历宏体 AST，收集所有绑定点（var_decl / for_stmt / fn_decl_params / catch_expr_err_name）；若**绑定节点**不在 `local_binding_decls` 且名字不在 `param_names`，则分配 binding_id，写入 binding_sites，生成 `name__hyg_<expansion_id>_<binding_id>` 写入 rename_map。
  - [ ] 明确 `fn_decl_name` 首版**不**参与 hygiene，避免改写宏输出的可见函数/方法名。
  - [ ] 第二遍：作用域解析，对整棵 AST 中每个 `AST_IDENTIFIER` 解析到 binding_id / 参数 / 自由名，写入 use_sites。
- [ ] 作用域规则：BLOCK、FN_DECL、FOR、CATCH 压栈；FN_DECL 先处理 params 再处理 body；FOR 与 CATCH 的进入/绑定顺序严格对齐现有类型检查器。

### 1.4 expansion_id

- [ ] 确定 expansion_id 来源：在 TypeChecker 上增加 `macro_expansion_counter` 并在每次展开前递增，或在 macro_expand 模块内用静态变量。
- [ ] 两处展开入口（见下）在调用 `build_hygiene_data` 前取得并传入 expansion_id，并在本次展开后递增（若用 checker 字段则先取后增）。

### 1.5 两处展开入口调用 build_hygiene_data

- [ ] **AST_CALL_EXPR 路径**（expand_macros_in_node_simple 内，约 2755–2778 行）：在构建好 `ctx.bindings` 后，先得到 `local_binding_decls`（调用 `collect_local_binding_decls`），再调用 `build_hygiene_data(...)`，将结果填入 `ctx` 的 hygiene 字段，再调用 `extract_macro_output_with_params`。
- [ ] **AST_METHOD_BLOCK 路径**（约 2862–2912 行）：对 struct 返回宏，在构建好 `ctx.bindings` 后同样调用 `collect_local_binding_decls` 与 `build_hygiene_data(...)`，将结果填入 `ctx`，再调用 `extract_macro_output_with_params`。

### 1.6 merged_ctx 传递 hygiene

- [ ] 在 `extract_macro_output_with_params` 中，`merged_ctx = *ctx` 之后，确保 `merged_ctx` 的 hygiene 相关字段与 `ctx` 一致（指针拷贝即可，不置空）。

---

## Phase 2：拷贝时应用卫生

### 2.1 deep_copy_ast_with_params

- [ ] **前置判断**：仅当 `ctx.hygiene_use_sites != null`（或约定的“已启用卫生”条件）时才进行 use_sites/binding_sites 查找；否则保持当前逻辑（只做参数替换）。
- [ ] **AST_IDENTIFIER**：若启用卫生，在 use_sites 中查当前节点；binding_id == -1 则 find_param_binding 并替换；binding_id >= 0 则 copy.identifier_name = rename_map[binding_id]（并保证 binding_id < hygiene_rename_count）；-2 或未查到则保留 node.identifier_name。
- [ ] **AST_VAR_DECL**：若启用卫生且在 binding_sites 中查到该 node，则 copy.var_decl_name = rename_map[binding_id]；否则保持 node.var_decl_name。
- [ ] **AST_FOR_STMT**：若启用卫生且在 binding_sites 中查到该 for 节点（对应循环变量），则 copy.for_stmt_var_name = rename_map[binding_id]；否则保持原名。
- [ ] **AST_FN_DECL**：保持 `fn_decl_name` 原样。fn_decl_params 的拷贝在递归时走 AST_VAR_DECL 分支，已由上面处理。
- [ ] **AST_CATCH_EXPR**：若启用卫生且在 binding_sites 中查到该 catch 节点（对应错误变量），则 copy.catch_expr_err_name = rename_map[binding_id]；否则保持原名。

### 2.2 deep_copy_ast_with_field_subst

- [ ] 在拷贝 AST_IDENTIFIER、AST_VAR_DECL、AST_FOR_STMT、AST_CATCH_EXPR、AST_FN_DECL 的参数节点时，应用与 `deep_copy_ast_with_params` 相同的“是否启用卫生 + use_sites/binding_sites 查找 + rename_map”逻辑，保证 for info.fields 展开后的块内标识符也卫生。
- [ ] （可选）实现 `lookup_use_sites(ctx, node)` / `lookup_binding_sites(ctx, node)` 等辅助，在 `deep_copy_ast_with_params` 与 `deep_copy_ast_with_field_subst` 中共用，避免重复线性查找。

---

## Phase 3：测试

### 3.1 新增测试

- [ ] 新增 `tests/test_macro_hygiene.uya`：
  - [ ] 用例 1：宏体内声明 `var tmp` 并使用 `tmp`，调用处也有 `tmp`；断言展开后宏生成的代码与调用处 `tmp` 不冲突（例如返回值或副作用符合预期）。
  - [ ] 用例 2：宏体内有 `var x`，调用处传入实参且也有外层 `x`；断言宏参数仍被实参替换、宏内 `x` 被重命名、调用处对 `x` 的引用仍指向外层。
  - [ ] 用例 3：宏体内 `catch |err| { ... }` 与调用处同名 `err` 不互相干扰，验证 catch 绑定点纳入 hygiene。
  - [ ] 用例 4：顶层有 `const info = @mc_type(T)`，内层再声明同名 `var info`；断言内层 `info` 仍被重命名，验证 `local_bindings` 排除按节点而非按名字工作。
  - [ ] 用例 5：同一宏在同一文件内展开两次，两次展开中宏内局部变量互不影响（例如两次各声明并使用的局部变量不互相覆盖）；通过返回值或可观测行为验证（如两次调用各自返回预期值、无互相干扰）。
- [ ] 运行 `make check` 与 `./tests/run_programs_parallel.sh --uya --c99 test_macro*.uya`，确保所有现有宏测试仍通过。

---

## Phase 4：文档

### 4.1 语言规范

- [ ] 在 [docs/uya.md](uya.md) 宏系统章节（§25）中增加“卫生宏”小节：说明宏体内引入的变量/循环变量/函数参数/`catch` 错误变量会做卫生重命名，避免与调用处名字捕获；宏参数与 `const x = @mc_eval/@mc_type` 的语义不变；`fn_decl_name` 首版保持原样；生成名格式可注明（如 `__hyg_<expansion>_<id>`）。

### 4.2 语法规范文档

- [ ] 在 [docs/grammar_formal.md](grammar_formal.md) 中补充卫生宏相关说明：宏展开阶段对宏体内绑定的标识符进行卫生重命名的语义规则（可与 uya.md §25 对应）；若要宣称生成名“绝不与用户代码冲突”，需同步保留 `__hyg_` 前缀，否则仅表述为实现约定。
- [ ] 若 [docs/grammar_quick.md](grammar_quick.md) 有宏系统速查，可增加一句“宏为卫生宏，宏内引入的名字不与调用处冲突”的说明。

### 4.3 与主待办集成

- [ ] 在 [docs/todo_mini_to_full.md](todo_mini_to_full.md) 中增加“卫生宏”已实现项（或链接到本 todo），便于主待办跟踪。

---

## 验收清单

- [ ] 现有所有宏测试（test_macro*.uya）通过。
- [ ] test_macro_hygiene.uya 中五则用例通过。
- [ ] uya.md §25 包含卫生宏说明。
- [ ] grammar_formal.md（及可选 grammar_quick.md）已更新卫生宏相关描述。
- [ ] make check 通过。
