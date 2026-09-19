# Chicago crime + arrest loaders.
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
#'   \code{getOption("rmoriedata.mirror")}. The mirror's
#'   \code{<type>_full.parquet} must use snappy or no compression and
#'   data pages v1: the package's own reader supports nothing else.
#' @param refresh If \code{TRUE}, ignore the cross-session cache of the
#'   complete dataset and fetch it again (the cache is rewritten). A cache
#'   file that cannot be read is discarded and refetched regardless.
#' @return A \code{data.frame}/\code{tibble}, or a length-1 character Parquet
#'   path when \code{as = "parquet_path"}.
#' @examples
#' # `type` selects the dataset; the bundled sample is returned by default.
#' comp <- load_chicago_data("complaints") # reported incidents
#' arr <- load_chicago_data("arrests") # arrests
#' nrow(comp)
#' nrow(arr)
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
                              fraction = NULL,
                              refresh = FALSE) {
  type <- match.arg(type)
  as <- match.arg(as)
  if (!is.null(limit) && !is.null(fraction)) {
    stop("give either `limit` (rows) or `fraction` (share of the dataset), ",
      "not both.",
      call. = FALSE
    )
  }
  if (!is.null(limit)) {
    stopifnot(is.numeric(limit), length(limit) == 1L, limit >= 1)
  }
  if (!is.null(fraction)) {
    stopifnot(
      is.numeric(fraction), length(fraction) == 1L,
      fraction > 0, fraction <= 1
    )
    total <- .rmd_full_count(type)
    limit <- max(1L, as.integer(ceiling(total * fraction)))
  }

  df <- if (isTRUE(full)) {
    .rmd_fetch_full(type, mirror, limit, refresh = isTRUE(refresh))
  } else {
    .rmd_sample(type)
  }

  switch(as,
    "data.frame" = as.data.frame(df, stringsAsFactors = FALSE),
    "tibble" = {
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
      "`limit` instead.",
      call. = FALSE
    )
  }
  n
}

.rmd_fetch_full <- function(type, mirror, limit = NULL, refresh = FALSE) {
  # A bounded fetch is never cached and never reads the full cache: the
  # `<type>_full.parquet` cache must only ever hold the complete dataset.
  bounded <- !is.null(limit)
  cache <- file.path(.rmd_cache_dir(), paste0(type, "_full.parquet"))
  if (!bounded && !isTRUE(refresh) && file.exists(cache)) {
    df <- tryCatch(morie_read_parquet(cache), error = function(e) NULL)
    if (!is.null(df)) return(df)
    unlink(cache) # damaged (interrupted write, full disk): fetch again
  }
  # The service's own row count decides whether a response is the complete
  # dataset; without it (count endpoint down) only the shape checks apply
  # and the result is not cached.
  expected <- if (bounded) NA_real_ else .rmd_full_count_or_na(type)
  # Try the optional mirror first (offline-friendly), then Socrata.
  n <- if (bounded) as.integer(limit) else max(5000000, expected, na.rm = TRUE)
  urls <- c(
    if (!bounded && !is.null(mirror)) {
      file.path(mirror, paste0(type, "_full.parquet"))
    },
    .rmd_full_url(type, n)
  )
  why <- character()
  for (u in urls) {
    df <- tryCatch(
      if (grepl("\\.parquet$", u)) {
        morie_read_parquet(u)
      } else {
        utils::read.csv(u, stringsAsFactors = FALSE, check.names = TRUE)
      },
      error = function(e) NULL
    )
    if (is.null(df)) {
      why <- c(why, paste0(u, ": no response"))
      next
    }
    bad <- .rmd_full_reject(df, if (bounded) NA_real_ else expected)
    if (!is.null(bad)) {
      why <- c(why, paste0(u, ": ", bad))
      next
    }
    # Without the service's count a short export cannot be told from a
    # complete one, so the data is returned but not written across
    # sessions: a bad day stays confined to this session.
    if (!bounded && !is.na(expected)) try(.rmd_cache_write(df, cache), silent = TRUE)
    return(df)
  }
  stop("could not fetch full Chicago '", type,
    "' data from mirror or Socrata:\n  ", paste(why, collapse = "\n  "),
    call. = FALSE
  )
}

.rmd_full_url <- function(type, n) {
  paste0(.rmd_endpoint(type), "?$limit=", format(n, scientific = FALSE))
}

.rmd_full_count_or_na <- function(type) {
  tryCatch(.rmd_full_count(type), error = function(e) NA_real_)
}

# Why a response is not the dataset, or NULL when it passes. A 200 carrying
# an HTML outage page reads as a one-column frame; a header-only body as
# zero rows; a silently short export as fewer rows than the service
# reports. None of these may reach the cross-session cache.
.rmd_full_reject <- function(df, expected = NA_real_) {
  if (ncol(df) < 2L) {
    return("a single column, which is an HTML page, not the dataset")
  }
  if (nrow(df) == 0L) return("no rows")
  if (!is.na(expected) && nrow(df) < 0.99 * expected) {
    return(sprintf("%d rows where the service reports %d",
                   nrow(df), as.integer(expected)))
  }
  NULL
}

# Write next to the destination and rename, so a concurrent reader sees
# either the previous file or the complete new one, never a partial write.
.rmd_cache_write <- function(df, path) {
  tmp <- tempfile("write-", tmpdir = dirname(path), fileext = ".parquet")
  on.exit(unlink(tmp), add = TRUE)
  morie_write_parquet(as.data.frame(df), tmp)
  if (!file.rename(tmp, path)) stop("could not replace ", path, call. = FALSE)
  invisible(path)
}

.rmd_write_parquet <- function(df, type, full) {
  # The native writer maps POSIXct to a parquet TIMESTAMP, which reads back
  # in pandas/polars; the `date_iso` string column is the lossless fallback
  # for readers that don't map the timestamp logical type.
  suffix <- if (isTRUE(full)) "full" else "sample"
  path <- file.path(.rmd_cache_dir(), paste0(type, "_", suffix, ".parquet"))
  .rmd_cache_write(df, path)
  path
}
