# R/load_chicago_data.R
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Load Chicago crime or arrest data
#'
#' Returns the bundled sample by default, or fetches the full dataset from the
#' City of Chicago SODA API (cached under \code{\link[tools]{R_user_dir}}) when
#' \code{full = TRUE}. The result can be returned as a base data frame, a
#' tibble, or written to a Parquet file whose path is returned -- the last being
#' the recommended bridge for Python (\code{pandas.read_parquet}).
#'
#' Parquet I/O uses this package's own native codec (R/aaa_parquet.R); no
#' package), so no \pkg{arrow} install is required.
#'
#' @param type One of \code{"arrests"} or \code{"complaints"}.
#' @param as Return format: \code{"data.frame"} (default), \code{"tibble"}, or
#'   \code{"parquet_path"} (writes a Parquet file to the session cache and
#'   returns its path).
#' @param full If \code{TRUE}, fetch the complete dataset from Socrata (network,
#'   large) instead of the bundled sample; cached across sessions as Parquet.
#' @param limit Optional row cap for a \code{full = TRUE} fetch (passed to
#'   the Socrata \code{$limit} parameter). A bounded fetch skips the mirror
#'   and is never written to the full-dataset cache. Default \code{NULL}
#'   fetches everything.
#' @param fraction Optional share of the dataset, in \code{(0, 1]}, for a
#'   \code{full = TRUE} fetch: the live row count is looked up and
#'   \code{limit} is set to \code{ceiling(total * fraction)}. Give either
#'   \code{fraction} or \code{limit}, not both.
#' @param mirror Optional base URL of an r-universe/drat mirror to try before
#'   Socrata (offline-friendly fallback). Defaults to
#'   \code{getOption("rmoriedata.mirror")}.
#' @return A \code{data.frame}/\code{tibble}, or a length-1 character Parquet
#'   path when \code{as = "parquet_path"}.
#' @examples
#' # `type` selects the dataset; the bundled sample is returned by default.
#' comp <- load_chicago_data("complaints")           # reported incidents
#' arr  <- load_chicago_data("arrests")              # arrests
#' nrow(comp); nrow(arr)
#' head(sort(table(comp$primary_type), decreasing = TRUE), 5)
#'
#' # `as = "tibble"` returns a tibble when the package is installed.
#' if (requireNamespace("tibble", quietly = TRUE)) {
#'   tb <- load_chicago_data("complaints", as = "tibble")
#'   class(tb)
#' }
#'
#' \donttest{
#' # `as = "parquet_path"` writes a Parquet file and returns its path --
#' # the recommended bridge to Python (pandas.read_parquet). Offline: the
#' # bundled sample is written, no network.
#' pq <- load_chicago_data("arrests", as = "parquet_path")
#' file.exists(pq)
#' }
#'
#' \donttest{
#' # `full = TRUE` fetches from the live Chicago SODA API; `limit` bounds
#' # the request (seconds, not minutes) and try() keeps the example
#' # graceful when the service is unreachable. Omit `limit` for the
#' # complete multi-million-row dataset (cached across sessions); `mirror`
#' # tries an offline-friendly Parquet mirror first when set.
#' big <- try(load_chicago_data("complaints", full = TRUE, limit = 1000))
#' if (!inherits(big, "try-error")) nrow(big)
#'
#' # `fraction` takes a share of the dataset instead of a row count:
#' # 0.001 = 0.1% of all rows (the live total is looked up first).
#' tiny <- try(load_chicago_data("arrests", full = TRUE, fraction = 0.0001))
#' if (!inherits(tiny, "try-error")) nrow(tiny)
#' }
#' @export
load_chicago_data <- function(type = c("arrests", "complaints"),
                              as = c("data.frame", "tibble", "parquet_path"),
                              full = FALSE,
                              mirror = getOption("rmoriedata.mirror", NULL),
                              limit = NULL,
                              fraction = NULL) {
  type <- match.arg(type)
  as   <- match.arg(as)
  if (!is.null(limit) && !is.null(fraction)) {
    stop("give either `limit` (rows) or `fraction` (share of the dataset), ",
         "not both.", call. = FALSE)
  }
  if (!is.null(limit)) {
    stopifnot(is.numeric(limit), length(limit) == 1L, limit >= 1)
  }
  if (!is.null(fraction)) {
    stopifnot(is.numeric(fraction), length(fraction) == 1L,
              fraction > 0, fraction <= 1)
    total <- .rmd_full_count(type)
    limit <- max(1L, as.integer(ceiling(total * fraction)))
  }

  df <- if (isTRUE(full)) .rmd_fetch_full(type, mirror, limit)
        else .rmd_sample(type)

  switch(as,
    "data.frame"   = as.data.frame(df, stringsAsFactors = FALSE),
    "tibble"       = {
      if (!requireNamespace("tibble", quietly = TRUE)) {
        return(as.data.frame(df, stringsAsFactors = FALSE))
      }
      tibble::as_tibble(df)
    },
    "parquet_path" = .rmd_write_parquet(df, type, full)
  )
}

