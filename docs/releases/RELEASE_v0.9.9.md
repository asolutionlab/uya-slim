# Uya v0.9.9 发布说明

> **类型**：**v0.9.x 发行线上的补丁版本**（patch）
> **发布日期**：2026-05-30

在 **v0.9.8** 将 package mode、`uya check`、第一阶段 exec VM、`std.http.websocket` 与 unknown hosted smoke 收入口径之后，**v0.9.9** 继续沿着“网络标准库可用性 + 编译器主线稳定性”推进：补齐 WebSocket 生命周期与 WSS / JSON 辅助能力，加入 HTTP/2 frame / stream / HPACK 基础栈，并修复 exec VM `catch` lowering 与若干 C99 / checker 回归。

---

## 核心变更

### 1. `std.http.websocket` 生命周期扩展

- `lib/std/http/websocket_async.uya`
- `lib/std/http/websocket_client.uya`
- `lib/std/http/websocket_json.uya`
- `lib/std/http/websocket_tls.uya`
- `lib/std/http/websocket_types.uya`
- `lib/tls/https.uya`
- `examples/uyagin_websocket_*.uya`
- `examples/https_websocket_echo.uya`

本版本继续扩展 WebSocket 主线能力：

- 新增 TLS / WSS loopback transport 骨架与示例；
- 增补 reconnect、heartbeat、heartbeat config、backpressure 与 close/lifecycle 路径；
- 补齐 JSON decode helper 与 typed JSON writer；
- 新增 echo / chat / JSON echo / HTTPS WebSocket 示例；
- 添加 WebSocket echo benchmark 基线与 Go / Uya 对照程序。

新增或扩展的回归包括：

- `tests/test_http_websocket_module_smoke.uya`
- `tests/test_https_websocket_loopback.uya`
- `tests/test_http_websocket_json.uya`
- `tests/test_http_websocket_heartbeat*.uya`
- `tests/test_http_websocket_reconnect.uya`
- `tests/test_http_websocket_backpressure.uya`

### 2. HTTP/2 / HPACK 基础栈落地

- `lib/std/http/http2_types.uya`
- `lib/std/http/http2_frame.uya`
- `lib/std/http/http2_stream.uya`
- `lib/std/http/hpack.uya`
- `lib/std/http/websocket_http2_h3_route.uya`
- `docs/std_http_websocket_http2_http3_route.md`

本版本新增 HTTP/2 frame / stream / HPACK 基础模块，作为后续 RFC 8441 extended CONNECT 与 HTTP/3 / QUIC adapter 的地基：

- 覆盖 frame header、DATA、SETTINGS、WINDOW_UPDATE、HEADERS payload 等基础解析；
- 建立 stream 生命周期与窗口记账模型；
- 实现 HPACK static table、literal、incremental indexing 与 dynamic table 驱逐；
- 保留 `websocket_http2_h3_route` 占位接口，确保 WebSocket frame/message/session 层后续可复用。

新增验证：

- `tests/test_http_http2_frame.uya`
- `tests/test_http_http2_stream.uya`
- `tests/test_http_hpack.uya`
- `tests/test_http_websocket_http2_h3_route.uya`

### 3. 编译器与 exec VM 回归修复

- `src/exec/builder.uya`
- `src/exec/lower.uya`
- `src/checker/check_node_extra.uya`
- `src/codegen/c99/main.uya`
- `src/codegen/c99/structs.uya`
- `src/codegen/c99/types.uya`

本版本修复了几条影响主线验证的回归：

- exec VM `catch` lowering 支持 bare return / empty block 路径，编译器 VM smoke 覆盖更完整；
- double pointer 赋值检查回归补测；
- C99 后端补齐 `Future<!WebSocketConn>` 场景所需的 error-union / struct codegen 路径；
- 继续刷新 backup seed，保持 C99 种子与当前自举源码一致。

新增或扩展验证：

- `tests/test_exec_vm_catch_bare_return.uya`
- `tests/test_exec_vm_catch_empty_block.uya`
- `tests/verify_exec_vm_compiler_regressions.sh`
- `tests/verify_exec_vm_compiler_stage_smoke.sh`
- `tests/test_double_pointer_assign_regression.uya`
- `tests/test_async_future_websocket_conn_codegen.uya`

---

## 升级指南

从 `v0.9.8` 升级到 `v0.9.9`：

```bash
git pull
git checkout v0.9.9

make clean && make release
```

如果重点验证 WebSocket / HTTP/2 / exec VM，可以额外运行：

```bash
./tests/run_programs_parallel.sh test_http_websocket_json.uya test_http_http2_frame.uya test_http_hpack.uya test_exec_vm_catch_bare_return.uya
tests/verify_exec_vm_compiler_regressions.sh
```

---

## 统计与验证

| 项目 | 说明 |
|------|------|
| 相对 `v0.9.8` | 见 `git log v0.9.8..HEAD` |
| 提交前备份 | `make clean && make backup-all` 通过（2026-05-30；Linux / hosted seed 已生成，macOS hosted 交叉 seed 因本机缺少 Zig 仅做版本字符串同步） |
| macOS hosted seed 声明 | `tests/verify_macos_hosted_seed_decls.sh` 通过（2026-05-30） |
| 最终 clean-tree release | `make release` 通过（2026-05-30） |
| 上一标签 | `v0.9.8` |

---

## 致谢

感谢所有为本版本贡献网络标准库、编译器回归修复、测试与发布验证的参与者。

---

**标签**：`v0.9.9`
**下载 / 发行页**：[GitHub Releases](https://github.com/uya-lang/uya/releases/tag/v0.9.9)
**完整变更日志**：[CHANGELOG.md](../../CHANGELOG.md)
