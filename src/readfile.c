/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * readfile.c -- the bytes of a file, from one open of a regular file only.
 *
 * The package checks a file (its SHA-256 against a signed or cached digest)
 * and then reads it. Checked by path and read again by path, a file replaced
 * between the two was read unchecked; so the file is opened once, here, and
 * the check and the reader both use what that one open gave. A path that is
 * not a regular file (a directory, a FIFO, a device, a socket) is refused
 * before it is opened: a FIFO blocked the reader for ever.
 *
 * C_rmd_readfile(path, max) returns a raw vector, or a string saying why the
 * file cannot be read (no file, not a regular file, larger than `max` bytes,
 * replaced while it was read, or the system's reason). The size is taken from
 * stat() and the vector allocated before the file is opened, so an allocation
 * error leaves no descriptor open; the open descriptor is then checked (fstat)
 * to be the same regular file, of the same size.
 *
 * A large file (the cache of chiload(full = TRUE)) is not held whole: held
 * whole and parsed, it took the file's size again on top of what the parse
 * needs. C_rmd_vopen(path, verify, max) opens it once and, with `verify` 1 or 2,
 * reads it through once, keeping its SHA-256 and (2) the SHA-256 of each 64 KiB
 * block; a file over `max` bytes is not opened (verify 1 is a digest alone);
 * C_rmd_vread(handle, start, n) then reads a range through the same
 * descriptor and checks every block it touches against the digest kept for
 * it, so the bytes handed to the parser are exactly bytes whose digest was
 * taken: a file renamed over this one is not seen (the descriptor is the old
 * file's), and one rewritten in place is an error ("changed while it was
 * read"). C_rmd_vclose(handle) closes the descriptor; the handle's finalizer
 * closes it too, should an error leave it open.
 *
 * On Windows the 64-bit stat is used (_stat64, _fstat64): the plain one holds
 * the size in 32 bits there, and a file over 2 GiB could not be read. That
 * branch is not compiled on the machines this package is checked on here.
 */
#include <R.h>
#include <Rinternals.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#ifdef _WIN32
#include <io.h>
#define RMD_OPEN(p) _open(p, _O_RDONLY | _O_BINARY | _O_NOINHERIT)
#define RMD_CLOSE _close
typedef struct _stat64 rmd_stat_t;
#define RMD_STAT _stat64
#define RMD_FSTAT _fstat64
#define RMD_SAME(a, b) ((a).st_size == (b).st_size)
#else
#include <unistd.h>
#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
#ifndef O_NOCTTY
#define O_NOCTTY 0
#endif
#define RMD_OPEN(p) open(p, O_RDONLY | O_NONBLOCK | O_NOCTTY | O_CLOEXEC)
#define RMD_CLOSE close
typedef struct stat rmd_stat_t;
#define RMD_STAT stat
#define RMD_FSTAT fstat
#define RMD_SAME(a, b) ((a).st_dev == (b).st_dev && (a).st_ino == (b).st_ino && \
                        (a).st_size == (b).st_size)
#endif

#ifndef S_ISREG
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif

static SEXP rmd_why(const char *what, int e) {
    char buf[256];
    if (e) snprintf(buf, sizeof buf, "%s (%s)", what, strerror(e));
    else snprintf(buf, sizeof buf, "%s", what);
    return mkString(buf);
}

/* Up to n bytes at offset `off` into b: the count read (short only at the end of
 * the file), or -1 with errno set. */
static double rmd_pread(int fd, unsigned char *b, double n, double off) {
#ifdef _WIN32
    if (_lseeki64(fd, (__int64) off, SEEK_SET) < 0) return -1;
#endif
    double got = 0;
    while (got < n) {
        double want = n - got;
        if (want > 1073741824.0) want = 1073741824.0;
#ifdef _WIN32
        long r = (long) _read(fd, b + (size_t) got, (unsigned int) want);
#else
        long r = (long) pread(fd, b + (size_t) got, (size_t) want, (off_t) (off + got));
#endif
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) return -1;
        if (r == 0) break;
        got += (double) r;
    }
    return got;
}

/* ---- SHA-256 (FIPS 180-4), fed in pieces ---------------------------------- */

typedef struct {
    uint32_t h[8];
    uint64_t len;
    unsigned char buf[64];
    size_t n;
} rmd_sha;

static const uint32_t rmd_k[64] = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
};

