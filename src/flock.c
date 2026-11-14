/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * flock.c -- an exclusive lock per hosted table, so that R sessions
 * downloading the same table take turns.
 *
 * The lock is held by an open descriptor (flock(2) on POSIX, LockFileEx on
 * one byte on Windows): the kernel drops it when the descriptor is closed
 * or the process dies, so a killed R session never leaves a lock behind
 * and no session ever has to decide that another's lock is stale. The lock
 * file itself stays; only the lock on it matters.
 *
 * C_rmd_flock_with(path, fn, busy) takes the lock without waiting and runs
 * fn() under it in one C frame, the release registered with R as that
 * frame's cleanup (R_ExecWithCleanup): an error or an interrupt inside
 * fn() unwinds through the release. When another process holds the lock,
 * `busy` is returned at once and the caller waits in R, where Ctrl-C works.
 */
#include <R.h>
#include <Rinternals.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

#ifdef _WIN32
#include <windows.h>
#include <io.h>
#define RMD_CLOSE _close
#else
#include <unistd.h>
#include <sys/file.h>
#define RMD_CLOSE close
#endif

#ifndef S_ISREG
#define S_ISREG(m) (((m) & S_IFMT) == S_IFREG)
#endif
#ifndef O_CLOEXEC
#define O_CLOEXEC 0
#endif
#ifndef O_NOFOLLOW
#define O_NOFOLLOW 0
#endif

/* The descriptor of the held lock, or -1 when another process holds it. */
static int rmd_flock_try(const char *p) {
#ifdef _WIN32
    int fd = _open(p, _O_RDWR | _O_CREAT | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE);
#else
    int fd = open(p, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
#endif
    if (fd < 0) {
        int e = errno;
        error("cannot open the lock file %s: %s", p, strerror(e));
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
        RMD_CLOSE(fd);
        error("the lock file %s is not a regular file", p);
    }
#ifdef _WIN32
    HANDLE h = (HANDLE) _get_osfhandle(fd);
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    if (LockFileEx(h, LOCKFILE_EXCLUSIVE_LOCK | LOCKFILE_FAIL_IMMEDIATELY, 0, 1, 0, &ov)) return fd;
    DWORD we = GetLastError();
    RMD_CLOSE(fd);
    if (we == ERROR_LOCK_VIOLATION || we == ERROR_IO_PENDING) return -1;
    error("the lock file %s cannot be locked (Windows error %lu)", p, (unsigned long) we);
#else
    if (flock(fd, LOCK_EX | LOCK_NB) == 0) return fd;
    int e = errno;
    RMD_CLOSE(fd);
    if (e == EWOULDBLOCK || e == EAGAIN || e == EINTR) return -1;
    error("the lock file %s cannot be locked: %s", p, strerror(e));
#endif
    return -1; /* not reached */
}

static void rmd_flock_close(int fd) {
#ifdef _WIN32
    HANDLE h = (HANDLE) _get_osfhandle(fd);
    OVERLAPPED ov;
    memset(&ov, 0, sizeof ov);
    UnlockFileEx(h, 0, 1, 0, &ov);
#else
    flock(fd, LOCK_UN);
#endif
    RMD_CLOSE(fd);
}

static SEXP rmd_flock_call_fn(void *d) {
    SEXP call = PROTECT(lang1((SEXP) d));
    SEXP r = eval(call, R_GlobalEnv);
    UNPROTECT(1);
    return r;
}

static void rmd_flock_cleanup(void *d) {
    rmd_flock_close(*(int *) d);
}

SEXP C_rmd_flock_with(SEXP path, SEXP fn, SEXP busy) {
    if (!isString(path) || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
        error("`path` must be a single file path");
    if (!isFunction(fn)) error("`fn` must be a function");
    int fd = rmd_flock_try(R_ExpandFileName(translateChar(STRING_ELT(path, 0))));
    if (fd < 0) return busy;
    return R_ExecWithCleanup(rmd_flock_call_fn, (void *) fn, rmd_flock_cleanup, &fd);
}