# -- internals ---------------------------------------------------------------

.rmd_sample <- function(type) {
  nm <- if (type == "arrests") "arrest_sample" else "complaint_sample"
  e <- new.env()
  utils::data(list = nm, package = "rmoriedata", envir = e)
  get(nm, envir = e)
}

.rmd_cache_dir <- function() {
  d <- tools::R_user_dir("rmoriedata", "cache")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.rmd_endpoint <- function(type) {
  if (type == "arrests") {
    "https://data.cityofchicago.org/resource/dpt3-jri9.csv"
  } else {
    "https://data.cityofchicago.org/resource/ijzp-q8t2.csv"
  }
}

.rmd_full_count <- function(type) {
  u <- paste0(.rmd_endpoint(type), "?$select=count(*)")
  n <- tryCatch(
    suppressWarnings(as.numeric(utils::read.csv(u)[1, 1])),
    error = function(e) NA_real_
  )
  if (is.na(n) || n < 1) {
    stop("could not determine the total row count for Chicago '", type,
         "' (needed to resolve `fraction`); check your connection or use ",
         "`limit` instead.", call. = FALSE)
  }
  n
}

.rmd_fetch_full <- function(type, mirror, limit = NULL) {
  # A bounded fetch is never cached and never reads the full cache: the
  # `<type>_full.parquet` cache must only ever hold the complete dataset.
  bounded <- !is.null(limit)
  cache <- file.path(.rmd_cache_dir(), paste0(type, "_full.parquet"))
  if (!bounded && file.exists(cache)) {
    return(morie_read_parquet(cache))
  }
  # Try the optional mirror first (offline-friendly), then Socrata.
  n <- if (bounded) as.integer(limit) else 5000000L
  urls <- c(
    if (!bounded && !is.null(mirror))
      file.path(mirror, paste0(type, "_full.parquet")),
    paste0(.rmd_endpoint(type), "?$limit=", n)
  )
  for (u in urls) {
    df <- tryCatch(
      if (grepl("\\.parquet$", u)) {
        morie_read_parquet(u)
      } else {
        utils::read.csv(u, stringsAsFactors = FALSE, check.names = TRUE)
      },
      error = function(e) NULL
    )
    if (!is.null(df)) {
      if (!bounded) try(morie_write_parquet(df, cache), silent = TRUE)
      return(df)
    }
  }
  stop("could not fetch full Chicago '", type,
       "' data from mirror or Socrata; check your connection.", call. = FALSE)
}

.rmd_write_parquet <- function(df, type, full) {
  # The native writer maps POSIXct to a parquet TIMESTAMP, which reads back
  # in pandas/polars; the `date_iso` string column is the lossless fallback
  # for readers that don't map the timestamp logical type.
  suffix <- if (isTRUE(full)) "full" else "sample"
  path <- file.path(.rmd_cache_dir(), paste0(type, "_", suffix, ".parquet"))
  morie_write_parquet(as.data.frame(df), path)
  path
}
