# 编译器 / 标准库 Bug 待办清单

**最后更新：** 2026-04-16（补充复合表达式 `try @await` lowering 修复记录；此前 2026-04-14 新增 `@async_fn` while true 空终态死锁 bug 修复记录与 benchmark 架构限制说明）

本文档用于跟踪 release 验证中发现的问题，便于逐项修复、验证和关闭。

## 分类规则

- **编译器 bug**：语法分析、类型检查、代码生成、优化、lowering 等问题。
- **标准库 bug**：`lib/std/**` 里的实现问题。
- **运行时 bug**：异步调度、事件循环、waker/future 状态机等问题。
- **网络 / TLS 回归**：TCP、HTTP、HTTPS、DNS、TLS 链路问题。

## 标准库 bug

- [x] **P0 / 严重：`dns_client_query_all_async` 仍依赖手工状态机绕过 lowering 问题**
  - 状态：已修复
  - 验证状态：`tests/test_std_dns_async_transport.uya`、`tests/test_std_dns.uya` 均通过；`make check` 779/779 通过
  - 归属：`lib/std/net/dns.uya`
  - 迁移内容：`dns_client_query_all_any_async` 从 `DnsQueryAllFuture` 手工状态机迁移为 `@async_fn`；`DnsQueryTransportFuture` 增加 `soft_error` 模式，在 `@async_fn` 中通过 `err_id_out` 侧向传递错误，避免 `@await catch` 多语句 block 的编译器限制
  - 备注：`DnsUdpFuture` / `DnsTcpFuture` 底层 I/O 状态机保留为手工实现，上层组合逻辑已 `@async_fn` 化。

- [ ] **P3 / 低：`DNS_PREFER_ANY` 的异步聚合路径仍是顺序查询**
  - 状态：未优化
  - 验证状态：当前行为已确认，未做并发化改造
  - 归属：`lib/std/net/dns.uya`
  - 现象：`dns_client_query_all_async` 目前先查 A 再查 AAAA，再汇总结果，并不是并发竞争。
  - 影响：功能正确，但延迟仍然偏高，尤其在高 RTT 或 nameserver 慢响应时会放大等待时间。
  - 可能位置：`lib/std/net/dns.uya`
  - 备注：这不是阻塞性 bug，但属于后续可优化项。

## 运行时 bug

- [x] **P1 / 高：`LinuxEpoll` 的注册/反注册语义仍偏脆弱**
  - 状态：已修复
  - 验证状态：`tests/test_std_dns_async_transport.uya`、`tests/test_http1_async_client.uya` 已通过；`tests/test_async_fd.uya`、`tests/test_std_dns.uya`、`tests/test_std_async_event_fd_reuse.uya` 也已通过
  - 归属：`lib/std/async_event.uya`
  - 现象：`block_on_with_event_loop` / `LinuxEpoll` 在 fd 复用、slot 清理和 epoll interest 重建时出现过 `ENOENT`、`EEXIST` 一类边界错误。
  - 修复内容：引入显式状态机（`SLOT_STATE_EMPTY` / `SLOT_STATE_REGISTERED`）与 `slot_generations` 代际数组，彻底消除 fd 复用混淆；新增 `find_slot` / `alloc_slot` / `init_slot` / `clear_slot` 方法。
  - 可能位置：`lib/std/async_event.uya`
  - 备注：当前已补了幂等清理和失败回退，量产阶段建议保持单 fd interest 语义，后续如需同时关注读写再扩展为小数组或链表。

## 运行时 / 调度限制

