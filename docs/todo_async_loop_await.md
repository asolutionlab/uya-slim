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
| 14 | `for`（范围 / 定长数组）内 `try @await`：收集 `enclosing_for`、发射回跳/退出（`emit_async_for_*`） | ✅ |

---

## 待办

### 高优先级

- [x] **嵌套 `while` 内多个 `try @await` 之间的语句未进入 C 状态机（业务语义丢失）** ✅
  - **修复**：`c99_emit_async_poll_not_last_transition` / `c99_emit_async_while_post_assign_stmts` / `c99_emit_async_tail_stmts_after_last_await` 均改为发射全部语句类型（if/return/表达式等），不再仅限 assign/var_decl。
  - **新增 `async_emit_poll_return` 机制**：inter-await 语句中的 `return expr` 自动包装为 `return Poll::Ready(Ok(expr))`（`gen_return_stmt` 检测 `codegen.async_emit_poll_return`）。
  - **通用 while 多 await 回跳**：新增 `c99_emit_async_while_multi_loopback` + `c99_async_first_await_in_while`，替代旧 `async_loop_var_is_total` 硬编码（已移除 `_uya_total`/`_uya_read_n` 字段与 `n`+`written` 特判）。循环变量通过 `async_local_*`（`s->_uya_loc_*`）通用持久化。
  - **验证**：`make check` 717/717 通过，`make b` 自举一致，`test_async_while_multi_await.uya` 新增覆盖。

- [x] **split 多文件 C 镜像下内部 `@async_fn` 与头文件 `static` 不一致** ✅
  - 现象：`static declaration of '…' follows non-static declaration`（生成的 stage-B 异步包装与 `uya_split_protos.h` 中非 static 原型冲突）。
  - 处理：`src/codegen/c99/function.uya` 在 `split_enabled` 时对有关异步路径**不再误加** `static`，与头文件一致。

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

- [x] **扩展循环变量持久化** ✅
  - 已移除 `n`+`written`+`total` 硬编码；所有函数体顶层 `var` 通过 `async_local_*`（`s->_uya_loc_*`）通用持久化

### async 状态机 lowering（2026-04-03 分析，2026-04 起陆续修复）

**历史根因**：收集与 emit 若只覆盖单一 await 形状或硬编码循环模式，会出现漏语句、错状态号、非法 C。

**当前主路径**：`collect_awaits_recursive` 记录 `enclosing_while` / `enclosing_for`；poll 体由通用段发射与 `emit_async_continuation` 补全（详见 [plan_async_coroutine_transform.md](plan_async_coroutine_transform.md)）。

- [x] **Bug A：两个连续 while+@await 写循环**
  - 现象：第一个循环结束后，第二个循环的状态转移失败 → 运行时挂死
  - 回归：`tests/test_async_bug_a_two_while.uya`
  - 典型场景：先写 header 再写 body（HTTP 客户端）
  ```uya
  while woff < hdr_len {
      const wn = try @await write(fd, hdr_ptr, hdr_len - woff);
      woff += wn;
  }
  while boff < body_len {   // ← 第二个循环的状态转移丢失
      const bn = try @await write(fd, body_ptr, body_len - boff);
      boff += bn;
  }
  ```

- [x] **Bug B：await 循环间的同步代码被吃掉**
  - 状态：已修复
  - 现象：第一个 await 循环结束后的 parse/malloc 等同步语句不进入状态机 → 运行时挂死
  - 回归：`tests/test_async_bug_b_sync_between.uya`
  - 典型场景：读 header → 同步解析 → 读 body
  ```uya
  while !header_done {
      const rn = try @await read(fd, buf, cap);
      // ... set header_done
  }
  const meta = try parse_meta(...);   // ← 此段被吃掉
  while copied < body_len {
      const rn2 = try @await read(fd, ...);
  }
  ```

- [x] **Bug C：`return try @await inner_async_fn(...)` 生成非法 C**
  - 现象：gcc 编译失败 — `inner_async` 被当作同步函数调用
  - 回归：`tests/test_async_bug_c_tail_await.uya`

- [x] **Bug D：分裂点附近局部变量与表达式**（与 A/B 叠加时更易触发）
  - 状态：已修复
  - 回归：`tests/test_async_bug_d_nested_block.uya`
  - `xxx undeclared`：恢复点在 if 内声明的变量未提升到状态结构体
  - `break not within loop`：内层 while 在状态机展开后错位
  - 切片表达式在分裂后生成错误类型
  - 覆盖：嵌套局部变量、`break` / `continue` resume、切片表达式、局部变量 `s` 与 poll state 指针命名冲突

**仍建议关注的方向**：
1. collect/emit 覆盖更多 await 出现位置（assign、bare expr 等）若仍有缺口
2. 迭代器 `for` / `for |&x|` 与 `@async_fn` 组合的 lowering 或明确诊断
3. `Future<!void>` 相关 void monomorph 特化补齐后，再扩展直接 `return error.X` 的覆盖

**验收**：Bug B / Bug D 已转正并通过；全量 `make check` 仍作为 release 闸门执行

### 低优先级

- [x] 计划/设计文档与待办同步（本文件、[plan_async_coroutine_transform.md](plan_async_coroutine_transform.md)、[async_loop_await_design.md](async_loop_await_design.md)）

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
| `test_async_copy.uya` | 循环内 await（async_copy） |
| `test_async_for_await.uya` | 范围 `for` + 定长数组 `for` 内含 `try @await` |
| `test_async_bug_a_two_while.uya` | 连续两个 `while` 内 await |
| `test_async_bug_c_tail_await.uya` | `return try @await` |
| `test_async_bug_b_sync_between.uya` | await 循环间同步语句 |
| `test_async_bug_d_nested_block.uya` | 分裂点附近局部变量、break/continue、切片表达式 |
| `test_async_io.uya` | AsyncReader/AsyncWriter 基础 |
| `test_block_on.uya` | block_on 基础 |
| `test_async_multiple_await.uya` | 多 await 线性 |
| `benchmarks/http_bench_async_epoll.uya` | epoll + `@async_fn` bench；端到端 HTTP 依赖 await 间语句完整发射；verify 脚本多仅编译 |
