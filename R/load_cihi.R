# R/load_cihi.R
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)
#'
#' Returns the bundled catalogue of the public data-table \code{.xlsx}
#' workbooks published on the Canadian Institute for Health Information
#' (CIHI) \dQuote{Access data and reports > Data tables} page
#' (\url{https://www.cihi.ca/en/access-data-and-reports/data-tables}).
#' Each row carries the table title, its direct \code{url}, and a
#' \code{wayback_url} snapshot on the Internet Archive so the table
#' stays retrievable even if CIHI rotates or removes the live file.
#'
#' Pair with \code{rmorie::morie_ingest_cihi_xlsx()} to download + parse
#' any row (that helper tries \code{url} first and falls back to
#' \code{wayback_url}). The Wayback snapshots were resolved with
#' \code{rmoriebricklayer::wayback_snapshot_url()}.
#'
#' @param archived_only If \code{TRUE}, drop rows with no Wayback
#'   snapshot. Default \code{FALSE} (return the full catalogue).
#' @return A \code{data.frame} with columns \code{title}, \code{url},
#'   \code{wayback_url}.
#' @source Canadian Institute for Health Information, Data tables
#'   (\url{https://www.cihi.ca/en/access-data-and-reports/data-tables}).
#'   Snapshotted to the Internet Archive (\url{https://web.archive.org}).
#'   Catalogue current as of 2026-07.
#' @examples
#' # Full catalogue: title, live url, Wayback snapshot url.
#' cat <- load_cihi_data_tables()
#' nrow(cat)
#' names(cat)
#' head(cat$title, 3)
#'
#' # `archived_only = TRUE` keeps only rows that have a Wayback snapshot,
#' # i.e. tables still retrievable if CIHI rotates the live file.
#' arch <- load_cihi_data_tables(archived_only = TRUE)
#' nrow(arch)                       # <= nrow(cat)
#' all(nzchar(arch$wayback_url))    # TRUE
#'
#' # Find a table by keyword before fetching it.
#' cat$title[grepl("hospital", cat$title, ignore.case = TRUE)][1:3]
#' @export
load_cihi_data_tables <- function(archived_only = FALSE) {
  path <- system.file("extdata", "cihi_data_tables.csv",
                      package = "rmoriedata")
  if (!nzchar(path)) {
    stop("bundled CIHI data-table catalogue not found in rmoriedata",
         call. = FALSE)
  }
  df <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  if (isTRUE(archived_only) && "wayback_url" %in% names(df)) {
    df <- df[nzchar(df[["wayback_url"]]), , drop = FALSE]
    rownames(df) <- NULL
  }
  df
}

#' Download a CIHI data table (live, with Wayback fallback)
#'
#' Resolves a CIHI table from the bundled catalogue and downloads it to
#' \code{dest}, falling back to the Internet Archive snapshot if the live
#' CIHI URL has rotated or been removed. The download + fallback runs
#' through \pkg{rmoriebricklayer}'s shared C++/libcurl foundation
#' (\code{bricklayer_fetch()}), the same engine \pkg{rmorie} and
#' \pkg{morie} use -- one implementation across the ecosystem.
#'
#' @param which A row index into \code{load_cihi_data_tables()}, or a
#'   string matched (case-insensitively, as a substring) against table
#'   titles. Must resolve to exactly one table.
#' @param dest Destination file path. Default: a tempfile with the
#'   table's own extension.
#' @param timeout Per-request timeout, seconds.
#' @return The \code{dest} path, invisibly. Errors if both the live URL
#'   and its Wayback fallback fail.
#' @examples
#' # Offline: inspect the catalogue to choose a `which` argument.
#' cat <- load_cihi_data_tables()
#' head(cat$title, 3)
#'
#' \dontrun{
#' # Not run: downloads a table from the live CIHI web service; check
#' # machines must not depend on remote-service availability.
#' # `which` by title substring (case-insensitive; must match exactly one).
#' f1 <- fetch_cihi_table("Hospital Beds")           # -> tempfile path
#'
#' # `which` by row index into load_cihi_data_tables().
#' f2 <- fetch_cihi_table(1)
#'
#' # `dest` chooses the output path; `timeout` bounds each request (seconds).
#' f3 <- fetch_cihi_table(1, dest = tempfile(fileext = ".xlsx"), timeout = 60)
#'
#' # An ambiguous substring errors and lists the candidates:
#' fetch_cihi_table("data")
#' }
#' @export
fetch_cihi_table <- function(which, dest = NULL, timeout = 120L) {
  if (!requireNamespace("rmoriebricklayer", quietly = TRUE)) {
    stop("fetch_cihi_table() needs 'rmoriebricklayer' for the shared ",
         "fetch-with-fallback engine.", call. = FALSE)
  }
  cat_df <- load_cihi_data_tables()
  if (is.numeric(which)) {
    idx <- as.integer(which)
  } else {
    hits <- grep(tolower(which), tolower(cat_df$title), fixed = TRUE)
    if (length(hits) == 0L) stop("no CIHI table matches '", which, "'.", call. = FALSE)
    if (length(hits) > 1L) {
      stop("'", which, "' matches ", length(hits), " tables; be more specific:\n  ",
           paste(utils::head(cat_df$title[hits], 6), collapse = "\n  "), call. = FALSE)
    }
    idx <- hits
  }
  row <- cat_df[idx, , drop = FALSE]
  if (is.null(dest)) {
    ext <- if ("format" %in% names(row)) row[["format"]] else "xlsx"
    dest <- tempfile(fileext = paste0(".", ext))
  }
  wb <- if ("wayback_url" %in% names(row)) row[["wayback_url"]] else ""
  rmoriebricklayer::bricklayer_fetch(row[["url"]], dest,
                                     wayback = wb, timeout = timeout)
  invisible(dest)
}
