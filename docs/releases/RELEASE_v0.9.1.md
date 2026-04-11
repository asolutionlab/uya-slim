# Uya v0.9.1 发布说明

> **类型**：**v0.9.x 发行线上的补丁版本**（patch）  
> **发布日期**：2026-04-12

在 **v0.9.0** 基础上修复编译器 `@async_fn` 状态机 lowering 中的两类关键 bug，并补齐泛型上下文下的错误返回与强制类型转换单态化。`make check` 下 **779** 项测试通过（2026-04-12）。

---

## 核心变更

### 编译器：async 状态机 lowering

#### 1. 变量提升容量不足（16 → 32）

- `src/codegen/c99/internal.uya`：将 `async_local_names` / `async_local_types` / `async_local_inits` / `async_local_root_stmt` / `async_param_names` 容量从 **16** 扩至 **32**。
- `src/codegen/c99/function.uya`、`global.uya`、`types.uya`、`utils.uya`：将所有硬编码 `16` 改为 `@len(...)` 动态上限检查，防止大函数 lowering 时局部变量被静默丢弃。

#### 2. 嵌套块内 hoisted 变量未初始化（SIGSEGV 根因）

- `src/codegen/c99/stmt.uya`：`gen_var_decl_stmt` 在生成 async poll 函数时，若变量已被 hoist 到 `async_local_names`，不再生成普通局部变量声明，而是直接生成状态机字段初始化：
  - 普通类型：`s->_uya_loc_xxx = init_expr;`
  - 数组字面量：`__builtin_memset((void *)&s->_uya_loc_xxx, 0, sizeof(...));`
  - 标识符（数组拷贝）：`__uya_memcpy((void *)s->_uya_loc_xxx, ..., sizeof(...));`
- 这修复了 `while`/`if` 等**不含 `@await` 的嵌套控制流**中的 `const` 指针在 resume 路径上未初始化导致的 null 指针解引用崩溃。

#### 3. 泛型上下文下的类型单态化

- `src/codegen/c99/stmt.uya`：`return error.X` 的 payload C 类型通过 `c99_mono_type_to_c` 解析，避免在泛型 `@async_fn` 中使用未单态化的 `struct err_union_size_t`。
- `src/codegen/c99/expr.uya`：`as!` 强制类型转换的 `value` 字段同样通过 `c99_mono_type_to_c` 处理泛型参数。

### 标准库修复

- `lib/std/http/http1_async.uya`：
  - 移除 `catch { ... }` 块内的多余分号（语法错误）。
  - 重新启用此前被 TODO 绕过的 `http_check_deadline(deadline_ms)` 超时检查（读 header 前、循环读 body 中）。
- `lib/tls/https.uya`：
  - 修复 `catch` 块语法。
  - 修正 `as!` 溢出使用方式：先提取 `!i32` 的 `.value`，再进行位运算与强制转换。

---

## 升级指南

从 v0.9.0 升级到 v0.9.1：

```bash
git pull
git checkout v0.9.1   # 发布打 tag 后

make clean && make check   # 或 make release-dirty 完整验证
```

若依赖单文件种子：提交中包含 **`backup/uya.c`** 时与仓库保持一致。

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 v0.9.0 | 见 `git log v0.9.0..HEAD` |
| 回归测试 | `make check` **779** 项全部通过 |
| 重点验证 | `test_http1_async_client`、`test_https_loopback`、`test_https_production`、`test_https_bridge_safety` 等 14 项 HTTP/HTTPS 测试全部通过 |
| 自举验证 | `make b` 通过，字节一致 |
| 上一标签 | `v0.9.0` |

---

## 致谢

感谢所有为本版本贡献代码、测试与文档的参与者。

---

**标签**：`v0.9.1`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.9.1)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