#define RMD_ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void rmd_sha_block(uint32_t *h, const unsigned char *p) {
    uint32_t w[64], a, b, c, d, e, f, g, k, t1, t2;
    for (int i = 0; i < 16; i++)
        w[i] = (uint32_t) p[4 * i] << 24 | (uint32_t) p[4 * i + 1] << 16 |
               (uint32_t) p[4 * i + 2] << 8 | (uint32_t) p[4 * i + 3];
    for (int i = 16; i < 64; i++) {
        uint32_t s0 = RMD_ROR(w[i - 15], 7) ^ RMD_ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
        uint32_t s1 = RMD_ROR(w[i - 2], 17) ^ RMD_ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    a = h[0]; b = h[1]; c = h[2]; d = h[3]; e = h[4]; f = h[5]; g = h[6]; k = h[7];
    for (int i = 0; i < 64; i++) {
        t1 = k + (RMD_ROR(e, 6) ^ RMD_ROR(e, 11) ^ RMD_ROR(e, 25)) + ((e & f) ^ (~e & g)) +
             rmd_k[i] + w[i];
        t2 = (RMD_ROR(a, 2) ^ RMD_ROR(a, 13) ^ RMD_ROR(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        k = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += k;
}

static void rmd_sha_init(rmd_sha *s) {
    static const uint32_t h0[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
    memcpy(s->h, h0, sizeof h0);
    s->len = 0;
    s->n = 0;
}

static void rmd_sha_add(rmd_sha *s, const unsigned char *p, size_t n) {
    s->len += (uint64_t) n;
    if (s->n) {
        size_t take = 64 - s->n < n ? 64 - s->n : n;
        memcpy(s->buf + s->n, p, take);
        s->n += take; p += take; n -= take;
        if (s->n < 64) return;
        rmd_sha_block(s->h, s->buf);
        s->n = 0;
    }
    for (; n >= 64; p += 64, n -= 64) rmd_sha_block(s->h, p);
    memcpy(s->buf, p, n);
    s->n = n;
}

static void rmd_sha_end(rmd_sha *s, unsigned char *out) {
    uint64_t bits = s->len * 8;
    unsigned char pad[72] = {0x80};
    size_t np = (s->n < 56 ? 56 : 120) - s->n;
    for (int i = 0; i < 8; i++) pad[np + i] = (unsigned char) (bits >> (56 - 8 * i));
    rmd_sha_add(s, pad, np + 8);
    for (int i = 0; i < 8; i++) {
        out[4 * i] = (unsigned char) (s->h[i] >> 24);
        out[4 * i + 1] = (unsigned char) (s->h[i] >> 16);
        out[4 * i + 2] = (unsigned char) (s->h[i] >> 8);
        out[4 * i + 3] = (unsigned char) s->h[i];
    }
}

static void rmd_sha_of(const unsigned char *p, size_t n, unsigned char *out) {
    rmd_sha s;
    rmd_sha_init(&s);
    rmd_sha_add(&s, p, n);
    rmd_sha_end(&s, out);
}

/* SHA-256 of a raw vector, lower-case hex: for the tests, which compare it with
 * the shared core's digest. */
SEXP C_rmd_sha256(SEXP x) {
    if (TYPEOF(x) != RAWSXP) error("`x` must be a raw vector");
    unsigned char d[32];
    char hex[65];
    rmd_sha_of(RAW(x), (size_t) XLENGTH(x), d);
    for (int i = 0; i < 32; i++) snprintf(hex + 2 * i, 3, "%02x", d[i]);
    return mkString(hex);
}

/* ---- whole files ----------------------------------------------------------- */

SEXP C_rmd_readfile(SEXP path, SEXP max_) {
    if (!isString(path) || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        error("`path` must be a single file path");
    double most = asReal(max_);
    const char *p = R_ExpandFileName(translateChar(STRING_ELT(path, 0)));
    rmd_stat_t st, fs;
    if (RMD_STAT(p, &st) != 0) return rmd_why("cannot be read", errno);
    if (!S_ISREG(st.st_mode)) return rmd_why("is not a regular file", 0);
    if (ISNAN(most) || (double) st.st_size > most)
        return rmd_why("is larger than it may be", 0);
    if ((double) st.st_size > (double) R_XLEN_T_MAX)
        return rmd_why("is too large to read", 0);
    R_xlen_t n = (R_xlen_t) st.st_size;
    SEXP out = PROTECT(allocVector(RAWSXP, n));
    int fd = RMD_OPEN(p);
    if (fd < 0) {
        int e = errno;
        UNPROTECT(1);
        return rmd_why("cannot be read", e);
    }
    if (RMD_FSTAT(fd, &fs) != 0 || !S_ISREG(fs.st_mode) || !RMD_SAME(st, fs)) {
        RMD_CLOSE(fd);
        UNPROTECT(1);
        return rmd_why("was replaced while it was read", 0);
    }
    double got = rmd_pread(fd, RAW(out), (double) n, 0);
    int e = errno;
    RMD_CLOSE(fd);
    UNPROTECT(1);
    if (got < 0) return rmd_why("cannot be read", e);
    if (got != (double) n) return rmd_why("was replaced while it was read", 0);
    return out;
}

/* ---- one open, read in ranges ---------------------------------------------- */

#define RMD_BLK 65536.0

typedef struct {
    int fd;
    double size;
    unsigned char *dig; /* 32 bytes a block; NULL when the file is not verified */
} rmd_vf;

static void rmd_vf_close(rmd_vf *v) {
    if (v->fd >= 0) RMD_CLOSE(v->fd);
    v->fd = -1;
    free(v->dig);
    v->dig = NULL;
}

static void rmd_vf_fin(SEXP h) {
    rmd_vf *v = (rmd_vf *) R_ExternalPtrAddr(h);
    if (!v) return;
    rmd_vf_close(v);
    free(v);
    R_ClearExternalPtr(h);
}

/* Reads the open file through once: its digest into `whole` (hex), and each
 * block's into v->dig. A read that comes up short, or a file whose size or
 * identity changed by the end, is a file replaced while it was read. */
static const char *rmd_vf_digest(rmd_vf *v, const rmd_stat_t *st, unsigned char *buf,
                                 char *whole, int *err) {
    unsigned char d[32];
    rmd_sha s;
    rmd_sha_init(&s);
    for (double off = 0, i = 0; off < v->size; off += RMD_BLK, i++) {
        double n = v->size - off < RMD_BLK ? v->size - off : RMD_BLK;
        double got = rmd_pread(v->fd, buf, n, off);
        if (got < 0) {
            *err = errno;
            return "cannot be read";
        }
        if (got != n) return "was replaced while it was read";
        rmd_sha_add(&s, buf, (size_t) n);
        if (v->dig) rmd_sha_of(buf, (size_t) n, v->dig + 32 * (size_t) i);
    }
    rmd_stat_t fs;
    if (RMD_FSTAT(v->fd, &fs) != 0 || !RMD_SAME(*st, fs)) return "was replaced while it was read";
    rmd_sha_end(&s, d);
    for (int i = 0; i < 32; i++) snprintf(whole + 2 * i, 3, "%02x", d[i]);
    return NULL;
}

/* list(handle, size, sha256), or a string saying why the file cannot be read.
 * Everything is allocated before the file is opened; once it is open, every
 * way out closes it or leaves it to the handle. */
SEXP C_rmd_vopen(SEXP path, SEXP verify_, SEXP max_) {
    if (!isString(path) || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        error("`path` must be a single file path");
    int mode = asInteger(verify_), verify = mode == 1 || mode == 2;
    double most = asReal(max_);
    const char *p = R_ExpandFileName(translateChar(STRING_ELT(path, 0)));
    rmd_stat_t st, fs;
    if (RMD_STAT(p, &st) != 0) return rmd_why("cannot be read", errno);
    if (!S_ISREG(st.st_mode)) return rmd_why("is not a regular file", 0);
    double size = (double) st.st_size, blocks = ceil(size / RMD_BLK);
    if (ISNAN(most) || size > most) return rmd_why("is larger than it may be", 0);
    rmd_vf *v = (rmd_vf *) calloc(1, sizeof *v);
    if (!v) error("cannot allocate the state of a file read");
    v->fd = -1;
    v->size = size;
    SEXP h = PROTECT(R_MakeExternalPtr(v, R_NilValue, R_NilValue));
    R_RegisterCFinalizerEx(h, rmd_vf_fin, TRUE);
    if (mode == 2 && blocks > 0) {
        v->dig = (unsigned char *) malloc((size_t) blocks * 32);
        if (!v->dig) error("cannot allocate the block digests of a %.0f-byte file", size);
    }
    SEXP out = PROTECT(allocVector(VECSXP, 3)), nm = PROTECT(allocVector(STRSXP, 3));
    SET_STRING_ELT(nm, 0, mkChar("handle"));
    SET_STRING_ELT(nm, 1, mkChar("size"));
    SET_STRING_ELT(nm, 2, mkChar("sha256"));
    setAttrib(out, R_NamesSymbol, nm);
    SET_VECTOR_ELT(out, 0, h);
    SET_VECTOR_ELT(out, 1, ScalarReal(size));
    SET_VECTOR_ELT(out, 2, ScalarString(NA_STRING));
    char whole[65];
    unsigned char *buf = verify ? (unsigned char *) R_alloc((size_t) RMD_BLK, 1) : NULL;
    int fd = RMD_OPEN(p), e = errno;
    if (fd < 0) {
        UNPROTECT(3);
        return rmd_why("cannot be read", e);
    }
    v->fd = fd;
    const char *why = NULL;
    e = 0;
    if (RMD_FSTAT(fd, &fs) != 0 || !S_ISREG(fs.st_mode) || !RMD_SAME(st, fs))
        why = "was replaced while it was read";
    else if (verify)
        why = rmd_vf_digest(v, &st, buf, whole, &e);
    if (why) {
        rmd_vf_close(v);
        UNPROTECT(3);
        return rmd_why(why, e);
    }
    if (verify) SET_VECTOR_ELT(out, 2, mkString(whole));
    UNPROTECT(3);
    return out;
}

static rmd_vf *rmd_vf_of(SEXP h) {
    rmd_vf *v = TYPEOF(h) == EXTPTRSXP ? (rmd_vf *) R_ExternalPtrAddr(h) : NULL;
    if (!v || v->fd < 0) error("parquet: the file is no longer open");
    return v;
}

/* One block (index b) into dst, checked against its digest. */
static void rmd_vf_block(rmd_vf *v, double b, unsigned char *dst) {
    double off = b * RMD_BLK, n = v->size - off < RMD_BLK ? v->size - off : RMD_BLK;
    double got = rmd_pread(v->fd, dst, n, off);
    if (got < 0) error("parquet: the file cannot be read (%s)", strerror(errno));
    if (got != n) error("parquet: the file was changed while it was read");
    unsigned char d[32];
    rmd_sha_of(dst, (size_t) n, d);
    if (memcmp(d, v->dig + 32 * (size_t) b, 32) != 0)
        error("parquet: the file was changed while it was read");
}

/* The bytes [start, start + n) of the open file, fewer when it ends sooner. */
SEXP C_rmd_vread(SEXP h, SEXP start_, SEXP n_) {
    rmd_vf *v = rmd_vf_of(h);
    double start = asReal(start_), n = asReal(n_);
    if (!R_FINITE(start) || !R_FINITE(n) || start < 0 || n < 0 ||
        start != floor(start) || n != floor(n))
        error("parquet: a range of the file must be whole numbers of bytes");
    if (n > v->size - start) n = v->size - start > 0 ? v->size - start : 0;
    if (n > (double) R_XLEN_T_MAX) error("parquet: a range of %.0f bytes is more than this R can allocate", n);
    SEXP out = PROTECT(allocVector(RAWSXP, (R_xlen_t) n));
    unsigned char *o = RAW(out);
    if (n > 0 && !v->dig) {
        double got = rmd_pread(v->fd, o, n, start);
        if (got < 0) error("parquet: the file cannot be read (%s)", strerror(errno));
        if (got != n) error("parquet: the file was changed while it was read");
    } else if (n > 0) {
        unsigned char *tmp = (unsigned char *) R_alloc((size_t) RMD_BLK, 1);
        for (double b = floor(start / RMD_BLK); b * RMD_BLK < start + n; b++) {
            double bs = b * RMD_BLK, be = bs + RMD_BLK < v->size ? bs + RMD_BLK : v->size;
            double a = start > bs ? start : bs, z = start + n < be ? start + n : be;
            if (a == bs && z == be) {
                rmd_vf_block(v, b, o + (size_t) (a - start)); /* wholly inside: in place */
            } else {
                rmd_vf_block(v, b, tmp);
                memcpy(o + (size_t) (a - start), tmp + (size_t) (a - bs), (size_t) (z - a));
            }
        }
    }
    UNPROTECT(1);
    return out;
}

SEXP C_rmd_vclose(SEXP h) {
    rmd_vf *v = TYPEOF(h) == EXTPTRSXP ? (rmd_vf *) R_ExternalPtrAddr(h) : NULL;
    if (v) rmd_vf_close(v);
    return R_NilValue;
}
