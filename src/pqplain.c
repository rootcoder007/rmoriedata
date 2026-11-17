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
 * C_rmd_pq_rle reads the RLE / bit-packed hybrid, C_rmd_pq_rows puts a data
 * page's values (or its dictionary's) into their rows, and C_rmd_pq_flba reads
 * FIXED_LEN_BYTE_ARRAY values; C_rmd_pq_ints reads INT32, INT64 and unsigned
 * 32-bit words, C_rmd_pq_secs reads INT64 and INT96 times as seconds, and
 * C_rmd_pq_i64 writes INT64 values; see each below.
 */
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <stdint.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

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
            if (v > 1)
                error("parquet: column %s has a definition level of %d, above its "
                      "maximum of 1", col, v);
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

/* C_rmd_pq_flba(buf, pos, count, width, kind): `count` FIXED_LEN_BYTE_ARRAY values
 * of `width` bytes each, from the 1-based byte `pos` of `buf`, as a vector of what
 * they mean, never a list of raw vectors (56 bytes of overhead a value, and copies
 * of every byte of a long one):
 *   kind 1, DECIMAL: the unscaled value, a big-endian two's complement whole
 *     number of any width, as the nearest double. Only its leading 8 significant
 *     bytes and whether any byte after them is nonzero matter to that: the 64 bits
 *     are converted once, with the rest folded into the lowest bit, which rounds
 *     as the whole number would. Past the range of a double it is infinite, and
 *     the R side refuses it. A width of 200 holding 1 was 0 * 256^199 = NaN.
 *   kind 2, UUID: its 16 bytes as lower-case text, 8-4-4-4-12.
 *   kind 3, FLOAT16: the IEEE half-precision number, little-endian.
 * A bound the caller has already checked is checked again: the block must lie
 * inside `buf`. */
static uint8_t rmd_mag(const unsigned char *p, R_xlen_t j, int neg, R_xlen_t t) {
    /* byte j of |x| for x = p[0 .. w-1]: for a negative x, ~x + 1, where the
     * carry of the +1 stops at the last nonzero byte t of x */
    if (!neg) return p[j];
    if (j < t) return (uint8_t) (255 - p[j]);
    return j == t ? (uint8_t) (256 - p[j]) : 0;
}

SEXP C_rmd_pq_flba(SEXP buf, SEXP pos, SEXP count, SEXP width, SEXP kind_) {
    if (TYPEOF(buf) != RAWSXP) error("parquet: internal: `buf` must be raw");
    double p0 = asReal(pos), nc = asReal(count), wd = asReal(width);
    int kind = asInteger(kind_);
    R_xlen_t len = XLENGTH(buf);
    if (!R_FINITE(p0) || p0 < 1 || !R_FINITE(nc) || nc < 0 || nc > (double) INT_MAX ||
        !R_FINITE(wd) || wd < 1 || wd > (double) INT_MAX ||
        wd != (double) (R_xlen_t) wd || kind < 1 || kind > 3 ||
        (kind == 2 && wd != 16) || (kind == 3 && wd != 2) ||
        nc * wd > (double) len - (p0 - 1))
        error("parquet: internal: bad position, count or width");
    R_xlen_t n = (R_xlen_t) nc, w = (R_xlen_t) wd;
    const unsigned char *b = RAW(buf) + (R_xlen_t) p0 - 1;
    if (kind == 2) {
        static const char hx[] = "0123456789abcdef";
        SEXP out = PROTECT(allocVector(STRSXP, n));
        char s[37];
        for (R_xlen_t i = 0; i < n; i++) {
            const unsigned char *p = b + i * 16;
            int o = 0;
            for (int j = 0; j < 16; j++) {
                if (j == 4 || j == 6 || j == 8 || j == 10) s[o++] = '-';
                s[o++] = hx[p[j] >> 4];
                s[o++] = hx[p[j] & 15];
            }
            s[o] = 0;
            SET_STRING_ELT(out, i, mkChar(s));
        }
        UNPROTECT(1);
        return out;
    }
    SEXP out = PROTECT(allocVector(REALSXP, n));
    double *o = REAL(out);
    for (R_xlen_t i = 0; i < n; i++) {
        const unsigned char *p = b + i * w;
        if (kind == 3) {
            unsigned int h = (unsigned int) p[0] | ((unsigned int) p[1] << 8);
            int e = (int) ((h >> 10) & 31);
            double f = (double) (h & 1023);
            double v = e == 0 ? ldexp(f, -24) :
                e == 31 ? (f != 0 ? R_NaN : R_PosInf) : ldexp(f + 1024, e - 25);
            o[i] = (h & 0x8000) ? -v : v;
            continue;
        }
        int neg = p[0] >= 128;
        R_xlen_t t = w - 1;
        if (neg) while (t > 0 && p[t] == 0) t--;
        R_xlen_t f = 0;
        while (f < w && rmd_mag(p, f, neg, t) == 0) f++;
        R_xlen_t m = w - f, top = m < 8 ? m : 8;
        uint64_t u = 0;
        for (R_xlen_t j = 0; j < top; j++) u = (u << 8) | rmd_mag(p, f + j, neg, t);
        if (m > 8) {
            /* sticky bit: u has at least 57 bits, so bit 0 lies below the
             * rounding position and only says "a little more than u" */
            int sticky = neg ? t >= f + 8 : 0;
            for (R_xlen_t j = f + 8; !neg && j < w && !sticky; j++) sticky = p[j] != 0;
            u |= (uint64_t) sticky;
        }
        double v = (double) u;
        if (m > 8) v = (m - 8) * 8.0 > 2000.0 ? R_PosInf : ldexp(v, (int) ((m - 8) * 8));
        o[i] = neg ? -v : v;
    }
    UNPROTECT(1);
    return out;
}