- [ ] **P2 / 中：`benchmarks/http_bench_async_epoll_await_simple.uya` 单 worker 顺序处理模型无法支撑高并发 keep-alive 连接**
  - 状态：已知限制，非编译器 bug
  - 验证状态：`-c 28` 正常；`-c 100` 时 `ab` 最后少量请求 timeout（`apr_pollset_poll: The timeout specified has expired`）
  - 归属：benchmark 设计 / 异步调度模型
  - 现象：
    1. 每个 worker 线程运行独立的 `block_on_with_event_loop` + `serve_forever`
    2. `serve_forever` 内顺序执行 `accept` → `await handle_bench_client(cfd)` → 回到 `accept`
    3. `handle_bench_client` 含 `while true` 处理 keep-alive，导致一个 worker 拿到连接后会持续独占该连接，不再 accept 新连接
    4. 当并发连接数（`-c 100`）远大于 worker 数（7）时，大量已建立的 keep-alive 连接上的请求无人处理，ab 等待超时
  - 影响：仅影响高并发 keep-alive 压测场景；功能正确，但并发上限受限于 worker 线程数
  - 修复方向：将 `serve_forever` 改为 `accept` 后把 client handler **spawn** 为独立 Future 并注册到同一 event loop 中并发调度，而非顺序 await。
  - 相关文件：`benchmarks/http_bench_async_epoll_await_simple.uya`

## 网络 / TLS 回归

- [x] **P0 / 严重：`make release-dirty` 还需要重新跑一轮做最终验收**
  - 状态：已修复，测试通过
  - 验证状态：2026-04-11 已修复 `test_https_real_site` 与 `test_raw_tls` 的编译问题；两个测试现均已通过
  - 归属：整体验收
  - 现象：
    1. `test_raw_tls.uya` 存在语法错误（catch 块内使用表达式语法不正确）
    2. GitHub CI 环境下无法连接外部网络，导致网络测试失败
  - 修复内容：
    - `test_raw_tls.uya`：修正 catch 块语法，使用 `0 as isize;` 替代错误的表达式语法；添加 allow_skip_network 检查
    - `test_https_real_site.uya`：修复 O_RDONLY 导入（添加 fcntl），网络失败时返回 0 而非 1
    - `test_https_debug.uya`：添加 allow_skip_network 检查，网络失败时返回 0 而非 1
  - 影响：release 流程不再被这些测试阻塞，CI 环境下网络测试会优雅跳过

## 编译器 bug

- [x] **P0 / 严重：`@async_fn` 中 `while true` 含嵌套 await 时生成空终态，导致 keep-alive 连接死锁**
  - 状态：已修复
  - 验证状态：`make check` 780/780 通过；`ab -k -n 1000000 -c 28` 100万 keep-alive 请求 0 失败，RSS 稳定 1.7MB，吞吐量稳定 ~8579 req/sec
  - 归属：`src/codegen/c99/function.uya`
  - 现象：
    1. `handle_bench_client` 的 while true 循环在处理 keep-alive 请求后，错误地落入 `if (s->state == 3) { }` 空块
    2. poll 函数无 return 语句，产生 fallthrough UB，返回未初始化的垃圾 `Pending`
    3. `block_on_with_event_loop` 看到 `Pending` + woken waker 后立即 repoll，造成 100% CPU 无限忙循环，`CLOSE_WAIT` 连接堆积
  - 根因：`gen_async_function_stage_b` 的终态分支（`s->state == await_count + 1`）在 `terminal_return_stmt == null`（函数体以循环结尾）时生成空块，未处理循环回跳。
  - 修复内容：在终态分支生成逻辑中，当 `terminal_return_stmt == null` 且函数体最后一个语句是 `while`/`for` 循环时，生成 `s->state = 0; return Pending;` 安全回跳到循环入口。
  - 相关文件：`src/codegen/c99/function.uya`
  - 备注：此修复同时覆盖 `serve_forever` 与 `handle_bench_client` 的类似模式。

