# Uya v0.9.7 发布说明

> **类型**：**v0.9.x 发行线上的补丁版本**（patch）  
> **发布日期**：2026-05-13

在 **v0.9.6** 完成 microapp 结果面、capability 白名单与 hosted/toolchain 发布线收口之后，**v0.9.7** 继续聚焦编译器主线稳定性：修复 interface + error-union lowering 回归，收紧 `drop` 语义为“仅编译器自动插入”，并补齐 union 自定义 `drop` 对当前活跃变体的自动递归清理。

---

## 核心变更

### 1. 修复 interface + error-union lowering 回归

- `src/checker/generics.uya`
- `src/checker/check_expr.uya`
- `src/codegen/c99/expr.uya`
- `src/codegen/c99/types.uya`
- `src/codegen/c99/stmt.uya`

本版本修复了 interface 方法与 error-union 组合场景下的 lowering / 类型替换回归，避免特定组合在 checker 或 C99 后端上出现错误推断与发射不一致。

新增回归测试：

- `tests/test_interface_error_union_method.uya`

### 2. `drop` 不再允许用户手动调用

`drop` 仍然只能声明为 `fn drop(self: T) void`，但从 **v0.9.7** 起进一步明确为：

- `drop(x)`：编译错误
- `T.drop(x)`：编译错误
- `x.drop()`：编译错误

`drop` 只允许由编译器在离开作用域时自动插入，以保证 RAII / move 语义和资源释放路径保持单一、可证明。

涉及实现：

- `src/checker/check_call.uya`
- `src/checker/symbols.uya`

新增错误测试：

- `tests/error_drop_manual_call.uya`
- `tests/error_drop_manual_type_call.uya`

### 3. union 自定义 `drop` 先自动清理当前活跃变体

对 union 值离开作用域时，如果该 union 自身定义了 `drop`，编译器现在会在执行用户 `drop` 函数体之前，先对**当前活跃变体**自动执行递归 `drop`。

这让 union 的 RAII 语义与 struct 的字段递归清理保持一致，也消除了文档中历史遗留的“在用户代码里手动 `drop(f)`”写法。

涉及实现：

- `src/codegen/c99/function.uya`

新增回归测试：

- `tests/test_union_drop_auto_variant.uya`

### 4. 文档口径同步到当前自举状态

- `docs/uya.md`
- `docs/grammar_quick.md`
- `docs/grammar_formal.md`
- `docs/uya_ai_prompt.md`
- `docs/builtin_functions.md`
- `src/README.md`
- `readme.md`

本版本同步清理了 `src/README.md` 中“代码生成阶段进行中（有段错误）”等过期历史描述，使根 README、语言规范、速查与源码目录说明对当前主线状态保持一致。

---

## 升级指南

从 `v0.9.6` 升级到 `v0.9.7`：

```bash
git pull
git checkout v0.9.7

make clean && make check
make b
```

如果你依赖最终发布闸门，建议额外执行：

```bash
make release
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 `v0.9.6` | 见 `git log v0.9.6..HEAD` |
| 自举验证 | `make b` 通过（2026-05-13） |
| 全量回归 | `make check` 通过（2026-05-13） |
| 提交前备份 | `make backup-all` 通过（2026-05-13；含 seed / backup 刷新） |
| 最终 clean-tree release | `make release` 通过（2026-05-13） |
| 上一标签 | `v0.9.6` |

---

## 致谢

感谢所有为本版本贡献代码、测试、发布验证与文档收口的参与者。

---

**标签**：`v0.9.7`  
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.9.7)  
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