/* C_rmd_pq_ints(buf, pos, count, width, unsigned): `count` little-endian whole
 * numbers of `width` bytes (4 or 8) from the 1-based byte `pos` of `buf`, read as
 * whole words, never through an R integer: readBin(size = 4) gives NA for the word
 * 0x80000000, which is a value of every 32-bit half (2^31 as an INT64's low word,
 * -2^63 and up as its high word, 2^31 as a UINT_32), and gave it without a word.
 *   width 4, signed: INT32, as integers; when one of them is -2^31, which no R
 *     integer holds, all of them as doubles.
 *   width 4, unsigned: 0 to 2^32 - 1 as doubles (UINT_32, lengths, Julian days).
 *   width 8: INT64 or UINT_64 as the nearest double, ties to even, rounded once
 *     (the R side warns from 2^53 up). A UINT_64 rounded as the signed value and
 *     then moved up by 2^64 was rounded twice. */
SEXP C_rmd_pq_ints(SEXP buf, SEXP pos, SEXP count, SEXP width, SEXP unsigned_) {
    if (TYPEOF(buf) != RAWSXP) error("parquet: internal: `buf` must be raw");
    double p0 = asReal(pos), nc = asReal(count);
    int w = asInteger(width), uns = asLogical(unsigned_);
    R_xlen_t len = XLENGTH(buf);
    if (!R_FINITE(p0) || p0 < 1 || !R_FINITE(nc) || nc < 0 ||
        (w != 4 && w != 8) || uns == NA_LOGICAL || nc * w > (double) len - (p0 - 1))
        error("parquet: internal: bad position, count or width");
    R_xlen_t n = (R_xlen_t) nc;
    const unsigned char *b = RAW(buf) + (R_xlen_t) p0 - 1;
    int real = uns || w == 8;
    for (R_xlen_t i = 0; i < n && !real; i++)
        real = b[4 * i] == 0 && b[4 * i + 1] == 0 && b[4 * i + 2] == 0 &&
            b[4 * i + 3] == 0x80;
    SEXP out = PROTECT(allocVector(real ? REALSXP : INTSXP, n));
    for (R_xlen_t i = 0; i < n; i++) {
        const unsigned char *p = b + i * w;
        uint64_t u = 0;
        for (int k = w - 1; k >= 0; k--) u = (u << 8) | p[k];
        uint32_t u4 = (uint32_t) u;
        int32_t s4;
        int64_t s8;
        memcpy(&s4, &u4, 4); /* two's complement, as int32_t and int64_t are */
        memcpy(&s8, &u, 8);
        if (!real) INTEGER(out)[i] = (int) s4; /* none is -2^31, R's NA */
        else if (w == 4) REAL(out)[i] = uns ? (double) u4 : (double) s4;
        else REAL(out)[i] = uns ? (double) u : (double) s8;
    }
    UNPROTECT(1);
    return out;
}

