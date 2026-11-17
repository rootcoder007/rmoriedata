/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * pqplain.c -- the per-value loops of the Parquet reader and writer
 * (R/aaa_parquet.R) for PLAIN-encoded BYTE_ARRAY values: a 4-byte
 * little-endian length, then that many bytes, per value.
 *
 * C_rmd_pq_strings(buf, pos, count, column) reads `count` values starting at the
 * 1-based byte `pos` of the raw vector `buf` and returns list(values, pos): the
 * strings, and the byte after the last one. A Parquet string is UTF-8 by
 * definition, and the writer refuses anything else, so a value that is not valid
 * UTF-8 (or holds a NUL byte, which no R string can) is refused naming the column;
 * every other value is marked UTF-8 (an ASCII one stays unmarked, as R keeps it).
 *
 * C_rmd_pq_bytes(strings) writes the strings (no NA) the same way, byte for byte
 * as R holds them: the R side has already made them UTF-8.
 *
 * C_rmd_pq_rle reads the RLE / bit-packed hybrid, and C_rmd_pq_rows puts a data
 * page's values (or its dictionary's) into their rows; see each below.
 */
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>

/* RFC 3629: no overlong forms, no surrogates, nothing past U+10FFFF. */
static int rmd_utf8_ok(const unsigned char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        unsigned char c = s[i];
        if (c < 0x80) { i++; continue; }
        size_t k;
        unsigned int cp;
        if (c >= 0xC2 && c <= 0xDF) { k = 1; cp = c & 0x1F; }
        else if (c >= 0xE0 && c <= 0xEF) { k = 2; cp = c & 0x0F; }
        else if (c >= 0xF0 && c <= 0xF4) { k = 3; cp = c & 0x07; }
        else return 0;
        if (n - i - 1 < k) return 0;
        for (size_t j = 1; j <= k; j++) {
            unsigned char d = s[i + j];
            if ((d & 0xC0) != 0x80) return 0;
            cp = (cp << 6) | (d & 0x3F);
        }
        if ((k == 2 && (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF))) ||
            (k == 3 && (cp < 0x10000 || cp > 0x10FFFF)))
            return 0;
        i += k + 1;
    }
    return 1;
}

SEXP C_rmd_pq_strings(SEXP buf, SEXP pos, SEXP count, SEXP column) {
    if (TYPEOF(buf) != RAWSXP) error("parquet: internal: `buf` must be raw");
    double p0 = asReal(pos), nc = asReal(count);
    R_xlen_t len = XLENGTH(buf);
    if (!R_FINITE(p0) || p0 < 1 || !R_FINITE(nc) || nc < 0 || nc > (double) R_XLEN_T_MAX)
        error("parquet: internal: bad position or count");
    const char *col = (isString(column) && XLENGTH(column) == 1) ?
        translateCharUTF8(STRING_ELT(column, 0)) : "?";
    const unsigned char *b = RAW(buf);
    R_xlen_t n = (R_xlen_t) nc;
    /* every value takes at least its 4 length bytes */
    if ((double) n * 4.0 > (double) len - (p0 - 1))
        error("parquet: a BYTE_ARRAY length runs past the end of its page or chunk "
              "(%.0f values from byte %.0f of %.0f)", nc, p0, (double) len);
    SEXP out = PROTECT(allocVector(STRSXP, n));
    R_xlen_t at = (R_xlen_t) p0 - 1;
    for (R_xlen_t i = 0; i < n; i++) {
        if (len - at < 4)
            error("parquet: a BYTE_ARRAY length runs past the end of its page or chunk "
                  "(4 bytes at %.0f of %.0f)", (double) at + 1, (double) len);
        uint32_t m = (uint32_t) b[at] | ((uint32_t) b[at + 1] << 8) |
            ((uint32_t) b[at + 2] << 16) | ((uint32_t) b[at + 3] << 24);
        at += 4;
        if ((double) m > (double) (len - at))
            error("parquet: a BYTE_ARRAY value runs past the end of its page or chunk "
                  "(%.0f bytes at %.0f of %.0f)", (double) m, (double) at + 1, (double) len);
        if (m > INT_MAX)
            error("parquet: column %s holds a value of %.0f bytes, more than an R "
                  "string can hold", col, (double) m);
        const unsigned char *s = b + at;
        if (memchr(s, 0, m) != NULL)
            error("parquet: column %s holds a value with a NUL byte (value %.0f), which "
                  "an R string cannot hold", col, (double) i + 1);
        if (!rmd_utf8_ok(s, m))
            error("parquet: column %s holds a value that is not valid UTF-8 (value %.0f); "
                  "Parquet strings are UTF-8, so the file is damaged or was not written "
                  "as Parquet requires", col, (double) i + 1);
        SET_STRING_ELT(out, i, mkCharLenCE((const char *) s, (int) m, CE_UTF8));
        at += m;
    }
    SEXP res = PROTECT(allocVector(VECSXP, 2));
    SET_VECTOR_ELT(res, 0, out);
    SET_VECTOR_ELT(res, 1, ScalarReal((double) at + 1));
    SEXP nm = PROTECT(allocVector(STRSXP, 2));
    SET_STRING_ELT(nm, 0, mkChar("values"));
    SET_STRING_ELT(nm, 1, mkChar("pos"));
    setAttrib(res, R_NamesSymbol, nm);
    UNPROTECT(3);
    return res;
}

