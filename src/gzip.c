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
#include <R_ext/Utils.h>

/* Whether the user has asked to stop: the check is made under a context of its
 * own, so it returns here and the stream can be released before the call ends. */
static void rmd_gz_chk(void *d) {
    (void) d;
    R_CheckUserInterrupt();
}

static int rmd_gz_stop(void) {
    return !R_ToplevelExec(rmd_gz_chk, NULL);
}

/* One gzip member of `x` at deflate level `level` (0: stored, not compressed). */
static SEXP rmd_deflate(SEXP x, int level) {
    if (TYPEOF(x) != RAWSXP) Rf_error("gzip: expected a raw vector");
    z_stream s;
    memset(&s, 0, sizeof s);
    if (deflateInit2(&s, level, Z_DEFLATED, 15 + 16, 9, Z_DEFAULT_STRATEGY) != Z_OK)
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

SEXP C_rmd_gzip_compress(SEXP x) { return rmd_deflate(x, 9); }

/* For data/R: bytes as one gzip member, stored as they are, for gzcon(), which
 * passes bytes through as they are only when they do not start as gzip does. */
SEXP C_rmd_gzip_store(SEXP x) { return rmd_deflate(x, 0); }

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

/* ---- the text of a .gz file ------------------------------------------------ */

/* Inflates every member of `in` (RFC 1952: a .gz file is one or more members)
 * into `out` (`cap` bytes), or only counts the bytes when `out` is NULL. NUL
 * bytes after the last member are ignored, as gzip -d ignores them. Returns 0
 * with *total set; 1 when the data is damaged (a member that is not valid
 * deflate data, fails its CRC-32 or length, or is cut short), with *why set;
 * 2 when bytes after a member are neither a member nor NUL padding, with
 * *at their offset. Input and output are fed to zlib in pieces of at most
 * 1 GiB, as its counts are 32-bit. */
static int rmd_gunzip_run(const unsigned char *in, double len, unsigned char *out,
                          double cap, double *total, const char **why, double *at) {
    unsigned char scratch[16384];
    z_stream s;
    memset(&s, 0, sizeof s);
    if (inflateInit2(&s, 15 + 16) != Z_OK) Rf_error("gzip: inflateInit2 failed");
    double fed = 0, used = 0;
    unsigned long turn = 0;
    *total = 0;
    for (;;) {
        int rc;
        do {
            /* every 4 MiB counted (256 blocks), and before each block written */
            if ((!out && (++turn & 255UL) == 0) || (out && turn++ > 0)) {
                if (rmd_gz_stop()) {
                    inflateEnd(&s);
                    Rf_error("gzip: interrupted");
                }
            }
            if (s.avail_in == 0 && fed < len) {
                double k = len - fed < 1073741824.0 ? len - fed : 1073741824.0;
                s.next_in = (Bytef *) (in + (size_t) fed);
                s.avail_in = (uInt) k;
                fed += k;
            }
            double room = out ? cap - *total : (double) sizeof scratch;
            if (room > 1073741824.0) room = 1073741824.0;
            s.next_out = out ? out + (size_t) *total : scratch;
            s.avail_out = (uInt) room;
            rc = inflate(&s, Z_NO_FLUSH);
            *total += room - (double) s.avail_out;
            if (rc == Z_MEM_ERROR) {
                inflateEnd(&s);
                Rf_error("gzip: not enough memory to inflate");
            }
            if (rc == Z_NEED_DICT || rc == Z_DATA_ERROR || rc == Z_STREAM_ERROR) {
                *why = s.msg ? s.msg : "not valid gzip data";
                inflateEnd(&s);
                return 1;
            }
            /* no progress: `out` is full, or the input is used up inside a member */
            if (rc == Z_BUF_ERROR) {
                inflateEnd(&s);
                if (out && *total >= cap)
                    Rf_error("gzip: the data inflated to more than it did when counted");
                *why = "the data ends inside a gzip member";
                return 1;
            }
        } while (rc != Z_STREAM_END);
        used = fed - (double) s.avail_in;
        double rest = len - used;
        const unsigned char *r = in + (size_t) used;
        size_t z = 0;
        while ((double) z < rest && r[z] == 0) z++;
        if ((double) z == rest) break; /* the end, or NUL padding only */
        if (rest < 2 || r[0] != 0x1f || r[1] != 0x8b) {
            *at = used;
            inflateEnd(&s);
            return 2;
        }
        if (inflateReset(&s) != Z_OK) {
            inflateEnd(&s);
            Rf_error("gzip: inflateReset failed");
        }
        s.next_in = (Bytef *) r;
        s.avail_in = (uInt) (rest < 1073741824.0 ? rest : 1073741824.0);
        fed = used + (double) s.avail_in;
    }
    inflateEnd(&s);
    return 0;
}

/* The inflated bytes of a .gz file, counted first and then inflated into a
 * vector of that size (a buffer grown as it went took twice the text); or, when
 * it cannot be inflated, c(kind, message): kind "damage" for damaged data,
 * "trailer" for bytes after the last member that are not one. */
SEXP C_rmd_gunzip(SEXP x) {
    if (TYPEOF(x) != RAWSXP) Rf_error("gzip: expected a raw vector");
    const char *why = NULL;
    char msg[256];
    double len = (double) XLENGTH(x), total = 0, at = 0;
    int rc = rmd_gunzip_run(RAW(x), len, NULL, 0, &total, &why, &at);
    if (rc == 0) {
        if (total > (double) R_XLEN_T_MAX)
            Rf_error("gzip: the data inflates to %.0f bytes, more than this R can allocate", total);
        SEXP out = PROTECT(allocVector(RAWSXP, (R_xlen_t) total));
        double again = 0;
        rc = rmd_gunzip_run(RAW(x), len, total > 0 ? RAW(out) : NULL, total, &again, &why, &at);
        if (rc == 0 && again == total) {
            UNPROTECT(1);
            return out;
        }
        UNPROTECT(1);
        Rf_error("gzip: the data inflated differently a second time");
    }
    if (rc == 1) snprintf(msg, sizeof msg, "the gzip data is damaged (%s)", why);
    else snprintf(msg, sizeof msg, "%.0f bytes after the last gzip member (from byte %.0f) are "
                  "not gzip data", len - at, at + 1);
    SEXP out = PROTECT(allocVector(STRSXP, 2));
    SET_STRING_ELT(out, 0, mkChar(rc == 1 ? "damage" : "trailer"));
    SET_STRING_ELT(out, 1, mkChar(msg));
    UNPROTECT(1);
    return out;
}
