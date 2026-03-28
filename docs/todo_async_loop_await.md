# 循环内 await 实现待办

**设计文档**：[async_loop_await_design.md](async_loop_await_design.md)  
**主待办**：[todo_mini_to_full.md](todo_mini_to_full.md) §16 异步编程

---

## 完成状态

| 阶段 | 任务 | 状态 |
|------|------|------|
| 1 | 递归收集 await（collect_awaits_recursive） | ✅ |
| 2 | 识别 `has_await_loop`、`async_loop_var_is_total` | ✅ |
| 3 | `_uya_total` 字段与 `total` 变量映射 | ✅ |
| 4 | 循环回跳逻辑（state 2 → state 1） | ✅ |
| 5 | `return_future_err_union` 放宽判定 | ✅ |
| 6 | `concrete_future_safe` 从 error union payload 提取 | ✅ |
| 7 | `state_slot_iface_c` 正确生成 `Future_usize` | ✅ |
| 8 | await operand try 包装（`await_operand_is_err_future`） | ✅ |
| 9 | `_uya_await_storage` 与复制逻辑（避免悬挂指针） | ✅ |
| 10 | `child_inner_is_err_union==0` 分支的循环与 try 逻辑 | ✅ |
| 11 | await 绑定变量纳入状态机结构体（`_uya_bind_*` 字段） | ✅ |
| 12 | 扩展 `get_c_name_for_identifier_ref` 支持 await 绑定变量引用 | ✅ |
| 13 | 扩展 codegen 追踪 await 绑定变量名 | ✅ |

---

## 待办

### 高优先级

- [x] **test_async_copy 段错误** ✅
  - 现象：`test_async_copy` 运行时 SIGSEGV（已解决）
  - ASan：`stack-buffer-overflow` 于 `block_on_usize_plain` 栈帧（已解决）
  - 验证：`./tests/run_programs_parallel.sh --uya --c99 test_async_copy.uya` 通过

- [x] **验证 Poll 返回类型链** ✅
  - `async_copy` 返回 `!Future<usize>`
  - `block_on_usize_plain(f)` 期望 `Future<usize>`，poll 返回 `Poll<usize>`
  - 确认状态机 poll 实际返回类型与 block_on 期望一致

### 中优先级

- [x] **端到端验证** ✅
  - `./tests/run_programs_parallel.sh --uya --c99 test_async_copy.uya` 通过
  - `make backup` 自举验证通过

- [ ] **扩展循环变量持久化**
  - 当前仅支持 `n`+`written` 的 `total` 模式
  - 支持更泛化的「循环内跨 await 变量」持久化

### 低优先级

- [ ] 文档与注释补充
- [ ] 边界情况测试（多 await、嵌套循环等）

---

## 验证步骤

```bash
# 1. 构建自举编译器
make uya

# 2. 编译测试
UYA_ROOT=lib/ ./bin/uya --c99 -o tests/build/test_async_copy.c tests/test_async_copy.uya

# 3. 编译 C（可选 ASan）
gcc -std=c99 -O2 -o tests/build/test_async_copy tests/build/test_async_copy.c -lm
# gcc -std=c99 -O0 -g -fsanitize=address -o tests/build/test_async_copy tests/build/test_async_copy.c -lm

# 4. 运行
./tests/build/test_async_copy

# 5. 完整测试脚本
./tests/run_programs_parallel.sh --uya --c99 test_async_copy.uya

# 6. 自举验证
make backup
```

---

## 相关测试

| 测试文件 | 说明 |
|----------|------|
| `test_async_copy.uya` | 循环内 await（async_copy），目标通过 |
| `test_async_io.uya` | AsyncReader/AsyncWriter 基础，应保持通过 |
| `test_block_on.uya` | block_on 基础，应保持通过 |
| `test_async_multiple_await.uya` | 多 await 线性，应保持通过 |
