/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * readfile.c -- the bytes of a file, read once, from a regular file only.
 *
 * The package checks a file (its SHA-256 against a signed or cached digest)
 * and then reads it. Checked by path and read again by path, a file replaced
 * between the two was read unchecked; so the bytes are read once, here, and
 * the check and the reader both use them. A path that is not a regular file
 * (a directory, a FIFO, a device, a socket) is refused before it is opened:
 * a FIFO blocked the reader for ever.
 *
 * C_rmd_readfile(path, max) returns a raw vector, or a string saying why the
 * file cannot be read (no file, not a regular file, larger than `max` bytes,
 * replaced while it was read, or the system's reason). The size is taken from
 * stat() and the vector allocated before the file is opened, so an allocation
 * error leaves no descriptor open; the open descriptor is then checked (fstat)
 * to be the same regular file, of the same size.
 */
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#ifdef _WIN32
#include <io.h>
#define RMD_OPEN(p) _open(p, _O_RDONLY | _O_BINARY | _O_NOINHERIT)
#define RMD_READ _read
#define RMD_CLOSE _close
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
#define RMD_READ read
#define RMD_CLOSE close
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

SEXP C_rmd_readfile(SEXP path, SEXP max_) {
    if (!isString(path) || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        error("`path` must be a single file path");
    double most = asReal(max_);
    const char *p = R_ExpandFileName(translateChar(STRING_ELT(path, 0)));
    struct stat st, fs;
    if (stat(p, &st) != 0) return rmd_why("cannot be read", errno);
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
    if (fstat(fd, &fs) != 0 || !S_ISREG(fs.st_mode) || !RMD_SAME(st, fs)) {
        RMD_CLOSE(fd);
        UNPROTECT(1);
        return rmd_why("was replaced while it was read", 0);
    }
    unsigned char *b = RAW(out);
    R_xlen_t got = 0;
    while (got < n) {
        size_t want = (size_t) (n - got);
        if (want > (1u << 30)) want = 1u << 30;
        long r = (long) RMD_READ(fd, b + got, (unsigned int) want);
        if (r < 0 && errno == EINTR) continue;
        if (r < 0) {
            int e = errno;
            RMD_CLOSE(fd);
            UNPROTECT(1);
            return rmd_why("cannot be read", e);
        }
        if (r == 0) break;
        got += (R_xlen_t) r;
    }
    RMD_CLOSE(fd);
    if (got != n) {
        UNPROTECT(1);
        return rmd_why("was replaced while it was read", 0);
    }
    UNPROTECT(1);
    return out;
}
