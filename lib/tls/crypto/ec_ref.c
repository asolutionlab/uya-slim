/* EC 参考实现：通过 OpenSSL 提供 P-256 / P-384 的公钥、ECDH、ECDSA 参考路径 */
#include <openssl/bn.h>
#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/obj_mac.h>
#include <stdint.h>
#include <string.h>

static int ec_make_key(int nid, const uint8_t *priv, size_t priv_len, EC_KEY **out_key, BIGNUM **out_priv_bn) {
    EC_KEY *key = EC_KEY_new_by_curve_name(nid);
    if (!key) {
        return -1;
    }
    BIGNUM *priv_bn = BN_bin2bn(priv, (int)priv_len, NULL);
    if (!priv_bn) {
        EC_KEY_free(key);
        return -1;
    }
    if (EC_KEY_set_private_key(key, priv_bn) != 1) {
        BN_clear_free(priv_bn);
        EC_KEY_free(key);
        return -1;
    }
    *out_key = key;
    *out_priv_bn = priv_bn;
    return 0;
}

static int ec_make_public_key(int nid, const uint8_t *pub, size_t pub_len, EC_KEY **out_key) {
    EC_KEY *key = EC_KEY_new_by_curve_name(nid);
    if (!key) {
        return -1;
    }
    const EC_GROUP *group = EC_KEY_get0_group(key);
    EC_POINT *point = EC_POINT_new(group);
    BN_CTX *ctx = BN_CTX_new();
    if (!point || !ctx) {
        EC_POINT_free(point);
        BN_CTX_free(ctx);
        EC_KEY_free(key);
        return -1;
    }
    if (EC_POINT_oct2point(group, point, pub, pub_len, ctx) != 1) {
        EC_POINT_free(point);
        BN_CTX_free(ctx);
        EC_KEY_free(key);
        return -1;
    }
    if (EC_KEY_set_public_key(key, point) != 1) {
        EC_POINT_free(point);
        BN_CTX_free(ctx);
        EC_KEY_free(key);
        return -1;
    }
    EC_POINT_free(point);
    BN_CTX_free(ctx);
    *out_key = key;
    return 0;
}

static int ec_public_from_private(int nid, const uint8_t *priv, size_t priv_len, uint8_t *pub_out, size_t pub_len) {
    EC_KEY *key = NULL;
    BIGNUM *priv_bn = NULL;
    BN_CTX *ctx = NULL;
    EC_POINT *pub = NULL;
    int rc = -1;

    if (ec_make_key(nid, priv, priv_len, &key, &priv_bn) != 0) {
        return -1;
    }
    ctx = BN_CTX_new();
    pub = EC_POINT_new(EC_KEY_get0_group(key));
    if (!ctx || !pub) {
        goto done;
    }
    if (EC_POINT_mul(EC_KEY_get0_group(key), pub, priv_bn, NULL, NULL, ctx) != 1) {
        goto done;
    }
    if (EC_POINT_point2oct(EC_KEY_get0_group(key), pub, POINT_CONVERSION_UNCOMPRESSED, pub_out, pub_len, ctx) != pub_len) {
        goto done;
    }
    rc = 0;

done:
    EC_POINT_free(pub);
    BN_CTX_free(ctx);
    BN_clear_free(priv_bn);
    EC_KEY_free(key);
    return rc;
}

static int ec_shared_secret(int nid, const uint8_t *priv, size_t priv_len, const uint8_t *pub, size_t pub_len, uint8_t *out, size_t out_len) {
    EC_KEY *key = NULL;
    BIGNUM *priv_bn = NULL;
    BN_CTX *ctx = NULL;
    EC_POINT *peer = NULL;
    int rc = -1;
    int field_len = 0;

    if (ec_make_key(nid, priv, priv_len, &key, &priv_bn) != 0) {
        return -1;
    }
    ctx = BN_CTX_new();
    peer = EC_POINT_new(EC_KEY_get0_group(key));
    if (!ctx || !peer) {
        goto done;
    }
    if (EC_POINT_oct2point(EC_KEY_get0_group(key), peer, pub, pub_len, ctx) != 1) {
        goto done;
    }
    field_len = EC_GROUP_get_degree(EC_KEY_get0_group(key));
    field_len = (field_len + 7) / 8;
    if (field_len <= 0 || (size_t)field_len > out_len) {
        goto done;
    }
    if (ECDH_compute_key(out, (size_t)field_len, peer, key, NULL) <= 0) {
        goto done;
    }
    rc = field_len;

done:
    EC_POINT_free(peer);
    BN_CTX_free(ctx);
    BN_clear_free(priv_bn);
    EC_KEY_free(key);
    return rc;
}