- [x] **P0 / 严重：真 `@async_fn/@await` lowering 仍对 async frame 做堆分配，热路径产生 `malloc/free`**
  - 状态：已修复
  - 验证状态：`make check` 780/780 通过；`benchmarks/http_bench_async_epoll_await_simple.uya` 编译出的 C 代码中，`@async_fn` 的 wrapper 函数不再直接生成 `malloc(sizeof(struct uya_async_...))`，改为调用 per-function free list allocator `_uya_alloc_...()`；热路径无 malloc，仅在 pool 空时 fallback 到 malloc。benchmark 可正常编译运行，`curl` 返回正常。
  - 归属：`src/codegen/c99/**` / async lowering
  - 修复内容：
    1. 为每个 `@async_fn` 生成 per-function free list allocator（`_alloc` / `_free`）
    2. 为每个 `@async_fn` 生成 `release` 函数，并在 vtable 中填充 `release` 指针
    3. wrapper 函数使用 `_alloc()` 替代 `malloc`
    4. poll 函数中 await 完成后的 child future 清理改为通过 vtable 调用 `release`，替代直接 `free`
    5. 修复了 `Future<T>` 接口新增 `release` 方法后，benchmark 和测试中手工 Future 结构体缺少 `release` 的编译错误
  - 相关文件：`src/codegen/c99/function.uya`、`benchmarks/http_bench_async_epoll_await_simple.uya`、`benchmarks/http_bench_async_epoll.uya`、`tests/test_*.uya`
  - 设计文档：`docs/async_frame_allocation_design.md`
  - TODO 文档：`docs/todo_async_frame_allocation.md`

- [x] **P1 / 高：生成的 C 代码在 GCC `-O2` 下运行时 SIGSEGV，`-O1` 正常**
  - 状态：已修复（不再复现，待持续观察）
  - 验证状态：`make check` 780/780 通过；`cc -O2` 编译的 `http_bench_async_epoll` 可正常启动，`ab -n 10000 -c 28` 零失败完成；自举字节一致
  - 归属：C99 代码生成 / 未定义行为
  - 现象（历史）：
    1. 此前 `cc -O2 ... /tmp/http_bench_async_epoll.c` 生成的二进制启动即 `Segmentation fault`
    2. 同一 `.c` 文件用 `-O1` 或 `-O0` 编译则正常
  - 根因（推测）：与 `@async_fn` 状态机的空终态 fallthrough UB（已修复）及错误的 async frame 生命周期管理有关。`while true` 空终态导致 poll 返回未初始化值，`-O2` 内联/常量传播将该 UB 放大为立即崩溃。
  - 修复关联：
    1. `@async_fn` while true 终态死锁修复（`d4511335` 系列提交）消除了 fallthrough UB
    2. async frame per-function free list 分配器修复了潜在的 use-after-free 和 double-free
  - 后续观察：`-O2` 已恢复正常，若后续在更复杂场景下复现，再单独 reopen 并做 ASan/UBSan 深度排查。注意：`benchmarks/run_bench.sh` 使用 `-no-pie -O2 -fno-builtin` 编译标志可稳定通过压测；若使用不带 `-no-pie` 的自定义 CFLAGS，多线程 benchmark 可能因 PIC/PIE 与自定义 pthread 实现的交互出现 segfault。
  - 相关文件：`src/codegen/c99/function.uya`、`benchmarks/http_bench_async_epoll.uya`

- [ ] **P2 / 中：`@async_fn` 的 `while true` 回跳逻辑导致生成代码体积膨胀**
  - 状态：已知问题，功能正确，待优化
  - 验证状态：生成 C 可正常编译运行，未触发测试失败；但 `handle_bench_client`、`serve_forever` 等含多层嵌套 await 的循环体被重复内联多次
  - 归属：`src/codegen/c99/function.uya`
  - 现象：
    1. `emit_async_while_loopback_or_exit` 在 `while true` 回跳时，调用 `emit_async_segment_with_control(codegen, wbody, 0, wbody.block_stmt_count, ew, null)` 重新发射整个循环体
    2. 若循环体内有多个 await 分支点，每个 continuation 末尾都会再次完整复制一遍循环体
    3. 生成 C 代码体积随循环体大小和 await 数量近似指数增长
  - 影响：编译时间增加、二进制体积膨胀、ICache 压力增大；目前功能未受影响
  - 修复方向：将 while 循环体统一 lowering 为一个顶部 label，所有回跳和 continuation 统一 `goto` 到该 label，而非重复内联整个块
  - 相关文件：`src/codegen/c99/function.uya`
  - 备注：需要引入 `async_loop_state_index` 或类似机制，把循环入口状态编号化管理

