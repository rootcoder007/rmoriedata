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
#' morie_core_sha256("abc")
#' morie_core_mean(1:10)
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