static int ec_sign_with_k(int nid, const uint8_t *priv, size_t priv_len, const uint8_t *hash, size_t hash_len, const uint8_t *k, size_t k_len, uint8_t *r_out, size_t r_len, uint8_t *s_out, size_t s_len) {
    EC_KEY *key = NULL;
    BIGNUM *priv_bn = NULL;
    BIGNUM *k_bn = NULL;
    BIGNUM *order = NULL;
    BIGNUM *kinv = NULL;
    BIGNUM *rp = NULL;
    BIGNUM *x = NULL;
    BIGNUM *y = NULL;
    BN_CTX *ctx = NULL;
    EC_POINT *kG = NULL;
    ECDSA_SIG *sig = NULL;
    const BIGNUM *sig_r = NULL;
    const BIGNUM *sig_s = NULL;
    int rc = -1;

    if (ec_make_key(nid, priv, priv_len, &key, &priv_bn) != 0) {
        return -1;
    }
    ctx = BN_CTX_new();
    if (!ctx) {
        goto done;
    }
    k_bn = BN_bin2bn(k, (int)k_len, NULL);
    if (!k_bn) {
        goto done;
    }
    order = BN_dup(EC_GROUP_get0_order(EC_KEY_get0_group(key)));
    if (!order) {
        goto done;
    }
    kinv = BN_mod_inverse(NULL, k_bn, order, ctx);
    if (!kinv) {
        goto done;
    }
    kG = EC_POINT_new(EC_KEY_get0_group(key));
    if (!kG) {
        goto done;
    }
    if (EC_POINT_mul(EC_KEY_get0_group(key), kG, k_bn, NULL, NULL, ctx) != 1) {
        goto done;
    }
    x = BN_new();
    y = BN_new();
    rp = BN_new();
    if (!x || !y || !rp) {
        goto done;
    }
    if (EC_POINT_get_affine_coordinates(EC_KEY_get0_group(key), kG, x, y, ctx) != 1) {
        goto done;
    }
    if (BN_nnmod(rp, x, order, ctx) != 1) {
        goto done;
    }
    sig = ECDSA_do_sign_ex(hash, (int)hash_len, kinv, rp, key);
    if (!sig) {
        goto done;
    }
    ECDSA_SIG_get0(sig, &sig_r, &sig_s);
    if (!sig_r || !sig_s) {
        goto done;
    }
    if (BN_bn2binpad(sig_r, r_out, (int)r_len) != (int)r_len) {
        goto done;
    }
    if (BN_bn2binpad(sig_s, s_out, (int)s_len) != (int)s_len) {
        goto done;
    }
    rc = 0;

done:
    ECDSA_SIG_free(sig);
    BN_clear_free(rp);
    BN_clear_free(y);
    BN_clear_free(x);
    EC_POINT_free(kG);
    BN_clear_free(kinv);
    BN_free(order);
    BN_clear_free(k_bn);
    BN_CTX_free(ctx);
    BN_clear_free(priv_bn);
    EC_KEY_free(key);
    return rc;
}

static int ec_verify_signature(int nid, const uint8_t *pub, size_t pub_len, const uint8_t *hash, size_t hash_len, const uint8_t *r, size_t r_len, const uint8_t *s, size_t s_len) {
    EC_KEY *key = NULL;
    BIGNUM *r_bn = NULL;
    BIGNUM *s_bn = NULL;
    ECDSA_SIG *sig = NULL;
    int rc = -1;

    if (ec_make_public_key(nid, pub, pub_len, &key) != 0) {
        return -1;
    }
    r_bn = BN_bin2bn(r, (int)r_len, NULL);
    s_bn = BN_bin2bn(s, (int)s_len, NULL);
    if (!r_bn || !s_bn) {
        goto done;
    }
    sig = ECDSA_SIG_new();
    if (!sig) {
        goto done;
    }
    if (ECDSA_SIG_set0(sig, r_bn, s_bn) != 1) {
        goto done;
    }
    r_bn = NULL;
    s_bn = NULL;
    rc = ECDSA_do_verify(hash, (int)hash_len, sig, key);

done:
    ECDSA_SIG_free(sig);
    BN_clear_free(r_bn);
    BN_clear_free(s_bn);
    EC_KEY_free(key);
    return rc;
}

int ec_public_from_private_p256_ref(uint8_t *pub_out, const uint8_t *priv) {
    return ec_public_from_private(NID_X9_62_prime256v1, priv, 32, pub_out, 65);
}

int ec_public_from_private_p384_ref(uint8_t *pub_out, const uint8_t *priv) {
    return ec_public_from_private(NID_secp384r1, priv, 48, pub_out, 97);
}

int ec_ecdh_p256_ref(uint8_t *out, const uint8_t *priv, const uint8_t *pub) {
    return ec_shared_secret(NID_X9_62_prime256v1, priv, 32, pub, 65, out, 32);
}

int ec_ecdh_p384_ref(uint8_t *out, const uint8_t *priv, const uint8_t *pub) {
    return ec_shared_secret(NID_secp384r1, priv, 48, pub, 97, out, 48);
}

int ec_ecdsa_sign_p256_with_k_ref(uint8_t *r_out, uint8_t *s_out, const uint8_t *priv, const uint8_t *hash, const uint8_t *k) {
    return ec_sign_with_k(NID_X9_62_prime256v1, priv, 32, hash, 32, k, 32, r_out, 32, s_out, 32);
}

int ec_ecdsa_sign_p384_with_k_ref(uint8_t *r_out, uint8_t *s_out, const uint8_t *priv, const uint8_t *hash, const uint8_t *k) {
    return ec_sign_with_k(NID_secp384r1, priv, 48, hash, 48, k, 48, r_out, 48, s_out, 48);
}

int ec_ecdsa_verify_p256_ref(const uint8_t *pub, const uint8_t *hash, const uint8_t *r, const uint8_t *s) {
    return ec_verify_signature(NID_X9_62_prime256v1, pub, 65, hash, 32, r, 32, s, 32);
}

int ec_ecdsa_verify_p384_ref(const uint8_t *pub, const uint8_t *hash, const uint8_t *r, const uint8_t *s) {
    return ec_verify_signature(NID_secp384r1, pub, 97, hash, 48, r, 48, s, 48);
}
