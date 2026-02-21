# Uya 编译器重构 TODO

## 进度概览

```
阶段一：模块拆分    [██████████] 100%
阶段二：内存优化    [ ] 0%
阶段三：性能优化    [ ] 0%
```

## 代码风格规范（强制）

| 规则 | 限制 | 说明 |
|------|------|------|
| 函数行数 | ≤ 50 行 | 超出则拆分为多个函数 |
| 嵌套深度 | ≤ 3 层 | 使用提前返回、提取函数 |
| 单文件行数 | ≤ 2000 行 | 超出则拆分为多个模块 |
| 单一职责 | 每函数做一件事 | 降低 AI 认知负担 |

**重构核心目标**：让 AI 能有效理解和修改代码

---

## 阶段一：模块拆分

### 1.1 checker.uya 拆分

```
[x] 创建 src/checker/ 目录结构
[x] 提取 types.uya (205 行) - 类型定义
    [x] TypeKind 枚举
    [x] Type 结构体
    [x] Symbol/FunctionSignature 等结构体
    [x] TypeChecker 结构体
    [x] 常量定义

[x] 提取 symbols.uya (564 行) - 符号表操作
    [x] hash_string
    [x] checker_init
    [x] symbol_table_lookup/insert
    [x] function_table_lookup/insert
    [x] checker_enter_scope/exit_scope
    [x] str_equals
    [x] 移动语义函数

[x] 提取 type_utils.uya (481 行) - 类型工具函数
    [x] type_equals
    [x] type_to_string
    [x] type_can_implicitly_convert
    [x] is_integer_type/is_float_type/etc.
    [x] type_satisfies_constraint

[x] 提取 lookup.uya (452 行) - 查找函数
    [x] find_struct_decl_from_program
    [x] find_enum_decl_from_program
    [x] find_method_in_struct/union
    [x] find_interface_decl_from_program
    [x] check_drop_method_signature
    [x] struct_implements_interface

[x] 提取 generics.uya (177 行) - 泛型单态化
    [x] register_mono_instance
    [x] substitute_generic_type

[x] 提取 proof.uya (331 行) - 安全证明和错误报告
    [x] 溢出检测函数
    [x] checker_eval_const_expr
    [x] checker_report_error

[x] 提取 type_from_ast.uya (335 行) - 类型解析
    [x] type_from_ast

[x] 提取 check_expr.uya (1465 行) - 表达式检查
    [x] checker_infer_type
    [x] checker_check_expr_type
    [x] copy_type
    [x] find_struct_field_type

[x] 提取 check_stmt.uya (754 行) - 语句检查
    [x] checker_check_var_decl
    [x] checker_check_fn_decl
    [x] checker_check_struct_decl
    [x] checker_check_destructure_decl

[x] 提取 check_call.uya (747 行) - 调用和成员访问检查
    [x] checker_check_call_expr
    [x] checker_check_member_access

[x] 提取 interval.uya (1027 行) - 区间算术和约束系统
    [x] pointer_nonnull_*
    [x] constraint_*
    [x] interval_*
    [x] extract_linear_expr
    [x] verify_linear_expr_bounds

[x] 提取 check_expr_extra.uya (824 行) - 表达式检查辅助
    [x] checker_check_array_access
    [x] checker_check_alignof
    [x] checker_check_len
    [x] checker_check_struct_init
    [x] checker_check_binary_expr
    [x] checker_check_cast_expr
    [x] checker_check_unary_expr
    [x] checker_check (主入口)

[x] 提取 modules.uya (1197 行) - 模块系统
    [x] extract_module_path_allocated
    [x] find_or_create_module
    [x] build_module_exports
    [x] process_use_stmt
    [x] dfs_visit_module
    [x] detect_circular_dependencies

[x] 提取 macro_expand.uya (1168 行) - 宏展开
    [x] find_macro_decl_from_program
    [x] find_param_binding
    [x] create_number_literal/bool_literal/string_literal
    [x] macro_eval_expr
    [x] deep_copy_ast_with_params/simple
    [x] extract_macro_output_*
    [x] expand_macros_in_node_simple

[x] 继续拆分 main.uya (1227 行 -> 610 行)
    [x] 提取 check_match_expr_node
    [x] 提取 check_assign_node
    [x] 提取 check_for_stmt_node

[x] 验证 checker 拆分
    [x] make check 通过 (414/414)
    [x] 每文件 ≤ 2000 行

当前：checker 模块拆分完成！共 16 个文件，10978 行
```

### 1.2 parser.uya 拆分