SEXP C_rmd_pq_bytes(SEXP x) {
    if (!isString(x)) error("parquet: internal: `x` must be character");
    R_xlen_t n = XLENGTH(x);
    double total = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(x, i);
        if (s == NA_STRING) error("parquet: internal: NA among the present values");
        total += 4.0 + (double) LENGTH(s);
    }
    if (total > (double) R_XLEN_T_MAX) error("parquet: column too large to write");
    SEXP out = PROTECT(allocVector(RAWSXP, (R_xlen_t) total));
    unsigned char *o = RAW(out);
    R_xlen_t at = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(x, i);
        uint32_t m = (uint32_t) LENGTH(s);
        o[at] = (unsigned char) (m & 0xFF);
        o[at + 1] = (unsigned char) ((m >> 8) & 0xFF);
        o[at + 2] = (unsigned char) ((m >> 16) & 0xFF);
        o[at + 3] = (unsigned char) ((m >> 24) & 0xFF);
        at += 4;
        if (m) memcpy(o + at, CHAR(s), m);
        at += m;
    }
    UNPROTECT(1);
    return out;
}

/* The RLE / bit-packed hybrid, one value at a time: `w` is 1 to 32 bits, the
 * data lies in bytes [p, e) of `b` (0-based). A bit-packed run of g groups
 * holds 8 g values (the last group may be padding); an RLE run holds its
 * count of one value. */
typedef struct {
    const unsigned char *b, *q;
    R_xlen_t p, e;
    int w, nbytes, packed;
    uint64_t left, val, bit;
} rmd_rle;

static void rmd_rle_init(rmd_rle *s, const unsigned char *b, R_xlen_t p, R_xlen_t e, int w) {
    s->b = b; s->q = b; s->p = p; s->e = e; s->w = w; s->nbytes = (w + 7) / 8;
    s->packed = 0; s->left = 0; s->val = 0; s->bit = 0;
}

