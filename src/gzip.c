/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * gzip.c -- the Parquet GZIP page codec (RFC 1952 members) through zlib,
 * which R itself links. Compression at level 9; decompression accepts one or
 * more gzip members, or one zlib stream (windowBits 15 + 32 detects the header).
 */
#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <string.h>
#include <zlib.h>

SEXP C_rmd_gzip_compress(SEXP x) {
    if (TYPEOF(x) != RAWSXP) Rf_error("gzip: expected a raw vector");
    z_stream s;
    memset(&s, 0, sizeof s);
    if (deflateInit2(&s, 9, Z_DEFLATED, 15 + 16, 9, Z_DEFAULT_STRATEGY) != Z_OK)
        Rf_error("gzip: deflateInit2 failed");
    /* avail_in and avail_out are 32-bit: a larger page would be cut short silently */
    if ((double) XLENGTH(x) > 4.0e9) {
        deflateEnd(&s);
        Rf_error("gzip: a page of %.0f bytes is more than this codec takes", (double) XLENGTH(x));
    }
    uLong bound = deflateBound(&s, (uLong) XLENGTH(x)) + 32;
    unsigned char *buf = (unsigned char *) R_alloc(bound, 1);
    s.next_in = (Bytef *) RAW(x);
    s.avail_in = (uInt) XLENGTH(x);
    s.next_out = buf;
    s.avail_out = (uInt) bound;
    int rc = deflate(&s, Z_FINISH);
    if (rc != Z_STREAM_END) { deflateEnd(&s); Rf_error("gzip: deflate failed (%d)", rc); }
    size_t n = (size_t) s.total_out;
    deflateEnd(&s);
    if ((double) n > (double) R_XLEN_T_MAX) Rf_error("gzip: the compressed page is more than this R can allocate");
    SEXP out = PROTECT(allocVector(RAWSXP, (R_xlen_t) n));
    memcpy(RAW(out), buf, n);
    UNPROTECT(1);
    return out;
}

/* RFC 1952, 2.2: a gzip file is a series of members, and a page may hold several
 * (concatenated gzip output). Each is inflated in turn into the one buffer of the
 * stated size, so the bounds below hold for all of them together: no member writes
 * past `want`, and a member split from a bomb stops there. A page must come out at
 * exactly `want` bytes with all its input used: bytes after the last member that are
 * not a member are refused, as is a zlib stream followed by anything. */
SEXP C_rmd_gzip_decompress(SEXP x, SEXP size) {
    if (TYPEOF(x) != RAWSXP) Rf_error("gzip: expected a raw vector");
    double want = asReal(size);
    if (!R_FINITE(want) || want < 0 || want != floor(want)) Rf_error("gzip: bad uncompressed size");
    /* avail_in is 32-bit: a longer page would be cut short without a word */
    if ((double) XLENGTH(x) > 4294967295.0)
        Rf_error("gzip: a page of %.0f bytes is more than this codec takes", (double) XLENGTH(x));
    /* checked before allocating, as in snappy.c: deflate expands at most 1032 to 1, and avail_out is 32-bit */
    if (want > 4294967295.0 || want > (double) XLENGTH(x) * 1032.0 + 1024.0)
        Rf_error("gzip: page states %.0f bytes, more than %.0f compressed bytes can hold", want, (double) XLENGTH(x));
    /* before the cast: where R_xlen_t is 32 bits, a larger size is undefined behaviour */
    if (want > (double) R_XLEN_T_MAX) Rf_error("gzip: page states %.0f bytes, more than this R can allocate", want);
    SEXP out = PROTECT(allocVector(RAWSXP, (R_xlen_t) want));
    unsigned char spare = 0; /* somewhere to point for a page of no bytes */
    const unsigned char *in = RAW(x);
    int gz = XLENGTH(x) >= 2 && in[0] == 0x1f && in[1] == 0x8b, rc;
    z_stream s;
    memset(&s, 0, sizeof s);
    if (inflateInit2(&s, 15 + 32) != Z_OK) Rf_error("gzip: inflateInit2 failed");
    s.next_in = (Bytef *) in;
    s.avail_in = (uInt) XLENGTH(x);
    s.next_out = want > 0 ? RAW(out) : &spare;
    s.avail_out = (uInt) want;
    for (;;) {
        rc = inflate(&s, Z_FINISH);
        if (rc != Z_STREAM_END || s.avail_in == 0 || !gz) break;
        /* the next bytes must be another gzip member, not a zlib stream */
        if (inflateReset2(&s, 15 + 16) != Z_OK) break;
    }
    /* total_out restarts at each member: what is left of the buffer counts */
    double got = want - (double) s.avail_out;
    uInt left = s.avail_in;
    inflateEnd(&s);
    if (rc == Z_STREAM_END && left == 0 && got == want) {
        UNPROTECT(1);
        return out;
    }
    if (got == want && left > 0)
        Rf_error("gzip: page holds data after its stated %.0f bytes", want);
    Rf_error("gzip: page did not decompress to its stated %.0f bytes", want);
    return R_NilValue; /* not reached */
}

/* CRC-32 (zlib's, the polynomial Parquet uses for PageHeader.crc) of a raw vector, as a
 * double so the unsigned 32-bit value survives. */
SEXP C_rmd_crc32(SEXP x) {
    if (TYPEOF(x) != RAWSXP) Rf_error("crc32: `x` must be a raw vector");
    uLong c = crc32(0L, Z_NULL, 0);
    R_xlen_t n = XLENGTH(x);
    const Bytef *p = (const Bytef *) RAW(x);
    while (n > 0) {
        uInt take = n > (R_xlen_t) 0x40000000 ? 0x40000000u : (uInt) n;
        c = crc32(c, p, take);
        p += take;
        n -= take;
    }
    return Rf_ScalarReal((double) c);
}