```
[ ] 创建 src/parser/ 目录结构
[ ] 提取 types.uya (~1000 行)
    [ ] parser_parse_type
    [ ] parse_array_type
    [ ] parse_pointer_type
    [ ] parse_generic_type
    [ ] parse_function_type

[ ] 提取 expressions.uya (~2500 行)
    [ ] parser_parse_expression 主入口
    [ ] parser_parse_primary_expr
    [ ] parser_parse_unary_expr
    [ ] parser_parse_cast_expr
    [ ] parser_parse_mul_expr
    [ ] parser_parse_add_expr
    [ ] parser_parse_shift_expr
    [ ] parser_parse_rel_expr
    [ ] parser_parse_eq_expr
    [ ] parser_parse_bitand_expr
    [ ] parser_parse_xor_expr
    [ ] parser_parse_bitor_expr
    [ ] parser_parse_and_expr
    [ ] parser_parse_or_expr
    [ ] parser_parse_assign_expr
    [ ] parse_integer_literal
    [ ] parse_float_literal
    [ ] remove_underscores

[ ] 提取 statements.uya (~1500 行)
    [ ] parser_parse_statement 主入口
    [ ] parser_parse_block
    [ ] parser_parse_if_stmt
    [ ] parser_parse_while_stmt
    [ ] parser_parse_for_stmt
    [ ] parser_parse_return_stmt
    [ ] parser_parse_var_decl
    [ ] parser_parse_defer_stmt

[ ] 提取 declarations.uya (~1500 行)
    [ ] parser_parse_declaration 主入口
    [ ] parser_parse_function
    [ ] parser_parse_struct
    [ ] parser_parse_method_block
    [ ] parser_parse_enum
    [ ] parser_parse_union
    [ ] parser_parse_union_body
    [ ] parser_parse_interface
    [ ] parser_parse_type_alias
    [ ] parser_parse_macro
    [ ] parser_parse_error_decl
    [ ] parser_parse_use_stmt
    [ ] parser_parse_extern_decl
    [ ] parser_parse_extern_function
    [ ] parser_parse_extern_var_decl
    [ ] parser_parse_export_var_decl

[ ] 创建 main.uya (~700 行)
    [ ] Parser 结构体
    [ ] ParserContext 枚举
    [ ] parser_init
    [ ] parser_parse
    [ ] parser_parse_program
    [ ] parser_match
    [ ] parser_consume
    [ ] parser_expect
    [ ] parser_get_filename
    [ ] parser_peek_is_struct_init
    [ ] parser_peek_is_generic_method_call

[ ] 验证 parser 拆分
    [ ] make check 通过
    [ ] make tests 通过
    [ ] 生成 C 代码一致性检查
```

---

## 阶段二：内存优化

```
[ ] Arena 按需增长
    [ ] 设计 ArenaChunk 结构体
    [ ] 实现 arena_grow 函数
    [ ] 修改 arena_init 支持小初始容量
    [ ] 修改 arena_alloc 支持自动增长
    [ ] 测试验证

[ ] 临时 Arena 优化
    [ ] 分析 temp_arena 使用场景
    [ ] 实现栈分配或复用方案
    [ ] 测试验证

[ ] 大数组动态化
    [ ] main_file_paths_global 动态化
    [ ] resolved_files_global 动态化
    [ ] 测试验证

[ ] 内存占用测试
    [ ] 小程序测试 (< 32MB)
    [ ] 自举测试 (< 128MB)
```

---

## 阶段三：性能优化

```
[ ] 阶段耗时分析
    [ ] 添加 CompileStats 结构体
    [ ] 在各阶段添加计时
    [ ] 输出编译统计信息

[ ] 热点分析
    [ ] 使用 perf 或 gprof 分析
    [ ] 识别热点函数
    [ ] 记录分析结果

[ ] 热点函数优化
    [ ] type_equals 优化
    [ ] symbol_table_lookup 优化
    [ ] checker_arena_strdup 优化
    [ ] 其他发现的瓶颈

[ ] 性能测试
    [ ] 自举编译时间 < 5s
    [ ] 小程序编译时间对比
```

---

## 验收清单

### 阶段一验收
```
[ ] checker.uya 拆分为 7-8 个文件
[ ] 每个文件 < 2000 行
[ ] parser.uya 拆分为 5 个文件
[ ] 每个文件 < 2500 行
[ ] make check 通过
[ ] make tests 通过
[ ] make backup 成功
```

### 阶段二验收
```
[ ] 内存占用 < 128MB
[ ] 小程序内存占用 < 32MB
[ ] make check 通过
```

### 阶段三验收
```
[ ] 自举编译时间 < 5s
[ ] 有性能分析报告
[ ] make check 通过
```

---

## 注意事项

1. **每次拆分后必须验证**：`make check`
2. **小步迭代**：每次只拆一个模块
3. **保留备份**：`make backup` 在每个里程碑后执行
4. **避免循环依赖**：拆分前绘制依赖图
5. **保持函数签名不变**：避免影响其他模块