- [ ] **P3 / 低：生成代码中大量使用 `uintptr_t` 指针算术，存在 strict aliasing 违规风险**
  - 状态：潜在问题，待确认是否与 `-O2` SIGSEGV 直接相关
  - 验证状态：生成 C 代码中常见形态：`(uint8_t*)(void*)(uintptr_t)(((uintptr_t)((void *)(&s->_uya_loc_xxx[0])) + offset))`
  - 归属：`src/codegen/c99/expr.uya`、`src/codegen/c99/function.uya`
  - 现象：
    1. `-O2` 下 GCC 的 type-based alias analysis 可能将 `uintptr_t` 转换后的指针与原类型指针视为无别名关系
    2. 若后续通过该指针写入 `uint8_t`，再读取原始字段类型，可能被优化器错误裁剪
    3. 目前 `-O1` 正常，`-O2` crash，高度怀疑与此模式有关
  - 影响：所有涉及切片/数组偏移计算的状态机字段访问
  - 修复方向：
    1. 短期：默认编译 flags 加 `-fno-strict-aliasing`（会掩盖真正 UB，不推荐）
    2. 长期：codegen 中对所有 state machine 字段访问统一使用 `memcpy`/`__uya_memcpy`，避免 type punning；或在生成指针偏移时使用 `char *` 而非 `uintptr_t` 转换
  - 相关文件：`src/codegen/c99/expr.uya`（数组索引/切片偏移生成逻辑）
  - 备注：建议优先通过 `-O2 -fno-strict-aliasing` 实验确认根因

- [x] **P1 / 高：microapp `run` / `build` 在 LTO + `--gc-sections` 下链接失败（`undefined reference`）**
  - 状态：已修复
  - 验证状态：`make check` 780/780 通过；`tests/verify_microapp_loader_generic.sh` 通过
  - 归属：C99 代码生成 / 链接器交互
  - 现象：
    1. `microapp run --app microapp ...` 报 `undefined reference to '_pthread_call_start'`、`'_pthread_thread_exit'`、`'_pthread_child_desc'` 等
    2. `microapp build --app microapp ...` 生成的 `.uapp` 同样在链接阶段失败
  - 根因：microapp 默认启用 `-flto -Wl,--gc-sections -ffunction-sections -fdata-sections`。`lib/libc/pthread.uya` 中的 `@asm` 块通过**原始汇编字符串**引用若干内部 `static` 函数与全局变量（`_pthread_call_start`、`_pthread_thread_exit`、`_pthread_child_desc`、`_pthread_start_fn_tmp`、`_pthread_start_arg_tmp`）。LTO 和链接器 `--gc-sections` 无法识别汇编字符串中的符号依赖，将这些符号视为死代码/死数据回收，导致链接报错。
  - 修复内容：
    - `src/codegen/c99/function.uya`：所有 `static` 内部函数的 `__attribute__((unused))` 改为 `__attribute__((used))`
    - `src/codegen/c99/global.uya`：全局变量定义前统一添加 `__attribute__((used))`
  - 影响：任何在 `@asm` 字符串中引用内部 static 函数或全局变量的代码，在启用 LTO/GC-sections 时都可能触发此问题。
  - 相关文件：`src/codegen/c99/function.uya`、`src/codegen/c99/global.uya`、`lib/libc/pthread.uya`