/* The nearest double to S + r / per (0 <= r < per; per 10^d, d = 3, 6 or 9), rounded
 * once. Converting the count to a double and dividing it rounded twice: a time in
 * nanoseconds is past 2^53, so the count was already rounded before the division.
 * Fast path: s + f, with f = r / per rounded once, is s + r / per to within 2^-54,
 * and Fast2Sum gives its own rounding error exactly; unless that leaves the exact
 * value within 2^-53 of half a unit in the last place either side, it rounds to the
 * same double. Otherwise, and past 2^53 seconds, the C library's correctly rounded
 * strtod() reads the exact value written in decimal (no decimal point, so no locale
 * enters into it). */
static double rmd_secs(int64_t S, int64_t r, int64_t per, int d) {
    const int64_t big = (int64_t) 1 << 53;
    if (S == 0) return (double) r / (double) per;
    if (S > -big && S < big) {
        double s = (double) S, f = (double) r / (double) per, x = s + f;
        double err = f - (x - s);
        double up = (nextafter(x, R_PosInf) - x) / 2, dn = (x - nextafter(x, R_NegInf)) / 2;
        if (up - err > 0x1p-53 && dn + err > 0x1p-53) return x;
    }
    /* S + r / per = -(-S - 1 + (per - r) / per) when S < 0 and r > 0 */
    int neg = S < 0;
    int64_t q = neg ? (r ? -S - 1 : -S) : S, m = neg && r ? per - r : r;
    char txt[64];
    snprintf(txt, sizeof txt, "%s%lld%0*llde-%d", neg ? "-" : "", (long long) q, d,
             (long long) m, d);
    return strtod(txt, NULL);
}

/* C_rmd_pq_secs(buf, pos, count, width, per): `count` times from the 1-based byte
 * `pos` of `buf` as seconds since the epoch, each the nearest double to its exact
 * value:
 *   width 8: INT64 counts of 1 / per seconds (a TIMESTAMP or TIME in MILLIS,
 *     MICROS or NANOS; per 1e3, 1e6 or 1e9);
 *   width 12: INT96, nanoseconds within the day (8 bytes, signed) and the Julian
 *     day (4 bytes, unsigned; 2440588 is 1970-01-01); per 1e9.
 * Whole seconds and the remainder are split in 64-bit integers (the INT96 day is at
 * most 2^32 days, 3.7e14 seconds), then combined once by rmd_secs(). */
SEXP C_rmd_pq_secs(SEXP buf, SEXP pos, SEXP count, SEXP width, SEXP per_) {
    if (TYPEOF(buf) != RAWSXP) error("parquet: internal: `buf` must be raw");
    double p0 = asReal(pos), nc = asReal(count), pd = asReal(per_);
    int w = asInteger(width);
    R_xlen_t len = XLENGTH(buf);
    int d = pd == 1e3 ? 3 : pd == 1e6 ? 6 : pd == 1e9 ? 9 : 0;
    if (!R_FINITE(p0) || p0 < 1 || !R_FINITE(nc) || nc < 0 || (w != 8 && w != 12) ||
        !d || (w == 12 && d != 9) || nc * w > (double) len - (p0 - 1))
        error("parquet: internal: bad position, count, width or unit");
    R_xlen_t n = (R_xlen_t) nc;
    int64_t per = (int64_t) pd;
    const unsigned char *b = RAW(buf) + (R_xlen_t) p0 - 1;
    SEXP out = PROTECT(allocVector(REALSXP, n));
    double *o = REAL(out);
    for (R_xlen_t i = 0; i < n; i++) {
        const unsigned char *p = b + i * w;
        uint64_t u = 0;
        for (int k = 7; k >= 0; k--) u = (u << 8) | p[k];
        int64_t v, S, r;
        memcpy(&v, &u, 8); /* two's complement, as int64_t is */
        S = v / per;
        r = v % per;
        if (r < 0) {
            r += per;
            S -= 1;
        }
        if (w == 12) {
            uint32_t jd = (uint32_t) p[8] | ((uint32_t) p[9] << 8) |
                ((uint32_t) p[10] << 16) | ((uint32_t) p[11] << 24);
            S += ((int64_t) jd - 2440588) * 86400;
        }
        o[i] = rmd_secs(S, r, per, d);
    }
    UNPROTECT(1);
    return out;
}

