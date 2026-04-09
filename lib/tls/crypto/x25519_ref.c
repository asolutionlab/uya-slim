/* X25519 参考实现：通过 OpenSSL 提供 RFC 7748 正确输出，供测试链接 */
#include <openssl/evp.h>
#include <openssl/params.h>
#include <openssl/core_names.h>
#include <stdint.h>

/* 与 Uya extern fn x25519_ref_impl 的 C 符号匹配 */
int x25519_ref_impl(uint8_t *out, const uint8_t *scalar, const uint8_t *point) {
    EVP_PKEY *pk = EVP_PKEY_new_raw_private_key(EVP_PKEY_X25519, NULL, scalar, 32);
    if (!pk) return -1;
    EVP_PKEY *peer = EVP_PKEY_new_raw_public_key(EVP_PKEY_X25519, NULL, point, 32);
    if (!peer) { EVP_PKEY_free(pk); return -1; }
    EVP_PKEY_CTX *ctx = EVP_PKEY_CTX_new(pk, NULL);
    if (!ctx) { EVP_PKEY_free(peer); EVP_PKEY_free(pk); return -1; }
    size_t len = 32;
    if (EVP_PKEY_derive_init(ctx) <= 0 ||
        EVP_PKEY_derive_set_peer(ctx, peer) <= 0 ||
        EVP_PKEY_derive(ctx, out, &len) <= 0) {
        EVP_PKEY_CTX_free(ctx);
        EVP_PKEY_free(peer);
        EVP_PKEY_free(pk);
        return -1;
    }
    EVP_PKEY_CTX_free(ctx);
    EVP_PKEY_free(peer);
    EVP_PKEY_free(pk);
    return 0;
}
