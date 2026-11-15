/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * strtod.c -- decimal text to doubles, correctly rounded on every platform.
 *
 * R's own conversion (R_strtod, behind read.csv(), as.numeric(), type.convert()
 * and scan()) accumulates the digits in a long double and scales by powers of
 * ten, so its last bit differs between platforms: "1.239042694" is
 * 1.2390426939999999 on ARM64 and 1.2390426940000001 on x86-64 (the nearest
 * double is the first). The C library's strtod() is correctly rounded (glibc,
 * macOS, the Windows UCRT), so the same text gives the same double everywhere.
 *
 * C_rmd_strtod(x) checks each string is a plain number before converting it:
 *   [+-]? ( digits [. digits?] | . digits ) ( [eE] [+-]? digits )?
 * with no space, no hexadecimal, no "Inf" or "NaN"; anything else, NA and the
 * empty string are NA. strtod() reads the decimal point of the process locale, so
 * the point is swapped for that locale's own before converting: the result does
 * not depend on LC_NUMERIC.
 */
#include <R.h>
#include <Rinternals.h>
#include <stdlib.h>
#include <string.h>
#include <locale.h>

static int rmd_plain_number(const char *s) {
    const char *p = s;
    int digits = 0;
    if (*p == '+' || *p == '-') p++;
    while (*p >= '0' && *p <= '9') { p++; digits++; }
    if (*p == '.') {
        p++;
        while (*p >= '0' && *p <= '9') { p++; digits++; }
    }
    if (!digits) return 0;
    if (*p == 'e' || *p == 'E') {
        p++;
        if (*p == '+' || *p == '-') p++;
        if (!(*p >= '0' && *p <= '9')) return 0;
        while (*p >= '0' && *p <= '9') p++;
    }
    return *p == '\0';
}

SEXP C_rmd_strtod(SEXP x) {
    if (!isString(x)) error("rmd_strtod: `x` must be character");
    R_xlen_t n = XLENGTH(x);
    SEXP out = PROTECT(allocVector(REALSXP, n));
    double *o = REAL(out);
    const char *dp = localeconv()->decimal_point;
    size_t dpl = (dp && *dp) ? strlen(dp) : 1;
    int swap = !(dp && strcmp(dp, ".") == 0);
    char small[128];
    for (R_xlen_t i = 0; i < n; i++) {
        SEXP s = STRING_ELT(x, i);
        const char *c = (s == NA_STRING) ? NULL : CHAR(s);
        if (!c || !rmd_plain_number(c)) { o[i] = NA_REAL; continue; }
        if (!swap) { o[i] = strtod(c, NULL); continue; }
        size_t len = strlen(c), need = len + dpl + 1;
        char *buf = need <= sizeof small ? small : R_alloc(need, 1);
        const char *pt = strchr(c, '.');
        if (pt) {
            size_t k = (size_t) (pt - c);
            memcpy(buf, c, k);
            memcpy(buf + k, dp, dpl);
            strcpy(buf + k + dpl, pt + 1);
        } else {
            strcpy(buf, c);
        }
        o[i] = strtod(buf, NULL);
    }
    UNPROTECT(1);
    return out;
}
