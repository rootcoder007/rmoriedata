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
#' @param x For `mdsha()`, a length-1 character vector or a
#'   raw vector. For `mdmean()`, a numeric vector (coerced with
#'   [as.numeric()]); NA/NaN propagate.
#' @return `mdsha()` returns a 64-character lowercase hex
#'   digest. `mdmean()` returns a length-1 numeric.
#' @examples
#' ## ---- mdsha(): 64-char lowercase hex digest --------------
#' mdsha("abc") # hash a character scalar
#' mdsha("") # the empty string still hashes
#' mdsha(charToRaw("abc")) # identical digest from raw bytes
#'
#' # character input and its raw-byte equivalent agree:
#' identical(mdsha("abc"), mdsha(charToRaw("abc")))
#'
#' # Data-integrity pin: verify a value is byte-for-byte what you expect.
#' expected <- mdsha("record-42")
#' stopifnot(mdsha("record-42") == expected)
#'
#' # Fingerprint a whole object by hashing its serialization.
#' mdsha(serialize(list(a = 1, b = "x"), NULL))
#'
#' ## ---- mdmean(): fast length-1 mean --------------------------
#' mdmean(1:10) # 5.5
#' mdmean(c(2, 4, 6)) # 4
#' mdmean(c(-1, 0, 1)) # 0
#' mdmean(c(1, 2, NA)) # NA propagates (no na.rm)
#' mdmean(complaint_sample$year) # mean over a bundled column
#' @useDynLib rmoriedata, .registration = TRUE
#' @name morie_core
NULL

#' @rdname morie_core
#' @export
mdsha <- function(x) {
  if (!is.raw(x)) x <- as.character(x)
  .Call(C_morie_core_sha256, x)
}

#' @rdname morie_core
#' @export
mdmean <- function(x) {
  if (!is.numeric(x) && !is.logical(x)) {
    stop("`x` must be a numeric vector", call. = FALSE)
  }
  .Call(C_morie_core_mean, as.numeric(x))
}