/* the next value into *v; 0 when the data has run out */
static int rmd_rle_next(rmd_rle *s, int *v) {
    while (s->left == 0) {
        if (s->p >= s->e) return 0;
        uint64_t header = 0;
        int shift = 0;
        for (;;) {
            if (s->p >= s->e) error("parquet: RLE run header runs past its data");
            unsigned char c = s->b[s->p++];
            header |= (uint64_t) (c & 127) << shift;
            if (!(c & 128)) break;
            shift += 7;
            if (shift > 63) error("parquet: RLE run header longer than 10 bytes");
        }
        if (header & 1) { /* bit-packed: groups of eight values */
            uint64_t groups = header >> 1;
            if (groups > (uint64_t) (s->e - s->p) / (uint64_t) s->w)
                error("parquet: bit-packed run of %.0f groups runs past its data",
                      (double) groups);
            s->packed = 1;
            s->q = s->b + s->p;
            s->bit = 0;
            s->left = groups * 8;
            s->p += (R_xlen_t) (groups * (uint64_t) s->w);
        } else { /* a run of one value */
            uint64_t val = 0;
            if (s->e - s->p < s->nbytes) error("parquet: RLE run value runs past its data");
            for (int k = 0; k < s->nbytes; k++) val |= (uint64_t) s->b[s->p + k] << (8 * k);
            s->p += s->nbytes;
            if (val > (uint64_t) INT_MAX) error("parquet: RLE value above 2^31");
            s->packed = 0;
            s->val = val;
            s->left = header >> 1;
        }
    }
    s->left--;
    if (!s->packed) {
        *v = (int) s->val;
        return 1;
    }
    uint64_t x = 0;
    for (int k = 0; k < s->w; k++, s->bit++)
        x |= (uint64_t) ((s->q[s->bit >> 3] >> (s->bit & 7)) & 1) << k;
    if (x > (uint64_t) INT_MAX) error("parquet: RLE value above 2^31");
    *v = (int) x;
    return 1;
}

/* C_rmd_pq_rle(buf, pos, width, count, end): `count` values of the hybrid
 * starting at the 1-based byte `pos` of `buf`, read no further than the
 * 1-based byte `end`; `width` is 1 to 32 bits. Returns list(values, pos). One
 * pass in C: a page of runs of one value each cost the R loop a second per
 * hundred thousand rows. */
SEXP C_rmd_pq_rle(SEXP buf, SEXP pos, SEXP width, SEXP count, SEXP end) {
    if (TYPEOF(buf) != RAWSXP) error("parquet: internal: `buf` must be raw");
    double p0 = asReal(pos), nc = asReal(count), e0 = asReal(end);
    int w = asInteger(width);
    R_xlen_t len = XLENGTH(buf);
    if (!R_FINITE(p0) || p0 < 1 || !R_FINITE(nc) || nc < 0 || nc > (double) INT_MAX ||
        !R_FINITE(e0) || w == NA_INTEGER || w < 1 || w > 32)
        error("parquet: internal: bad position, count or width");
    R_xlen_t e = e0 >= (double) len ? len : (e0 < 0 ? 0 : (R_xlen_t) e0);
    R_xlen_t p = p0 - 1 >= (double) len ? len : (R_xlen_t) (p0 - 1);
    R_xlen_t n = (R_xlen_t) nc;
    rmd_rle s;
    rmd_rle_init(&s, RAW(buf), p, e, w);
    SEXP vals = PROTECT(allocVector(INTSXP, n));
    int *out = INTEGER(vals);
    for (R_xlen_t o = 0; o < n; o++)
        if (!rmd_rle_next(&s, out + o))
            error("parquet: RLE data ran out after %.0f of %.0f values", (double) o, (double) n);
    SEXP res = PROTECT(allocVector(VECSXP, 2));
    SEXP nm = PROTECT(allocVector(STRSXP, 2));
    SET_STRING_ELT(nm, 0, mkChar("values"));
    SET_STRING_ELT(nm, 1, mkChar("pos"));
    setAttrib(res, R_NamesSymbol, nm);
    SET_VECTOR_ELT(res, 0, vals);
    SET_VECTOR_ELT(res, 1, ScalarInteger((int) (s.p + 1)));
    UNPROTECT(3);
    return res;
}

/* C_rmd_pq_rows(page, dpos, dend, ipos, iwidth, vals, n, column): the `n` rows of
 * a data page, made at their final length in one pass. `dpos` to `dend` (1-based,
 * inclusive) hold the definition levels at width 1, or `dpos` is 0 for a column
 * with none (every row present). With `ipos` 0, `vals` are the page's present
 * values in order; otherwise `vals` is the dictionary and its 0-based indices
 * start at the 1-based byte `ipos` at width `iwidth` (0 to 32), running to the end
 * of the page. A missing row is NA (NULL in a list). Neither the levels nor the
 * indices are expanded into vectors of their own: a dictionary page of a 184-byte
 * file holding one run of 5e7 indices cost 1.75 GB in R, four times its result. */
