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
#' Parquet I/O uses \pkg{nanoparquet} (already a hard dependency of this
#' package), so no \pkg{arrow} install is required.
#'
#' @param type One of \code{"arrests"} or \code{"complaints"}.
#' @param as Return format: \code{"data.frame"} (default), \code{"tibble"}, or
#'   \code{"parquet_path"} (writes a Parquet file to the session cache and
#'   returns its path).
#' @param full If \code{TRUE}, fetch the complete dataset from Socrata (network,
#'   large) instead of the bundled sample; cached across sessions as Parquet.
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
#' \dontrun{
#' # Not run: fetches the full multi-million-row dataset from the live
#' # Chicago Socrata service; check machines must not depend on remote
#' # services or long downloads.
#' # `full = TRUE` fetches the complete dataset from the Chicago SODA API
#' # (live network, ~millions of rows; cached across sessions). `mirror`
#' # tries an offline-friendly Parquet mirror first when set. Network-only,
#' # so it is not run in automated checks.
#' big <- load_chicago_data("complaints", full = TRUE,
#'                          mirror = getOption("rmoriedata.mirror"))
#' nrow(big)
#' }
#' @export
load_chicago_data <- function(type = c("arrests", "complaints"),
                              as = c("data.frame", "tibble", "parquet_path"),
                              full = FALSE,
                              mirror = getOption("rmoriedata.mirror", NULL)) {
  type <- match.arg(type)
  as   <- match.arg(as)

  df <- if (isTRUE(full)) .rmd_fetch_full(type, mirror) else .rmd_sample(type)

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

.rmd_fetch_full <- function(type, mirror) {
  cache <- file.path(.rmd_cache_dir(), paste0(type, "_full.parquet"))
  if (file.exists(cache)) {
    return(as.data.frame(nanoparquet::read_parquet(cache)))
  }
  # Try the optional mirror first (offline-friendly), then Socrata.
  urls <- c(
    if (!is.null(mirror)) file.path(mirror, paste0(type, "_full.parquet")),
    paste0(.rmd_endpoint(type), "?$limit=5000000")
  )
  for (u in urls) {
    df <- tryCatch(
      if (grepl("\\.parquet$", u)) {
        as.data.frame(nanoparquet::read_parquet(u))
      } else {
        utils::read.csv(u, stringsAsFactors = FALSE, check.names = TRUE)
      },
      error = function(e) NULL
    )
    if (!is.null(df)) {
      try(nanoparquet::write_parquet(df, cache), silent = TRUE)
      return(df)
    }
  }
  stop("could not fetch full Chicago '", type,
       "' data from mirror or Socrata; check your connection.", call. = FALSE)
}

.rmd_write_parquet <- function(df, type, full) {
  # nanoparquet maps POSIXct to a parquet TIMESTAMP, which reads back cleanly
  # in pandas/polars; the `date_iso` string column is the lossless fallback
  # for readers that don't map the timestamp logical type.
  suffix <- if (isTRUE(full)) "full" else "sample"
  path <- file.path(.rmd_cache_dir(), paste0(type, "_", suffix, ".parquet"))
  nanoparquet::write_parquet(as.data.frame(df), path)
  path
}
