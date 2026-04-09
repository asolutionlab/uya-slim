# TLS 纯 Uya 实现待办文档

本文档为 [tls_uya_design.md](tls_uya_design.md) 的配套待办：按阶段列出任务、验收标准及测试要求。实现时需在 **分支 `feature/tls-pure-uya`** 进行；测试文件位于 **`tests/` 根目录**，命名 `test_tls_*.uya`，且需同时通过 `--c99` 与 `--uya --c99`（参考 [.cursorrules](../.cursorrules) 与 [todo_mini_to_full.md](todo_mini_to_full.md)）。

---

**开发流程（必读）**：TLS 库实现必须按 **[.codebuddy/rules/uya-dev-flow.mdc](../.codebuddy/rules/uya-dev-flow.mdc)** 的开发流程进行，包括但不限于：

- **TDD**：先写测试（红）→ 再写实现（绿）→ 再重构；小步迭代，测试先行。
- **验证**：开发前后使用 `make check`（自举 + 测试）；完成后执行 `make backup`。
- **测试风格**：若项目统一采用 `test "name" {}` 风格，则 TLS 测试与之保持一致；若使用 `export fn main() i32` + `run_programs_parallel.sh`，则保持现有约定，但每个功能均需有对应用例。
- **代码规范**：函数 ≤50 行、嵌套 ≤3 层、单一职责；禁止在测试失败或自举未通过时提交。

具体命令与禁止操作见 [uya-dev-flow.mdc](../.codebuddy/rules/uya-dev-flow.mdc)。

---

## 总览

| 阶段 | 内容 | 状态 |
|------|------|------|
| 0 | 分支、common、测试占位、文档 | 已完成 |
| 1 | 基础层：MPI、熵（DRBG 移至阶段 2） | 已完成 |
| 2 | 密码学层：DRBG、哈希、HMAC、HKDF、AES、GCM、RSA、EC、X25519 | 待办 |
| 3 | X.509 层：ASN.1、证书解析、链验证 | 待办 |
| 4 | SSL/TLS 层：记录、握手、context；可选 DTLS | 待办 |

---

## 阶段 0：前置条件

**目标**：搭建仓库与目录结构、统一错误与常量、预留测试入口。

### 0.0 新建分支

- [x] 创建并切换到分支 `feature/tls-pure-uya`（或 `tls-uya`），后续所有 TLS 相关提交均在此分支。
- [ ] 在 README 或 CONTRIBUTING 中注明 TLS 开发在此分支。

### 0.1 公共类型与错误（lib/tls/common.uya）

- [x] 定义错误集合：如 `error.TlsBadInput`、`error.TlsInvalidMac`、`error.TlsDecodeError`、`error.TlsNoMemory`、`error.TlsCryptoFailure`、`error.TlsPlatformUnsupported` 等，与设计文档一致。
- [x] 定义 TLS 版本常量（如 `TLS_1_2 = 0x0303`、`TLS_1_3 = 0x0304`）。
- [x] 定义记录类型常量（handshake、alert、application_data 等）、常用密码套件 ID（占位即可，后续按需补全）。
- [x] 仅依赖 Uya 内置类型；若使用 `std.mem`，仅引用已有 API。
- [x] 验收：`common.uya` 可被 `use tls.common` 引用并编译通过。

### 0.2 测试占位与 CI

- [x] 在 **`tests/` 根目录**创建占位测试文件（可先 `return 0`）；该目录与 `tests/run_programs_parallel.sh` 无参数时的收集范围一致（`find tests/ -maxdepth 1 -name "*.uya"`），保证一次性跑全量时包含所有 test_tls_*。
  - [x] `tests/test_tls_mpi.uya`
  - [x] `tests/test_tls_sha256.uya` 或 `tests/test_tls_crypto.uya`（覆盖 SHA/HMAC/HKDF）
  - [x] `tests/test_tls_aes_gcm.uya`
  - [x] `tests/test_tls_drbg.uya`（阶段 2 实现 DRBG 后启用；或合并到 test_tls_crypto.uya）
  - [x] `tests/test_tls_rsa.uya` 或合并到 test_tls_crypto.uya（覆盖 RSA/EC/X25519）
  - [x] `tests/test_tls_x509.uya`（覆盖 ASN.1、cert、verify）
  - [x] `tests/test_tls_record.uya`（阶段 4 记录层单元测试；或合并到 test_tls_handshake.uya）
  - [x] `tests/test_tls_handshake.uya`
