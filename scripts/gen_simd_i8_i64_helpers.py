#!/usr/bin/env python3
"""Emit Uya fputs lines for types.uya: SSE branch i64/u64 + i8/u8 helpers.

Usage:
  python3 gen_simd_i8_i64_helpers.py sse       # paste into SSE `#if UYA_HAVE_SIMD_X86_SSE` after ge_f32x2
  python3 gen_simd_i8_i64_helpers.py portable  # paste into NEON + `#else` after ge_f32x2 (before add_i32x4)

Portable uses `const void *` pred stubs (no __m128i). Regenerate after editing this file.
"""

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')

def emit(lines):
    for line in lines:
        print(f'    fputs("{esc(line)}\\n" as *byte, codegen.output as *void);')

def sse_i64_core():
    emit([
        "static inline void uya_simd_sse_i64x2_pred_store_mask(void *m, __m128i pr) {",
        "  union { __m128i v; int64_t q[2]; } u; u.v = pr;",
        "  bool *M = (bool *)m; M[0] = u.q[0] != 0; M[1] = u.q[1] != 0;",
        "}",
    ])
    for name, intrin in [
        ("add", "_mm_add_epi64"), ("sub", "_mm_sub_epi64"),
        ("and", "_mm_and_si128"), ("or", "_mm_or_si128"), ("xor", "_mm_xor_si128"),
    ]:
        emit([
            f"static inline void uya_simd_sse_{name}_i64x2(void *r, const void *a, const void *b) {{",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            f"  _mm_storeu_si128((__m128i *)(void *)r, {intrin}(va, vb));",
            "}",
        ])
    emit([
        "static inline void uya_simd_sse_mul_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] * bb[0]; rr[1] = aa[1] * bb[1];",
        "}",
        "static inline void uya_simd_sse_div_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] / bb[0]; rr[1] = aa[1] / bb[1];",
        "}",
        "static inline void uya_simd_sse_rem_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] % bb[0]; rr[1] = aa[1] % bb[1];",
        "}",
        "static inline void uya_simd_sse_shl_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] << bb[_i];",
        "}",
        "static inline void uya_simd_sse_shr_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] >> bb[_i];",
        "}",
        "static inline void uya_simd_sse_splat_i64x2(void *r, int64_t s) {",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_set_epi64x(s, s));",
        "}",
        "static inline void uya_simd_sse_neg_i64x2(void *r, const void *a) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_sub_epi64(_mm_setzero_si128(), va));",
        "}",
    ])
    emit([
        "static inline void uya_simd_sse_eq_i64x2_mask(void *m, const void *a, const void *b) {",
        "#if defined(__SSE4_1__)",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  uya_simd_sse_i64x2_pred_store_mask(m, _mm_cmpeq_epi64(va, vb));",
        "#else",
        "  bool *M = (bool *)m; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  M[0] = (aa[0] == bb[0]); M[1] = (aa[1] == bb[1]);",
        "#endif",
        "}",
    ])
    for cmpname, op in [("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
        emit([
            f"static inline void uya_simd_sse_{cmpname}_i64x2_mask(void *m, const void *a, const void *b) {{",
            "  bool *M = (bool *)m; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
            f"  M[0] = (aa[0] {op} bb[0]); M[1] = (aa[1] {op} bb[1]);",
            "}",
        ])

def sse_u64_core():
    emit([
        "static inline void uya_simd_sse_add_u64x2(void *r, const void *a, const void *b) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_add_epi64(va, vb));",
        "}",
        "static inline void uya_simd_sse_sub_u64x2(void *r, const void *a, const void *b) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_sub_epi64(va, vb));",
        "}",
        "static inline void uya_simd_sse_and_u64x2(void *r, const void *a, const void *b) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_and_si128(va, vb));",
        "}",
        "static inline void uya_simd_sse_or_u64x2(void *r, const void *a, const void *b) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_or_si128(va, vb));",
        "}",
        "static inline void uya_simd_sse_xor_u64x2(void *r, const void *a, const void *b) {",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_xor_si128(va, vb));",
        "}",
        "static inline void uya_simd_sse_mul_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] * bb[0]; rr[1] = aa[1] * bb[1];",
        "}",
        "static inline void uya_simd_sse_div_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] / bb[0]; rr[1] = aa[1] / bb[1];",
        "}",
        "static inline void uya_simd_sse_rem_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] % bb[0]; rr[1] = aa[1] % bb[1];",
        "}",
        "static inline void uya_simd_sse_shl_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] << bb[_i];",
        "}",
        "static inline void uya_simd_sse_shr_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] >> bb[_i];",
        "}",
        "static inline void uya_simd_sse_splat_u64x2(void *r, uint64_t s) {",
        "  _mm_storeu_si128((__m128i *)(void *)r, _mm_set_epi64x((int64_t)s, (int64_t)s));",
        "}",
        "static inline void uya_simd_sse_neg_u64x2(void *r, const void *a) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a;",
        "  rr[0] = 0ULL - aa[0]; rr[1] = 0ULL - aa[1];",
        "}",
    ])
    for cmpname, op in [("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
        emit([
            f"static inline void uya_simd_sse_{cmpname}_u64x2_mask(void *m, const void *a, const void *b) {{",
            "  bool *M = (bool *)m; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
            f"  M[0] = (aa[0] {op} bb[0]); M[1] = (aa[1] {op} bb[1]);",
            "}",
        ])

def sse_i8_pred_store():
    emit([
        "static inline void uya_simd_sse_i8x16_pred_store_mask(void *m, __m128i pr) {",
        "  union { __m128i v; int8_t c[16]; } u; u.v = pr;",
        "  bool *M = (bool *)m; int _k; for (_k = 0; _k < 16; _k++) M[_k] = (u.c[_k] != 0);",
        "}",
    ])

def sse_i8_binop_x16(elem: str, op: str, sse_call: str):
    emit([
        f"static inline void uya_simd_sse_{op}_{elem}x16(void *r, const void *a, const void *b) {{",
        "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
        f"  _mm_storeu_si128((__m128i *)(void *)r, {sse_call});",
        "}",
    ])

def copy_small(dst_arr: str, src_ptr: str, n: int) -> str:
    return (
        f"  {{ int _z; unsigned char *_d = {dst_arr}; const unsigned char *_s = (const unsigned char *)({src_ptr}); "
        f"for (_z = 0; _z < {n}; _z++) _d[_z] = _s[_z]; }}"
    )

def copy_to_r(r_ptr: str, src_arr: str, n: int) -> str:
    return (
        f"  {{ int _z; unsigned char *_d = (unsigned char *)({r_ptr}); const unsigned char *_s = {src_arr}; "
        f"for (_z = 0; _z < {n}; _z++) _d[_z] = _s[_z]; }}"
    )

def sse_i8_binop_pad(elem: str, op: str, n: int, sse_call: str):
    emit([
        f"static inline void uya_simd_sse_{op}_{elem}x{n}(void *r, const void *a, const void *b) {{",
        "  unsigned char ta[16] = {0}, tb[16] = {0}, tr[16] = {0};",
        copy_small("ta", "a", n),
        copy_small("tb", "b", n),
        "  __m128i va = _mm_loadu_si128((const __m128i *)(void *)ta);",
        "  __m128i vb = _mm_loadu_si128((const __m128i *)(void *)tb);",
        f"  _mm_storeu_si128((__m128i *)(void *)tr, {sse_call});",
        copy_to_r("r", "tr", n),
        "}",
    ])

def sse_i8_scalar_loop(elem: str, op: str, n: int, ctype: str, opchar: str):
    if opchar == "*":
        line = (
            "  rr[_k] = (int8_t)((int32_t)aa[_k] * (int32_t)bb[_k]);"
            if ctype == "int8_t"
            else "  rr[_k] = (uint8_t)((uint32_t)aa[_k] * (uint32_t)bb[_k]);"
        )
    elif opchar == "/":
        line = "  rr[_k] = aa[_k] / bb[_k];"
    elif opchar == "%":
        line = "  rr[_k] = aa[_k] % bb[_k];"
    elif opchar == "<<":
        line = (
            "  rr[_k] = (int8_t)((int32_t)aa[_k] << ((int32_t)bb[_k] & 31));"
            if ctype == "int8_t"
            else "  rr[_k] = (uint8_t)((uint32_t)aa[_k] << ((int32_t)bb[_k] & 31));"
        )
    else:  # >>
        line = (
            "  rr[_k] = (int8_t)((int32_t)aa[_k] >> ((int32_t)bb[_k] & 31));"
            if ctype == "int8_t"
            else "  rr[_k] = (uint8_t)((uint32_t)aa[_k] >> ((int32_t)bb[_k] & 31));"
        )
    emit([
        f"static inline void uya_simd_sse_{op}_{elem}x{n}(void *r, const void *a, const void *b) {{",
        f"  {ctype} *rr = ({ctype} *)r; const {ctype} *aa = (const {ctype} *)a; const {ctype} *bb = (const {ctype} *)b;",
        f"  int _k; for (_k = 0; _k < {n}; _k++) {{",
        line,
        "  }",
        "}",
    ])

def sse_i8_full(signed_prefix: str, ctype: str, u_suffix: str):
    """signed_prefix '' for i8, 'u' for u8 uses u8 in function names."""
    p = "u8" if ctype == "uint8_t" else "i8"
    # simd add/sub/and/or/xor
    for op, intrin in [("add", "_mm_add_epi8"), ("sub", "_mm_sub_epi8"),
                       ("and", "_mm_and_si128"), ("or", "_mm_or_si128"), ("xor", "_mm_xor_si128")]:
        sse_i8_binop_x16(p, op, intrin + "(va, vb)")
        for n in (8, 4, 2):
            sse_i8_binop_pad(p, op, n, intrin + "(va, vb)")
    # mul div rem shl shr - scalar per width
    for n in (16, 8, 4, 2):
        sse_i8_scalar_loop(p, "mul", n, ctype, "*")
        sse_i8_scalar_loop(p, "div", n, ctype, "/")
        sse_i8_scalar_loop(p, "rem", n, ctype, "%")
        sse_i8_scalar_loop(p, "shl", n, ctype, "<<")
        sse_i8_scalar_loop(p, "shr", n, ctype, ">>")
    # splat / neg
    for n in (16, 8, 4, 2):
        emit([
            f"static inline void uya_simd_sse_splat_{p}x{n}(void *r, {ctype} s) {{",
            f"  {ctype} *rr = ({ctype} *)r; int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = s;",
            "}",
            f"static inline void uya_simd_sse_neg_{p}x{n}(void *r, const void *a) {{",
            f"  {ctype} *rr = ({ctype} *)r; const {ctype} *aa = (const {ctype} *)a;",
            f"  int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = ({ctype})(-(int)aa[_k]);" if ctype == "int8_t" else f"  int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = ({ctype})(0U - aa[_k]);",
            "}",
        ])
    # masks x16 only use full xmm; smaller: pad
    if ctype == "int8_t":
        emit([
            "static inline void uya_simd_sse_eq_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmpeq_epi8(va, vb));",
            "}",
            "static inline void uya_simd_sse_ne_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_xor_si128(eq, _mm_set1_epi8((char)-1)));",
            "}",
            "static inline void uya_simd_sse_lt_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmplt_epi8(va, vb));",
            "}",
            "static inline void uya_simd_sse_gt_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmpgt_epi8(va, vb));",
            "}",
            "static inline void uya_simd_sse_le_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  __m128i lt = _mm_cmplt_epi8(va, vb); __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_or_si128(lt, eq));",
            "}",
            "static inline void uya_simd_sse_ge_i8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  __m128i gt = _mm_cmpgt_epi8(va, vb); __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_or_si128(gt, eq));",
            "}",
        ])
        for n, suf in [(8, "x8"), (4, "x4"), (2, "x2")]:
            emit([
                f"static inline void uya_simd_sse_eq_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  unsigned char ta[16] = {0}, tb[16] = {0};",
                copy_small("ta", "a", n),
                copy_small("tb", "b", n),
                "  __m128i va = _mm_loadu_si128((const __m128i *)(void *)ta);",
                "  __m128i vb = _mm_loadu_si128((const __m128i *)(void *)tb);",
                "  __m128i pr = _mm_cmpeq_epi8(va, vb);",
                "  union { __m128i v; int8_t c[16]; } uu; uu.v = pr;",
                "  bool *M = (bool *)m;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (uu.c[_k] != 0);",
                "}",
            ])
            emit([
                f"static inline void uya_simd_sse_ne_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  unsigned char ta[16] = {0}, tb[16] = {0};",
                copy_small("ta", "a", n),
                copy_small("tb", "b", n),
                "  __m128i va = _mm_loadu_si128((const __m128i *)(void *)ta);",
                "  __m128i vb = _mm_loadu_si128((const __m128i *)(void *)tb);",
                "  __m128i eq = _mm_cmpeq_epi8(va, vb);",
                "  __m128i pr = _mm_xor_si128(eq, _mm_set1_epi8((char)-1));",
                "  union { __m128i v; int8_t c[16]; } uu; uu.v = pr;",
                "  bool *M = (bool *)m;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (uu.c[_k] != 0);",
                "}",
            ])
            emit([
                f"static inline void uya_simd_sse_lt_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const int8_t *aa = (const int8_t *)a; const int8_t *bb = (const int8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] < bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_gt_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const int8_t *aa = (const int8_t *)a; const int8_t *bb = (const int8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] > bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_le_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const int8_t *aa = (const int8_t *)a; const int8_t *bb = (const int8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] <= bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_ge_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const int8_t *aa = (const int8_t *)a; const int8_t *bb = (const int8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] >= bb[_k]);",
                "}",
            ])
    else:
        bx = "_mm_set1_epi8((char)0x80)"
        emit([
            "static inline void uya_simd_sse_eq_u8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmpeq_epi8(va, vb));",
            "}",
            "static inline void uya_simd_sse_ne_u8x16_mask(void *m, const void *a, const void *b) {",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            "  __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_xor_si128(eq, _mm_set1_epi8((char)-1)));",
            "}",
            f"static inline void uya_simd_sse_lt_u8x16_mask(void *m, const void *a, const void *b) {{",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            f"  __m128i bx = {bx}; __m128i ba = _mm_xor_si128(va, bx); __m128i bb = _mm_xor_si128(vb, bx);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmplt_epi8(ba, bb));",
            "}",
            f"static inline void uya_simd_sse_gt_u8x16_mask(void *m, const void *a, const void *b) {{",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            f"  __m128i bx = {bx}; __m128i ba = _mm_xor_si128(va, bx); __m128i bb = _mm_xor_si128(vb, bx);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_cmplt_epi8(bb, ba));",
            "}",
            f"static inline void uya_simd_sse_le_u8x16_mask(void *m, const void *a, const void *b) {{",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            f"  __m128i bx = {bx}; __m128i ba = _mm_xor_si128(va, bx); __m128i bb = _mm_xor_si128(vb, bx);",
            "  __m128i lt = _mm_cmplt_epi8(ba, bb); __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_or_si128(lt, eq));",
            "}",
            f"static inline void uya_simd_sse_ge_u8x16_mask(void *m, const void *a, const void *b) {{",
            "  __m128i va = _mm_loadu_si128((const __m128i *)(const void *)a);",
            "  __m128i vb = _mm_loadu_si128((const __m128i *)(const void *)b);",
            f"  __m128i bx = {bx}; __m128i ba = _mm_xor_si128(va, bx); __m128i bb = _mm_xor_si128(vb, bx);",
            "  __m128i gt = _mm_cmplt_epi8(bb, ba); __m128i eq = _mm_cmpeq_epi8(va, vb);",
            "  uya_simd_sse_i8x16_pred_store_mask(m, _mm_or_si128(gt, eq));",
            "}",
        ])
        for n, suf in [(8, "x8"), (4, "x4"), (2, "x2")]:
            emit([
                f"static inline void uya_simd_sse_eq_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  unsigned char ta[16] = {0}, tb[16] = {0};",
                copy_small("ta", "a", n),
                copy_small("tb", "b", n),
                "  __m128i va = _mm_loadu_si128((const __m128i *)(void *)ta);",
                "  __m128i vb = _mm_loadu_si128((const __m128i *)(void *)tb);",
                "  __m128i pr = _mm_cmpeq_epi8(va, vb);",
                "  union { __m128i v; int8_t c[16]; } uu; uu.v = pr;",
                "  bool *M = (bool *)m;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (uu.c[_k] != 0);",
                "}",
                f"static inline void uya_simd_sse_ne_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  unsigned char ta[16] = {0}, tb[16] = {0};",
                copy_small("ta", "a", n),
                copy_small("tb", "b", n),
                "  __m128i va = _mm_loadu_si128((const __m128i *)(void *)ta);",
                "  __m128i vb = _mm_loadu_si128((const __m128i *)(void *)tb);",
                "  __m128i eq = _mm_cmpeq_epi8(va, vb);",
                "  __m128i pr = _mm_xor_si128(eq, _mm_set1_epi8((char)-1));",
                "  union { __m128i v; int8_t c[16]; } uu; uu.v = pr;",
                "  bool *M = (bool *)m;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (uu.c[_k] != 0);",
                "}",
                f"static inline void uya_simd_sse_lt_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const uint8_t *aa = (const uint8_t *)a; const uint8_t *bb = (const uint8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] < bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_gt_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const uint8_t *aa = (const uint8_t *)a; const uint8_t *bb = (const uint8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] > bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_le_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const uint8_t *aa = (const uint8_t *)a; const uint8_t *bb = (const uint8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] <= bb[_k]);",
                "}",
                f"static inline void uya_simd_sse_ge_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                "  bool *M = (bool *)m; const uint8_t *aa = (const uint8_t *)a; const uint8_t *bb = (const uint8_t *)b;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] >= bb[_k]);",
                "}",
            ])

def portable_i64_u64():
    """Scalar C only — for NEON + #else (no __m128i); pred uses const void * like i16 scalar branch."""
    emit([
        "static inline void uya_simd_sse_i64x2_pred_store_mask(void *m, const void *pr) {",
        "  bool *M = (bool *)m; const int64_t *p = (const int64_t *)pr;",
        "  M[0] = (p[0] != 0); M[1] = (p[1] != 0);",
        "}",
    ])
    # i64x2 — ignore pred mask portable stub (not called without SSE)
    for name, op in [
        ("add", "+"), ("sub", "-"), ("and", "&"), ("or", "|"), ("xor", "^"),
    ]:
        emit([
            f"static inline void uya_simd_sse_{name}_i64x2(void *r, const void *a, const void *b) {{",
            "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
            f"  rr[0] = aa[0] {op} bb[0]; rr[1] = aa[1] {op} bb[1];",
            "}",
        ])
    emit([
        "static inline void uya_simd_sse_mul_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] * bb[0]; rr[1] = aa[1] * bb[1];",
        "}",
        "static inline void uya_simd_sse_div_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] / bb[0]; rr[1] = aa[1] / bb[1];",
        "}",
        "static inline void uya_simd_sse_rem_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  rr[0] = aa[0] % bb[0]; rr[1] = aa[1] % bb[1];",
        "}",
        "static inline void uya_simd_sse_shl_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] << bb[_i];",
        "}",
        "static inline void uya_simd_sse_shr_i64x2(void *r, const void *a, const void *b) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] >> bb[_i];",
        "}",
        "static inline void uya_simd_sse_splat_i64x2(void *r, int64_t s) {",
        "  int64_t *rr = (int64_t *)r; rr[0] = s; rr[1] = s;",
        "}",
        "static inline void uya_simd_sse_neg_i64x2(void *r, const void *a) {",
        "  int64_t *rr = (int64_t *)r; const int64_t *aa = (const int64_t *)a;",
        "  rr[0] = -aa[0]; rr[1] = -aa[1];",
        "}",
    ])
    for cmpname, op in [("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
        emit([
            f"static inline void uya_simd_sse_{cmpname}_i64x2_mask(void *m, const void *a, const void *b) {{",
            "  bool *M = (bool *)m; const int64_t *aa = (const int64_t *)a; const int64_t *bb = (const int64_t *)b;",
            f"  M[0] = (aa[0] {op} bb[0]); M[1] = (aa[1] {op} bb[1]);",
            "}",
        ])
    emit([
        "static inline void uya_simd_sse_add_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] + bb[0]; rr[1] = aa[1] + bb[1];",
        "}",
        "static inline void uya_simd_sse_sub_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] - bb[0]; rr[1] = aa[1] - bb[1];",
        "}",
        "static inline void uya_simd_sse_and_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] & bb[0]; rr[1] = aa[1] & bb[1];",
        "}",
        "static inline void uya_simd_sse_or_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] | bb[0]; rr[1] = aa[1] | bb[1];",
        "}",
        "static inline void uya_simd_sse_xor_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] ^ bb[0]; rr[1] = aa[1] ^ bb[1];",
        "}",
        "static inline void uya_simd_sse_mul_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] * bb[0]; rr[1] = aa[1] * bb[1];",
        "}",
        "static inline void uya_simd_sse_div_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] / bb[0]; rr[1] = aa[1] / bb[1];",
        "}",
        "static inline void uya_simd_sse_rem_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  rr[0] = aa[0] % bb[0]; rr[1] = aa[1] % bb[1];",
        "}",
        "static inline void uya_simd_sse_shl_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] << bb[_i];",
        "}",
        "static inline void uya_simd_sse_shr_u64x2(void *r, const void *a, const void *b) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
        "  int _i; for (_i = 0; _i < 2; _i++) rr[_i] = aa[_i] >> bb[_i];",
        "}",
        "static inline void uya_simd_sse_splat_u64x2(void *r, uint64_t s) {",
        "  uint64_t *rr = (uint64_t *)r; rr[0] = s; rr[1] = s;",
        "}",
        "static inline void uya_simd_sse_neg_u64x2(void *r, const void *a) {",
        "  uint64_t *rr = (uint64_t *)r; const uint64_t *aa = (const uint64_t *)a;",
        "  rr[0] = 0ULL - aa[0]; rr[1] = 0ULL - aa[1];",
        "}",
    ])
    for cmpname, op in [("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
        emit([
            f"static inline void uya_simd_sse_{cmpname}_u64x2_mask(void *m, const void *a, const void *b) {{",
            "  bool *M = (bool *)m; const uint64_t *aa = (const uint64_t *)a; const uint64_t *bb = (const uint64_t *)b;",
            f"  M[0] = (aa[0] {op} bb[0]); M[1] = (aa[1] {op} bb[1]);",
            "}",
        ])


def portable_i8_u8_pred_stub():
    emit([
        "static inline void uya_simd_sse_i8x16_pred_store_mask(void *m, const void *pr) {",
        "  bool *M = (bool *)m; const int8_t *p = (const int8_t *)pr;",
        "  int _k; for (_k = 0; _k < 16; _k++) M[_k] = (p[_k] != 0);",
        "}",
    ])


def portable_i8_binop_loop(p: str, op: str, n: int, ctype: str, c_op: str):
    if c_op in ("+", "-", "&", "|", "^"):
        expr = f"aa[_k] {c_op} bb[_k]"
    else:
        raise ValueError(c_op)
    emit([
        f"static inline void uya_simd_sse_{op}_{p}x{n}(void *r, const void *a, const void *b) {{",
        f"  {ctype} *rr = ({ctype} *)r; const {ctype} *aa = (const {ctype} *)a; const {ctype} *bb = (const {ctype} *)b;",
        f"  int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = ({ctype})({expr});",
        "}",
    ])


def portable_i8_full():
    portable_i8_u8_pred_stub()
    for ctype, p in [("int8_t", "i8"), ("uint8_t", "u8")]:
        for op, c_op in [("add", "+"), ("sub", "-"), ("and", "&"), ("or", "|"), ("xor", "^")]:
            for n in (16, 8, 4, 2):
                portable_i8_binop_loop(p, op, n, ctype, c_op)
        for n in (16, 8, 4, 2):
            sse_i8_scalar_loop(p, "mul", n, ctype, "*")
            sse_i8_scalar_loop(p, "div", n, ctype, "/")
            sse_i8_scalar_loop(p, "rem", n, ctype, "%")
            sse_i8_scalar_loop(p, "shl", n, ctype, "<<")
            sse_i8_scalar_loop(p, "shr", n, ctype, ">>")
        for n in (16, 8, 4, 2):
            emit([
                f"static inline void uya_simd_sse_splat_{p}x{n}(void *r, {ctype} s) {{",
                f"  {ctype} *rr = ({ctype} *)r; int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = s;",
                "}",
                f"static inline void uya_simd_sse_neg_{p}x{n}(void *r, const void *a) {{",
                f"  {ctype} *rr = ({ctype} *)r; const {ctype} *aa = (const {ctype} *)a;",
                f"  int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = ({ctype})(-(int)aa[_k]);" if ctype == "int8_t" else f"  int _k; for (_k = 0; _k < {n}; _k++) rr[_k] = ({ctype})(0U - aa[_k]);",
                "}",
            ])
        if ctype == "int8_t":
            for suf, n in [("x16", 16), ("x8", 8), ("x4", 4), ("x2", 2)]:
                for cmpname, cop in [("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
                    emit([
                        f"static inline void uya_simd_sse_{cmpname}_i8{suf}_mask(void *m, const void *a, const void *b) {{",
                        "  bool *M = (bool *)m; const int8_t *aa = (const int8_t *)a; const int8_t *bb = (const int8_t *)b;",
                        f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] {cop} bb[_k]);",
                        "}",
                    ])
        else:
            for suf, n in [("x16", 16), ("x8", 8), ("x4", 4), ("x2", 2)]:
                for cmpname, cop in [("eq", "=="), ("ne", "!="), ("lt", "<"), ("gt", ">"), ("le", "<="), ("ge", ">=")]:
                    emit([
                        f"static inline void uya_simd_sse_{cmpname}_u8{suf}_mask(void *m, const void *a, const void *b) {{",
                        "  bool *M = (bool *)m; const uint8_t *aa = (const uint8_t *)a; const uint8_t *bb = (const uint8_t *)b;",
                        f"  int _k; for (_k = 0; _k < {n}; _k++) M[_k] = (aa[_k] {cop} bb[_k]);",
                        "}",
                    ])


def main():
    import sys
    mode = sys.argv[1] if len(sys.argv) > 1 else "sse"
    if mode == "sse":
        sse_i8_pred_store()
        sse_i8_full("", "int8_t", "")
        sse_i8_full("u", "uint8_t", "u")
        sse_i64_core()
        sse_u64_core()
    elif mode == "portable":
        portable_i8_full()
        portable_i64_u64()
    else:
        raise SystemExit("usage: gen_simd_i8_i64_helpers.py [sse|portable]")


if __name__ == "__main__":
    main()
