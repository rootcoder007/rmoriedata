# SPDX-License-Identifier: AGPL-3.0-or-later

#' Shared C-core helpers (rmorie ecosystem backend)
#'
#' Thin access to the compiled core that ships in
#' \pkg{rmoriebricklayer}. rmoriedata links that core via
#' `LinkingTo: rmoriebricklayer`, so these functions call the exact same
#' kernels used across the rmorie family -- no duplicated C code. They
#' back fast data-integrity hashing and summaries for the bundled
#' datasets without requiring \pkg{rmorie}.
#'
#' @param x For `morie_core_sha256()`, a length-1 character vector or a
#'   raw vector. For `morie_core_mean()`, a numeric vector (coerced with
#'   [as.numeric()]); NA/NaN propagate.
#' @return `morie_core_sha256()` returns a 64-character lowercase hex
#'   digest. `morie_core_mean()` returns a length-1 numeric.
#' @examples
#' ## ---- morie_core_sha256(): 64-char lowercase hex digest --------------
#' morie_core_sha256("abc")            # hash a character scalar
#' morie_core_sha256("")               # the empty string still hashes
#' morie_core_sha256(charToRaw("abc")) # identical digest from raw bytes
#'
#' # character input and its raw-byte equivalent agree:
#' identical(morie_core_sha256("abc"), morie_core_sha256(charToRaw("abc")))
#'
#' # Data-integrity pin: verify a value is byte-for-byte what you expect.
#' expected <- morie_core_sha256("record-42")
#' stopifnot(morie_core_sha256("record-42") == expected)
#'
#' # Fingerprint a whole object by hashing its serialization.
#' morie_core_sha256(serialize(list(a = 1, b = "x"), NULL))
#'
#' ## ---- morie_core_mean(): fast length-1 mean --------------------------
#' morie_core_mean(1:10)               # 5.5
#' morie_core_mean(c(2, 4, 6))         # 4
#' morie_core_mean(c(-1, 0, 1))        # 0
#' morie_core_mean(c(1, 2, NA))        # NA propagates (no na.rm)
#' morie_core_mean(complaint_sample$year)  # mean over a bundled column
#' @useDynLib rmoriedata, .registration = TRUE
#' @name morie_core
NULL

#' @rdname morie_core
#' @export
morie_core_sha256 <- function(x) {
  if (!is.raw(x)) x <- as.character(x)
  .Call(C_morie_core_sha256, x)
}

#' @rdname morie_core
#' @export
morie_core_mean <- function(x) .Call(C_morie_core_mean, as.numeric(x))