- [x] 确认 `tests/run_programs_parallel.sh --c99` 与 `--uya --c99` 能运行上述测试（占位通过即可）。
- [x] 验收：CI 或本地脚本可一次性跑完上述 test_tls_*.uya。

### 0.3 文档

- [x] 将 [tls_uya_design.md](tls_uya_design.md) 置于 `docs/`（或已存在则确认与本文一致）。
- [x] 在 `docs/` 下保留或新增 `tls_uya_plan.md`，记录与 mbedTLS 的模块对应关系及本待办文档链接。
- [x] 验收：新人可仅凭 design + todo 理解阶段划分与接口约定。

---

## 阶段 1：基础层

**目标**：实现大数（MPI）、熵源，供上层密码学与 X.509 使用。**DRBG 依赖 AES 或 HMAC，移至阶段 2 实现。**

### 1.1 大数（lib/tls/base/mpi.uya）

- [x] 定义 `struct Mpi`，内部 limb 表示（如 `[u64]` 或固定最大长度），提供 init/clear。
- [x] 实现 from_bytes_be / from_bytes_le、to_bytes_be / to_bytes_le（调用方提供缓冲区）。
- [x] 实现 add、sub、mul、div、mod、exp_mod、compare；compare 在密钥路径上为常量时间。
- [x] 编写 `tests/test_tls_mpi.uya`：已知值加减乘除、幂模、与 NIST 或自算向量对照。
- [x] 验收：test_tls_mpi.uya 通过 `--c99` 与 `--uya --c99`。

### 1.2 熵（lib/tls/base/entropy.uya）

- [x] 实现 `fn fill_entropy(buf: &byte, len: usize) !void`，Linux 下通过 syscall/FFI 读 `/dev/urandom`。
- [x] 其他平台可返回 `error.TlsPlatformUnsupported` 或预留扩展点。
- [x] 验收：在测试或示例中调用 fill_entropy 并检查输出非全零（或单独小测试）；`tests/test_tls_entropy.uya` 需在具备 `/dev/urandom` 的环境下通过。

### 1.3 DRBG（移至阶段 2）

- [x] **不在阶段 1 实现**：CTR-DRBG 依赖 AES，HMAC-DRBG 依赖 HMAC；已于阶段 2.5 实现 HMAC-DRBG。

---

## 阶段 2：密码学层

**目标**：实现哈希、HMAC、HKDF、AES、AES-GCM、RSA、EC、X25519、DRBG，供 X.509 与 TLS 使用。**DRBG 依赖 AES 或 HMAC，需在 2.1–2.3 就绪后实现（见 2.5）。**

### 2.1 哈希（lib/tls/crypto/sha256.uya, sha384.uya）

- [x] SHA-256：一次性接口和/或带状态 struct；输出 32 字节大端。
- [x] SHA-384：同上，输出 48 字节（lib/tls/crypto/sha384.uya，SHA-512 截断）。
- [x] `tests/test_tls_sha256.uya`（或 test_tls_crypto.uya）：NIST/RFC 向量。
- [x] 验收：SHA 测试通过。

### 2.2 HMAC 与 HKDF（lib/tls/crypto/hmac.uya, hkdf.uya）

- [x] HMAC-SHA256、HMAC-SHA384；接口与设计文档一致。
- [x] HKDF-Extract、HKDF-Expand（RFC 5869）。
- [x] 测试：RFC 4231 HMAC-SHA256 向量（Test Case 1、2）。
- [x] 验收：HMAC/HKDF 测试通过。

### 2.3 对称加密（lib/tls/crypto/aes.uya, gcm.uya）

- [x] AES-128/256：块加密、CBC/ECB（按需）；接口与设计一致。
- [x] AES-GCM：encrypt/decrypt，nonce、tag 显式传入/传出；解密验 tag 失败返回错误。
- [x] （可选）ChaCha20-Poly1305：同上风格（当前为 API 占位：提供 encrypt/decrypt 接口与测试，后续可接 RFC 8439 向量与纯 Uya 实现）。
- [x] `tests/test_tls_aes_gcm.uya`：NIST GCM 向量。
- [x] 验收：AES-GCM 测试通过。

### 2.4 公钥（lib/tls/crypto/rsa.uya, ec.uya, x25519.uya）

