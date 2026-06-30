/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * rmoriedata_init.c -- rmoriedata's connection to the shared ecosystem
 * C core.
 *
 * rmoriedata declares `LinkingTo: rmoriebricklayer` and includes the
 * core's public header; the kernels below are not reimplemented here --
 * they resolve at load time to the single compiled copy that lives in
 * rmoriebricklayer (one source of truth for the whole rmorie family).
 *
 * These back fast data-integrity hashing and summary statistics for the
 * bundled datasets without pulling in rmorie or duplicating C code.
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <string.h>

#include <rmoriebricklayer.h>   /* the shared core, via LinkingTo */

/* SHA-256 of a length-1 character string or a raw vector, using the
 * shared core's rmbl_sha256_hex(). */
SEXP C_morie_core_sha256(SEXP x) {
    const unsigned char *data;
    size_t len;
    char out[65];
    if (TYPEOF(x) == RAWSXP) {
        data = (const unsigned char *) RAW(x);
        len  = (size_t) XLENGTH(x);
    } else if (TYPEOF(x) == STRSXP && XLENGTH(x) >= 1) {
        SEXP s = STRING_ELT(x, 0);
        if (s == NA_STRING) return ScalarString(NA_STRING);
        data = (const unsigned char *) CHAR(s);
        len  = strlen((const char *) data);
    } else {
        Rf_error("morie_core_sha256 expects a length-1 character vector or a raw vector");
    }
    rmbl_sha256_hex(data, len, out);
    return mkString(out);
}

/* Arithmetic mean via the shared core's rmbl_mean(). */
SEXP C_morie_core_mean(SEXP x) {
    x = PROTECT(coerceVector(x, REALSXP));
    double m = rmbl_mean(REAL(x), XLENGTH(x));
    UNPROTECT(1);
    return ScalarReal(m);
}

static const R_CallMethodDef CallEntries[] = {
    {"C_morie_core_sha256", (DL_FUNC) &C_morie_core_sha256, 1},
    {"C_morie_core_mean",   (DL_FUNC) &C_morie_core_mean,   1},
    {NULL, NULL, 0}
};

void R_init_rmoriedata(DllInfo *dll) {
    R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