/* C_rmd_pq_i64(x, per): the doubles `x` as INT64 values, 8 little-endian bytes each,
 * made from the 64-bit value itself. The R side split them into two 32-bit halves
 * for writeBin(), and a low half of 2^31 went through as.integer() as NA.
 *   per 1: `x` are whole numbers above -2^63 and below 2^63 (the writer has refused
 *     others), written as they are.
 *   per 1e6: `x` are times in seconds, each written as the whole number of
 *     microseconds nearest to it (ties to even), worked out exactly: |x| is split
 *     into whole seconds and a fraction f (both exact), the fraction's microseconds
 *     are found with fma(), which rounds f * 10^6 - c once and so keeps its sign,
 *     and the two are joined in 64-bit integers. A time read from a file of
 *     milliseconds or microseconds is the nearest double to its count, and that
 *     count is what is written back. */
static int rmd_us(double x, int64_t *us) {
    double a = fabs(x), fl = floor(a), f = a - fl, c = floor(f * 1e6);
    while (fma(f, 1e6, -c) < 0) c -= 1;
    while (fma(f, 1e6, -(c + 1)) >= 0) c += 1;
    double h = fma(f, 1e6, -(c + 0.5));
    if (h > 0 || (h == 0 && fmod(c, 2) != 0)) c += 1;
    /* the whole seconds and c (at most 10^6) must make a count below 2^63, compared
     * in integers: a bound of 2^63 / 10^6 in doubles is rounded */
    if (!(fl < 9223372036854775808.0)) return 0;
    int64_t S = (int64_t) fl;
    if (S > (INT64_MAX - (int64_t) c) / 1000000) return 0;
    int64_t u = S * 1000000 + (int64_t) c;
    *us = x < 0 ? -u : u;
    return 1;
}

/* C_rmd_pq_usfit(x): for each double `x` (times in seconds), TRUE when it is finite
 * and its nearest whole microsecond (ties to even) is a count a TIMESTAMP_MICROS
 * holds, from -(2^63 - 1) to 2^63 - 1; FALSE otherwise. NA and NaN, which the
 * writer writes as missing, are NA. */
SEXP C_rmd_pq_usfit(SEXP x) {
    if (TYPEOF(x) != REALSXP) error("parquet: internal: `x` must be double");
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(allocVector(LGLSXP, n));
    const double *v = REAL(x);
    int *o = LOGICAL(out);
    int64_t us;
    for (R_xlen_t i = 0; i < n; i++)
        o[i] = ISNAN(v[i]) ? NA_LOGICAL : (R_FINITE(v[i]) && rmd_us(v[i], &us));
    UNPROTECT(1);
    return out;
}

SEXP C_rmd_pq_i64(SEXP x, SEXP per_) {
    if (TYPEOF(x) != REALSXP) error("parquet: internal: `x` must be double");
    double per = asReal(per_);
    if (per != 1 && per != 1e6) error("parquet: internal: `per` must be 1 or 1e6");
    R_xlen_t n = XLENGTH(x);
    if ((double) n * 8.0 > (double) R_XLEN_T_MAX) error("parquet: column too large to write");
    SEXP out = PROTECT(allocVector(RAWSXP, n * 8));
    unsigned char *o = RAW(out);
    const double *v = REAL(x);
    for (R_xlen_t i = 0; i < n; i++) {
        if (!(v[i] > -9223372036854775808.0 && v[i] < 9223372036854775808.0) ||
            (per == 1 && v[i] != floor(v[i])))
            error("parquet: internal: %g is not a 64-bit whole number", v[i]);
        int64_t s;
        if (per == 1) s = (int64_t) v[i];
        else if (!rmd_us(v[i], &s))
            error("parquet: internal: %g seconds is past the range of a TIMESTAMP",
                  v[i]);
        uint64_t u;
        memcpy(&u, &s, 8);
        for (int k = 0; k < 8; k++) o[8 * i + k] = (unsigned char) (u >> (8 * k));
    }
    UNPROTECT(1);
    return out;
}