- [x] RSA：PKCS#1 v1.5 验签（SHA-256）；`rsa_verify_pkcs1_v15_sha256(n, e, hash, hash_len, sig, sig_len)`；密钥由调用方以 Mpi (n, e) 传入；解析 (n,e) 从字节或 X.509 待阶段 3。
- [x] EC：P-256 有限域 Fe256/标量 Sc256（lib/tls/crypto/ec_p256.uya）、点运算与标量乘、公钥生成、ECDH 已实现；ECDSA sign/verify API 已占位（验签/签名逻辑待补 NIST 向量与 sc256 模逆）。P-384 待实现（同结构）。
- [x] X25519：32 字节标量乘接口（lib/tls/crypto/x25519.uya）；RFC 7748 算法；当前使用 OpenSSL 参考实现（x25519_ref.c）通过 RFC 7748 Section 6.1 向量；纯 Uya 实现（x25519_pure_uya）未通过向量，待排查 fe_mul/fe_inv/fe_add/fe_sub。
- [x] 测试：test_tls_rsa.uya 中 X25519 确定性+非零通过；RSA 已知向量（512-bit, e=65537, SHA256("abc")）验签通过 + 篡改失败；EC 模块加载与 public_from_private_p256/ecdh_p256 调用通过。
- [x] 验收：X25519、RSA、EC（P-256 骨架+ECDH）测试通过 `--c99` 与 `--uya --c99`；EC 子群检查与 ECDSA 已知向量见后续迭代。

### 2.5 DRBG（lib/tls/base/drbg.uya）

- [x] 在 2.1–2.3（哈希、HMAC、AES）就绪后实现：HMAC-DRBG（NIST SP 800-90A，SHA-256）。
- [x] 定义 `struct DrbgCtx`，接口 drbg_init、drbg_fill_random、drbg_reseed。
- [x] 编写 `tests/test_tls_drbg.uya`：固定 entropy+nonce，验证确定性及非零输出。
- [x] 验收：DRBG 测试通过 `--c99` 与 `--uya --c99`。

---

## 阶段 3：X.509 层

**目标**：ASN.1/DER 解析、证书解析、证书链与主机名验证。

### 3.1 ASN.1（lib/tls/x509/asn1.uya）

- [x] 最小 DER 解析：INTEGER、OID、BIT STRING、OCTET STRING、SEQUENCE、显式标签常量；时间类型仅保留标签常量，解析可于 3.2 按需加。
- [x] 接口：游标式 Asn1Reader（data/len/pos）、asn1_enter_sequence、asn1_get_tlv、asn1_get_integer/octet_string/oid/bit_string、asn1_skip、asn1_remaining。
- [x] 测试：test_tls_x509 中手写 DER（SEQUENCE + INTEGER 5 + OCTET STRING "hello"）解析通过。
- [x] 验收：asn1 测试通过（--c99 与 --uya --c99 均通过）。

### 3.2 证书解析（lib/tls/x509/cert.uya）

- [x] 定义 Cert 结构体：der/tbs_offset/tbs_len、serial、sig、rsa_n/rsa_e（RSA 公钥）、sig_len 等；供 verify 使用。
- [x] `fn cert_parse(der, der_len, cert_out) !void`：解析证书 SEQUENCE、TBSCertificate（可选 [0] version、serial、跳过 sig/issuer/validity/subject、SubjectPublicKeyInfo RSA、可选 [1][2][3]）、signatureAlgorithm（跳过）、signatureValue BIT STRING。
- [x] 测试：test_tls_x509 中空输入 cert_parse 预期 TlsDecodeError；证书解析通过（当前仅覆盖空输入失败，有效证书解析待补嵌入 DER 或文件读取）。
- [x] 验收：test_tls_x509.uya 中 ASN.1 + 证书解析（空失败）通过；--c99 与 --uya --c99 均通过。

### 3.3 证书验证（lib/tls/x509/verify.uya）

- [x] 单证 RSA 验签：cert_verify_signature(cert, signer)（SHA-256(TBSCertificate) + PKCS#1 v1.5）、cert_verify_self(cert)；信任锚由调用方提供。
- [x] 链验证：多级证书链、基本约束、用途（当前为 RSA-only 结构校验：CA/basicConstraints/pathLen/keyUsage 与信任锚匹配，签名校验仍由 cert_verify_signature + RSA 测试覆盖）。
- [x] 主机名验证：SAN、CN 与 hostname 比较（当前提供 hostname_match/verify_hostname_bytes，支持精确匹配、大小写不敏感与简化 wildcard \"*.example.com\"；后续可接 DER 中 SAN/CN 解析）。
- [x] 测试：test_tls_x509 中 cert_verify_self 无公钥时预期失败。
- [x] 验收：verify 相关测试通过（--c99 与 --uya --c99）。

