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

- [ ] **嵌套 `while` 内多个 `try @await` 之间的语句未进入 C 状态机（业务语义丢失）**
  - **触发示例**：`benchmarks/http_bench_async_epoll.uya` 中 `@async_fn handle_bench_client`：外层「每请求」循环 + 内层「读满请求头」循环，在**第一次** `read` 就绪与**第一次** `write` 之间存在解析请求行、`build_http_ok_response`、填充 `g_cli_hdr_len` 等语句。
  - **运行时现象**：`curl http://127.0.0.1:8876/` 报 **Empty reply from server (52)**；`strace` 可见 `read` 已收到 `GET / HTTP/1.1...` 后，连续 **`write(fd, "", 0)`**（长度为 0），随后对端读 EOF、`close`。
  - **根因**：`collect_awaits_recursive`（`src/codegen/c99/function.uya`）按 DFS 收集**全部** `try @await` 点；poll 代码在「上一 await Ready」分支里**直接**接下一 await 的 `gen_expr(operand)`，**未发出**相邻 await 之间函数体里的普通语句与副作用，故 `g_cli_hdr_len[slot]` 等仍为 0。
  - **与 `test_async_copy` 的关系**：`async_copy` 走 **`has_await_loop` + `n`/`written`/`total` 特判与循环回跳**；不等价于「任意嵌套循环内 await 间语句均已正确发射」。
  - **验证现状**：`tests/verify_http_bench_async_epoll_compile.sh` 仅验证 **`uya --c99` + `cc -c`**；**不加** `--safety-proof`（脚本注释：`@async_fn` 状态机拆分后 `g_cli_*[slot]` 的支配边界对证明器不可见）。**不**表示运行时 HTTP 正确。
  - **修复方向**：在 await 边界完整发出 CPS 片段（或拆成多段线性子函数/显式状态），并与「循环变量持久化泛化」（见 [todo_async_runtime_and_http.md](todo_async_runtime_and_http.md) P1）统筹。
  - **备注（网络）**：bench 仅 bind **`127.0.0.1`** 时，`curl http://localhost:8876` 先试 **`::1`** 可能出现「拒绝连接」，落到 IPv4 后仍可能因上列 bug 得到 Empty reply，二者需区分。

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
| `benchmarks/http_bench_async_epoll.uya` | epoll + `@async_fn` bench；**运行时 HTTP** 正确性依赖「await 间语句发射」修复；`tests/verify_http_bench_async_epoll_compile.sh` 仅编译 |