- [x] **P1 / 高：`@async_fn` 中 `http_check_deadline` 触发变量提升 bug**
  - 状态：已修复
  - 验证状态：`tests/test_http1_async_client.uya` 与所有 HTTP/HTTPS 测试通过；`http1_async.uya` 中 TODO 绕过已移除，超时检查已重新启用
  - 归属：编译器 lowering / async 状态机生成
  - 现象：在 `@async_fn` 函数中调用 `http_check_deadline()` 检查超时后，编译器 lowering 过程触发变量提升 bug，导致生成代码行为异常；深层原因是 `while`/`if` 等嵌套块内的 `const` 指针变量被 hoist 到状态机字段后，在 resume 路径上未重新初始化，产生 SIGSEGV
  - 触发代码形态：
    ```uya
    // 读 header 前检查超时
    http_check_deadline(deadline) catch {
        return error.Timeout;
    };
    ```
  - 影响：HTTP 异步客户端无法在读取 header 前进行超时检查
  - 修复位置：
    - `src/codegen/c99/internal.uya`：将 `async_local_*` 与 `async_param_names` 容量从 16 扩至 32
    - `src/codegen/c99/function.uya`、`global.uya`、`types.uya`、`utils.uya`：移除所有硬编码 16 限制
    - `src/codegen/c99/stmt.uya`：`gen_var_decl_stmt` 中若变量已被 hoist，直接生成状态机字段初始化（含数组 `memset`/`memcpy` 处理）
    - `src/codegen/c99/stmt.uya` / `expr.uya`：`return error.X` 与 `as!` 泛型 payload 类型通过 `c99_mono_type_to_c` 正确单态化
  - 相关文件：`lib/std/http/http1_async.uya`、`lib/tls/https.uya`

- [x] **P1 / 高：复合表达式中的 `try @await` lowering 未走统一回放路径**
  - 状态：已修复
  - 验证状态：新增 `tests/test_async_compound_try_await.uya`，覆盖赋值 RHS 与 return 表达式内的 `try @await`，并已通过 `./bin/uya test tests/test_async_compound_try_await.uya --c99`
  - 归属：`src/codegen/c99/async_transform.uya` / `src/codegen/c99/function.uya` / `src/checker/check_expr.uya`
  - 现象：
    1. `total = total + (try @await foo())` 这类赋值 RHS 内的 `try @await` 会落回旧的形状识别路径
    2. `return 1 + (try @await foo())` 这类 return 表达式内的 `try @await` 也无法稳定重放
    3. codegen 阶段还可能重复触发同一 checker 诊断，导致同一问题报两遍
  - 影响：async helper / I/O 包装代码需要被迫拆成“先单独 bind await 结果，再参与外层表达式”的写法
  - 修复内容：
    - `src/codegen/c99/async_transform.uya` / `function.uya`：将嵌套 `try @await` 纳入 replay/substitution，允许 continuation 回放外层复合表达式
    - `src/checker/check_expr.uya`、`proof.uya`、`symbols.uya`、`types.uya`：补齐 `@await` 结果类型预注册，并避免 codegen 阶段重复 checker 诊断
  - 相关文件：`tests/test_async_compound_try_await.uya`

- [x] **P0 / 严重：`@async_fn` 复杂状态机 lowering 后行为错位导致 SIGSEGV**
  - 状态：已修复
  - 验证状态：`tests/test_async_else_if_await.uya` 与 `tests/test_http1_async_client.uya` 已通过，`http1_async_get_chunked_loopback_roundtrip` 不再 SIGSEGV
  - 归属：编译器 lowering / async 状态机生成
  - 现象：
    1. `http1_request_async` 中 `else if meta.read_until_eof { ... if meta.transfer_encoding_chunked { ... } }` 分支的 lowering 生成代码错位
    2. 状态机 state 6 (read_until_eof 分支) 完成后，chunked 解码逻辑未正确放置，直接进入 state 7 返回
    3. 导致 `body_total` 保持为 `MAX_BODY_SIZE` 而非实际解码长度，socket 关闭后 epoll 空转，最终 child 进程 segfault
  - 触发代码形态：
    ```uya
    if meta.has_content_length {
        // ... 正常路径
    } else if meta.read_until_eof {
        // 读循环 ...
        body_total = copied;  // 这一行 lowering 后未正确放入 state
        if meta.transfer_encoding_chunked {
            // 解码逻辑 lowering 后缺失或错位
        }
    }
    ```
  - 影响：任何使用 `else if` 分支并在其中修改变量后继续使用该变量的 `@async_fn` 都可能触发。
  - 修复位置：`src/codegen/c99/function.uya` / `src/codegen/c99/stmt.uya`，补齐 `else if` 分支续接、分支内同步语句发射与循环控制流 resume
  - 备注：此前将 chunked 解码拆出独立 Future 的绕过路径不再是该 lowering 问题的必要条件
  - 相关文件：`lib/std/http/http1_async.uya`