---

## 阶段 4：SSL/TLS 层

**目标**：TLS 记录层、握手状态机、SslContext；可选 DTLS。

### 4.1 记录层（lib/tls/ssl/record.uya）

- [x] 记录格式：类型(1)、版本(2)、长度(2) 共 5 字节头；单条 payload 最大 16384 字节；当前明文传输（无 AEAD），后续可接 GCM。
- [x] RecordCtx：写/读序列号、版本；record_encrypt/record_decrypt 实现分片与解析。
- [x] 单元测试：test_tls_record 单条记录加解密往返一致。
- [x] 验收：record 单元测试通过（--c99 与 --uya --c99）。

### 4.2 握手（lib/tls/ssl/handshake.uya）

- [x] 收发抽象：由调用方提供 recv_buf/recv_len 与 send_buf/send_max/send_len_out；handshake_client_start、handshake_client_step、handshake_server_step 返回 NeedSend/NeedRecv/Done/Error。
- [x] 最小状态机：HandshakeCtx（state/role）、客户端 ClientHelloSent→Done、服务端 ServerHelloSent→Done；当前为占位消息（5 字节），未接 PRF/RecordCtx。
- [x] `tests/test_tls_handshake.uya`：内存 mock 两端，client_start→server_step→client_step→server_step，双方 Done。
- [x] 验收：test_tls_handshake.uya 通过 `--c99` 与 `--uya --c99`。

### 4.3 上下文（lib/tls/ssl/context.uya）

- [x] SslContext：role、hs（&HandshakeCtx）、rec（&RecordCtx）；由调用方持有 HandshakeCtx/RecordCtx 并传入。
- [x] 接口：ssl_init、ssl_set_hostname（占位）、ssl_handshake_step、ssl_is_handshake_done、ssl_write、ssl_read、ssl_close_notify（占位）。
- [x] 与 handshake、record 集成；test_tls_handshake 中 test_context_handshake_and_write_read 经 context 完成握手并交换一条应用数据。
- [x] 验收：test_tls_handshake.uya 通过 `--c99` 与 `--uya --c99`。

### 4.4 TLS 1.3（lib/tls/ssl/handshake13.uya 或合并）

- [x] 1-RTT 握手骨架：ClientHello（占位 6 字节含 0x03 0x04）→ ServerHello（占位）→ Done；密钥 schedule 占位（后续用 HKDF）。
- [x] 与 context 集成：SslContext13 + ssl13_init/ssl13_handshake_step/ssl13_write/ssl13_read，应用在 init 时选 1.2（SslContext）或 1.3（SslContext13）。
- [x] 验收：test_context13_handshake_and_write_read 在 test_tls_handshake.uya 中通过；`--c99` 与 `--uya --c99` 通过。

### 4.5 DTLS（可选）

- [x] dtls_record.uya：13 字节 DTLS 头（ContentType/Version/Epoch/SequenceNumber/Length）封装与解析，单条记录明文 payload。
- [x] dtls_handshake.uya：占位状态机（ClientHello/ServerHello → Done）；当前未实现重传、超时、HelloVerifyRequest cookie，仅用于最小往返测试。
- [x] 验收：test_tls_dtls.uya 中 test_dtls_record_roundtrip、test_dtls_handshake_mock_roundtrip 通过；`--c99` 与 `--uya --c99` 通过。

---

## 里程碑与依赖

| 里程碑 | 内容 | 依赖 |
|--------|------|------|
| M1 | 阶段 1（MPI+entropy）+ 阶段 2（含 DRBG、哈希、HMAC、HKDF、AES-GCM、RSA/EC/X25519）完成；对应单元测试通过 | 无 |
| M2 | 阶段 3 完成；解析并验证真实证书链 | M1 |
| M3 | 阶段 4.1–4.3 完成；内存内 TLS 1.2/1.3 握手与加密通信 | M2 |
| M4 | DTLS、0-RTT、或与 mbedTLS 互操作（可选） | M3 |

---

## 参考

- [tls_uya_design.md](tls_uya_design.md) — 详细设计。
- [todo_mini_to_full.md](todo_mini_to_full.md) — 项目测试约定与实现顺序。
- [.cursorrules](../.cursorrules) — 测试需通过 `--c99` 与 `--uya --c99`。
