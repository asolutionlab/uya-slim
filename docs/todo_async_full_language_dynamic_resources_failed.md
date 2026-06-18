# Uya 异步生产化 TODO 失败归档

## 2026-06-18 归档清理

上下文：`# Uya 异步生产化 TODO（完整语法 + 动态资源）` / `## 先澄清边界`
父级任务：`[ ] “完整 Uya 语言语法”指的是：**凡是同步函数体里合法的 Uya 语法，放进 @async_fn 后也应合法并按同样语义工作**，除非语言规范本来就明确禁止。`

  - [f] 建立 async 函数体错误处理覆盖测试；最小验证：`../uya/bin/uya test <新增测试>`；完成条件：`try`、`catch`、错误返回和 `!T` 组合在 `@async_fn` 中与同步函数一致。
    - 失败原因：主 TODO 中遗留 `[f]` 状态，但未附带具体失败详情；本轮为归档清理轮，按约束未启动实现、未重新运行验证。
    - 阻塞命令：无；本轮未执行新增测试验证命令。
    - 后续重开条件：重新创建待执行任务，补充或重建覆盖 `try`、`catch`、错误返回和 `!T` 的 async 错误处理测试，并使用 `../uya/bin/uya test <新增测试>` 验证。

## 完成定义

父级任务路径：有一套从单测、`--uya --c99` 回归、长压测到 `make backup-all` 的完整闸门：

- [f] 有一套从单测、`--uya --c99` 回归、长压测到 `make backup-all` 的完整闸门：
  - [f] 执行完整闸门到 `make backup-all` 并归档最终验证结果；最小验证：`bash tests/verify_async_full_dynamic_resources_gate.sh`。
    - 验证命令：
      - `bash tests/verify_async_full_dynamic_resources_gate.sh`
      - `bash tests/verify_async_full_dynamic_resources_gate.sh backup-all`
      - `bash tests/verify_c99_struct_array_and_typed_route_regressions.sh`
    - 已通过阶段：
      - async await/param/frame pool/thread pool/event/multi-fd dynamic capacity 单测与固定容量扫描。
      - C99 async frame descriptors、empty descriptors、nested split-C codegen。
      - http async epoll C99 compile/runtime verify。
      - `tests/stress_pthread.sh 100`：`ok: 100 iterations`。
      - `tests/stress_epoll_server.sh 100`：`ok: 100 iterations`。
      - `tests/stress_http_async_epoll.sh 1800 1`：`wrk` 退出码 0，733048864 requests，RSS 4804/4948/4948 KB，FD 159/159/159。
    - 本轮已修正但未完成最终闸门：
      - `Makefile`：`check` 增加 `uya` 前置依赖，使 `make backup-all` 从 `make clean` 后可先恢复/构建 `bin/uya`。
      - `tests/verify_async_full_dynamic_resources_gate.sh`：仅在直接运行 `unit-scan`/`c99-stress` 阶段前要求编译器存在，允许 `backup-all` 子阶段从 clean 状态交给 `make` 构建。
      - 修正后 `bash tests/verify_async_full_dynamic_resources_gate.sh backup-all` 已越过缺失编译器问题，证明优化、顶层函数发射、async split-C、frame descriptor、split-C cache、check CLI、UPM、exec VM、microapp、SIMD select、切片形参等阶段通过。
    - 失败原因：
      - `make backup-all` 的 `make check` 后段失败于 `tests/verify_c99_struct_array_and_typed_route_regressions.sh`。
      - 聚焦复现命令 `bash tests/verify_c99_struct_array_and_typed_route_regressions.sh` 稳定失败。
    - 关键错误：
      - `/tmp/.../typed_route.c:21770:51: error: invalid initializer`
      - 生成形态：`struct err_union_int32_t _uya_try_tmp = std_http_uyagin_send_context_response_head_only_async(...)`
      - `/tmp/.../typed_route.c:22587:63: error: invalid initializer`
      - 生成形态：`const int32_t fd = ({ struct err_union_int32_t _uya_try_tmp = std_http_uyagin_accept_async(s->srv); ...`
    - 后续重开条件：
      - 修复 C99 async poll codegen 中 `try @await`/async call 的错误联合拆箱路径，避免把 `Future<!i32>` 直接初始化为 `struct err_union_int32_t`。
      - 先通过 `bash tests/verify_c99_struct_array_and_typed_route_regressions.sh`，再重跑 `bash tests/verify_async_full_dynamic_resources_gate.sh backup-all`；最终再重跑完整 `bash tests/verify_async_full_dynamic_resources_gate.sh`。