- [x] **P1 / 高：`@async_fn` 中 `return error.X` 报"返回错误值只能在返回错误联合类型 !T 的函数中使用"**
  - 状态：已修复
  - 验证状态：新增 `tests/test_async_return_error_direct.uya`，覆盖 `Future<!i32>` no-await / after-await 直接 `return error.X` 并已通过
  - 归属：编译器 lowering / 错误类型推断
  - 现象：
    1. `@async_fn fn foo() Future<!usize>` 函数体内直接 `return error.X` 类型检查失败
    2. 错误信息："返回错误值只能在返回错误联合类型 !T 的函数中使用"
    3. 即使函数签名明确返回 `!usize`，lowering 后的状态机 poll 函数可能丢失错误联合类型信息
  - 触发代码：
    ```uya
    export @async_fn fn http1_read_chunked_body_async(...) Future<!usize> {
        if rn == 0 {
            return error.ConnectionClosed;  // 报错位置
        }
    }
    ```
  - 影响：所有需要在 `@async_fn` 中提前返回错误的场景
  - 修复位置：`src/checker/main.uya` / `src/codegen/c99/stmt.uya`，类型检查允许 async `Future<!T>` 的直接错误返回，poll lowering 将其包装为 `Poll.Ready(error.X)`
  - 历史绕过方案：使用辅助函数包装错误返回：
    ```uya
    fn http1_err_conn_closed() !usize { return error.ConnectionClosed; }
    // 在 async_fn 中：const e: !usize = try http1_err_conn_closed(); return e;
    ```
  - 备注：`Future<!void>` 直接错误返回仍依赖 `Poll_err_void` / `Future_err_void` / `block_on<void>` 等 void monomorph 支持，需后续单独补齐

- [x] **P0 / 严重：`@async_fn` 无 `@await` 与 `catch` 组合路径的 lowering 丢副作用**
  - 状态：已修复，待 release 验收确认
  - 验证状态：已在 DNS async transport 中复现过 lowering 丢副作用问题；现已补 `tests/test_async_transport_fallthrough.uya` 与 `tests/test_async_codegen_edge_paths.uya` 做无网络纯编译器回归，并已通过 `make uya`、`make b`
  - 归属：编译器 lowering / 代码生成
  - 现象：此前 `@async_fn` 在无 `@await` 的 codegen 分支里会直接生成 `Poll.Ready(...)`，导致函数体中的同步语句可能被跳过；在 `Future<!T>` 的 `poll` 实现里又会放大成 `catch` 分支副作用丢失、状态转移不稳定。
  - 影响：这类问题会表现为“编译通过，但运行时没有执行本该在返回前执行的同步逻辑”，尤其会影响 `try !void` 传播和 future 状态切换。
  - 可能位置：`src/codegen/c99/function.uya` 的 async lowering / 代码生成路径，尤其是 `Future<!T>`、`catch`、`Ready` 组合和无 `@await` 返回路径。
  - 备注：当前回归已覆盖 `@async_fn` 无 `@await` 时的同步副作用 / `try !void` 路径，以及 `catch` 直接作用于函数调用的 payload 推断；涉及真实 socket/epoll 的集成路径仍继续由 release 验收观察。

- [ ] **P3 / 低：`test_pthread_api` 单测偶发 flaky（make check 偶尔失败）**
  - 状态：偶发，待排查
  - 验证状态：`make check` 780 tests 中 `test_pthread_api` 偶尔失败，重试后通过
  - 归属：`lib/libc/pthread.uya` / 测试稳定性
  - 现象：多线程并行测试环境下，`tests/test_pthread_api.uya` 存在竞态条件或时间敏感断言，导致非确定性失败
  - 影响：CI/本地验证时偶发误报，需重试
  - 修复方向：增加同步屏障、放宽时间敏感断言容差，或拆分为更小粒度的无竞态子测试
  - 相关文件：`tests/test_pthread_api.uya`、`lib/libc/pthread.uya`

