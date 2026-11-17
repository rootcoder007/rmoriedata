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

/* C_rmd_pq_rle(buf, pos, width, count, end): `count` values of the RLE /
 * bit-packed hybrid starting at the 1-based byte `pos` of `buf`, read no
 * further than the 1-based byte `end`; `width` is 1 to 32 bits. Returns
 * list(values, pos). One pass in C: a page of runs of one value each cost
 * the R loop a second per hundred thousand rows. */
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
    R_xlen_t n = (R_xlen_t) nc, o = 0;
    int nbytes = (w + 7) / 8;
    const unsigned char *b = RAW(buf);
    SEXP vals = PROTECT(allocVector(INTSXP, n));
    int *out = INTEGER(vals);
    while (o < n && p < e) {
        uint64_t header = 0;
        int shift = 0;
        for (;;) {
            if (p >= e) error("parquet: RLE run header runs past its data");
            unsigned char c = b[p++];
            header |= (uint64_t) (c & 127) << shift;
            if (!(c & 128)) break;
            shift += 7;
            if (shift > 63) error("parquet: RLE run header longer than 10 bytes");
        }
        uint64_t left = (uint64_t) (n - o);
        if (header & 1) { /* bit-packed: groups of eight values */
            uint64_t groups = header >> 1;
            if (groups > (uint64_t) (e - p) / (uint64_t) w)
                error("parquet: bit-packed run of %.0f groups runs past its data",
                      (double) groups);
            uint64_t nvals = groups * 8, take = nvals < left ? nvals : left, bit = 0;
            const unsigned char *q = b + p;
            for (uint64_t i = 0; i < take; i++) {
                uint64_t v = 0;
                for (int k = 0; k < w; k++, bit++)
                    v |= (uint64_t) ((q[bit >> 3] >> (bit & 7)) & 1) << k;
                if (v > (uint64_t) INT_MAX) error("parquet: RLE value above 2^31");
                out[o + (R_xlen_t) i] = (int) v;
            }
            o += (R_xlen_t) take;
            p += (R_xlen_t) (groups * (uint64_t) w);
        } else { /* a run of one value */
            uint64_t run = header >> 1, take = run < left ? run : left, v = 0;
            if (e - p < nbytes) error("parquet: RLE run value runs past its data");
            for (int k = 0; k < nbytes; k++) v |= (uint64_t) b[p + k] << (8 * k);
            p += nbytes;
            if (v > (uint64_t) INT_MAX) error("parquet: RLE value above 2^31");
            for (uint64_t i = 0; i < take; i++) out[o + (R_xlen_t) i] = (int) v;
            o += (R_xlen_t) take;
        }
    }
    if (o < n)
        error("parquet: RLE data ran out after %.0f of %.0f values", (double) o, (double) n);
    SEXP res = PROTECT(allocVector(VECSXP, 2));
    SEXP nm = PROTECT(allocVector(STRSXP, 2));
    SET_STRING_ELT(nm, 0, mkChar("values"));
    SET_STRING_ELT(nm, 1, mkChar("pos"));
    setAttrib(res, R_NamesSymbol, nm);
    SET_VECTOR_ELT(res, 0, vals);
    SET_VECTOR_ELT(res, 1, ScalarInteger((int) (p + 1)));
    UNPROTECT(3);
    return res;
}