SEXP C_rmd_pq_rows(SEXP page, SEXP dpos, SEXP dend, SEXP ipos, SEXP iwidth, SEXP vals,
                   SEXP n_, SEXP column) {
    if (TYPEOF(page) != RAWSXP) error("parquet: internal: `page` must be raw");
    int t = TYPEOF(vals);
    if (t != STRSXP && t != INTSXP && t != LGLSXP && t != REALSXP && t != VECSXP)
        error("parquet: internal: values of an unexpected type");
    double dp = asReal(dpos), de = asReal(dend), ip = asReal(ipos), nd = asReal(n_);
    int iw = asInteger(iwidth);
    R_xlen_t len = XLENGTH(page);
    if (!R_FINITE(dp) || dp < 0 || !R_FINITE(de) || de > (double) len ||
        !R_FINITE(ip) || ip < 0 || ip > (double) len + 1 ||
        !R_FINITE(nd) || nd < 0 || nd > (double) INT_MAX ||
        iw == NA_INTEGER || iw < 0 || iw > 32)
        error("parquet: internal: bad position, count or width");
    const char *col = (isString(column) && XLENGTH(column) == 1) ?
        translateCharUTF8(STRING_ELT(column, 0)) : "?";
    const unsigned char *b = RAW(page);
    R_xlen_t n = (R_xlen_t) nd, nv = XLENGTH(vals), present = n;
    int dict = ip > 0, v;
    rmd_rle d, x;
    /* the levels once to count the present rows (and refuse short data), then
     * again as the rows are filled */
    if (dp > 0) {
        present = 0;
        rmd_rle_init(&d, b, (R_xlen_t) dp - 1, de < dp - 1 ? (R_xlen_t) dp - 1 :
                     (R_xlen_t) de, 1);
        for (R_xlen_t i = 0; i < n; i++) {
            if (!rmd_rle_next(&d, &v))
                error("parquet: RLE data ran out after %.0f of %.0f values",
                      (double) i, (double) n);
            present += v != 0;
        }
        rmd_rle_init(&d, b, (R_xlen_t) dp - 1, de < dp - 1 ? (R_xlen_t) dp - 1 :
                     (R_xlen_t) de, 1);
    }
    if (!dict && present != nv)
        error("parquet: page of column %s holds %.0f values for %.0f present rows",
              col, (double) nv, (double) present);
    if (dict && iw > 0) rmd_rle_init(&x, b, (R_xlen_t) ip - 1, len, iw);
    SEXP out = PROTECT(allocVector(t, n));
    R_xlen_t k = 0;
    for (R_xlen_t i = 0; i < n; i++) {
        R_xlen_t j = -1;
        if (dp > 0) rmd_rle_next(&d, &v); else v = 1;
        if (v) {
            j = k;
            if (dict) {
                int ix = 0;
                if (iw > 0 && !rmd_rle_next(&x, &ix))
                    error("parquet: RLE data ran out after %.0f of %.0f values",
                          (double) k, (double) present);
                if ((R_xlen_t) ix >= nv)
                    error("parquet: dictionary index out of range in column %s", col);
                j = ix;
            }
            k++;
        }
        switch (t) {
        case STRSXP: SET_STRING_ELT(out, i, j < 0 ? NA_STRING : STRING_ELT(vals, j)); break;
        case INTSXP: INTEGER(out)[i] = j < 0 ? NA_INTEGER : INTEGER(vals)[j]; break;
        case LGLSXP: LOGICAL(out)[i] = j < 0 ? NA_LOGICAL : LOGICAL(vals)[j]; break;
        case REALSXP: REAL(out)[i] = j < 0 ? NA_REAL : REAL(vals)[j]; break;
        default: SET_VECTOR_ELT(out, i, j < 0 ? R_NilValue : VECTOR_ELT(vals, j));
        }
    }
    UNPROTECT(1);
    return out;
}