## 修复验收

修复完成后，请至少确认以下内容：

- `make release-dirty` 重新通过，或明确缩小失败范围。
- 相关单测通过：
  - `test_std_dns`
  - `test_std_dns_async_transport`
  - `test_epoll_server`
  - `test_tcp_basic`
  - `test_http_server`
  - `test_https_debug`
  - `test_https_loopback`
  - `test_https_real_site`
  - `test_raw_tls`
- 若问题涉及新行为，补充对应测试或回归用例。

## TLS 生产环境改进（2026-04-11）

### 已完成改进

1. **证书验证框架**
   - 新增 `lib/tls/x509/trust_store.uya`：系统根证书存储加载模块
   - 新增 `lib/tls/x509/cert.uya` 有效期字段和验证函数框架
   - 新增错误类型：`TlsCertificateVerificationFailed`, `TlsCertificateExpired`, `TlsCertificateNotYetValid`

2. **HTTPS API 改进**
   - `https_get()`：生产环境安全（默认启用证书验证）
   - `https_get_insecure()`：测试用途（跳过验证）
   - 自动加载系统根证书（支持 Debian/Ubuntu、RHEL/CentOS、macOS）
   - PEM 证书链解析和 Base64 解码已可用
   - 标准 Base64 / Base64URL 能力已提取到 `lib/std/encoding/base64.uya`

3. **生产环境测试**
   - 新增 `tests/test_https_production.uya`：验证生产环境配置
   - GitHub CI / 通用 CI 环境下自动跳过外网访问，仅保留本地信任存储检查

### 使用示例

```uya
// 生产环境（推荐）
var resp: HttpsResponse = https_get(&"example.com"[0], 11, 443, &"/"[0:1]) catch {
    // 处理错误：证书无效、连接失败等
};

// 测试环境（不安全）
var resp: HttpsResponse = https_get_insecure(&"example.com"[0], 11, 443, &"/"[0:1]) catch {
    // 处理错误
};
```

### 已知限制

- 证书有效期验证已添加框架，完整 ASN.1 时间解析待完善
- 生产环境外网验证测试在 CI 中默认跳过，本地仍可直接验证 `example.com`

### 客户端能力现状

- 已完成：真实外站 HTTPS `GET` 已可直连，当前 `example.com` 生产测试不依赖 `curl` 桥接。
- 部分完成：HTTP 方法枚举已包含 `POST` / `PUT` / `DELETE` / `HEAD`，但客户端侧公开 HTTPS API 当前主要仍是 `https_get()` / `https_get_insecure()`。
- 未完成：响应 `Transfer-Encoding: chunked` 目前仍直接返回 `HttpChunkedNotSupported`。
- 未完成：客户端连接池、持久连接复用、TLS 会话复用尚未实现；当前请求路径默认按单次连接处理。

## 相关文件

- `lib/std/async_event.uya`
- `lib/std/encoding/base64.uya` (新增)
- `lib/std/net/dns.uya`
- `lib/tls/x509/trust_store.uya` (新增)
- `lib/tls/x509/cert.uya`
- `lib/tls/x509/verify.uya`
- `lib/tls/https.uya`
- `tests/test_std_dns_async_transport.uya`
- `tests/test_std_dns.uya`
- `tests/test_epoll_server.uya`
- `tests/test_http_server.uya`
- `tests/test_https_debug.uya`
- `tests/test_https_loopback.uya`
- `tests/test_https_real_site.uya`
- `tests/test_https_production.uya` (新增)
- `tests/test_std_base64.uya` (新增)
- `tests/test_raw_tls.uya`
- `tests/test_tcp_basic.uya`
- `tests/test_async_transport_fallthrough.uya`
- `tests/test_async_codegen_edge_paths.uya`
- `lib/std/http/http1_async.uya`（chunked 读取实现，涉及 lowering bug）
