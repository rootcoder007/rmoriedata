# Chicago crime + arrest loaders.
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Load Chicago crime or arrest data
#'
#' Returns the bundled sample by default, or fetches the full dataset from the
#' City of Chicago SODA API when \code{full = TRUE}. A complete fetch is
#' cached as Parquet under \code{tempdir()} for the session; to keep it
#' across sessions name a directory first, for example
#' \code{options(rmoriedata.cache_dir = tools::R_user_dir("rmoriedata", "cache"))},
#' and drop it with \code{\link{chiclr}()}. Nothing is written
#' outside \code{tempdir()} unless you set that option. The result can be
#' returned as a base data frame, a
#' tibble, or written to a Parquet file whose path is returned -- the last being
#' the recommended bridge for Python (\code{pandas.read_parquet}).
#'
#' Parquet I/O uses this package's own native codec (R/aaa_parquet.R), so
#' no \pkg{arrow} install is required.
#'
#' @param type One of \code{"arrests"} or \code{"complaints"}.
#' @param as Return format: \code{"data.frame"} (default), \code{"tibble"}, or
#'   \code{"parquet_path"} (writes a Parquet file under \code{tempdir()}
#'   and returns its path; nothing is written to the user's home). Parquet
#'   keeps no time zone, so \code{date} reads back as the same instant in
#'   UTC; \code{date_iso} keeps the local time and offset.
#' @param full If \code{TRUE}, fetch the complete dataset from Socrata (network,
#'   large) instead of the bundled sample; a complete fetch is cached as
#'   Parquet (see Description). The result has the bundled sample's columns,
#'   in its order and with its types, derived from Socrata's export as the
#'   sample was.
#' @param limit Optional row cap. For a \code{full = TRUE} fetch it is passed to
#'   the Socrata \code{$limit} parameter (a bounded fetch skips the mirror
#'   and is never written to the full-dataset cache); otherwise it keeps the
#'   first \code{limit} rows of the bundled sample. Default \code{NULL}
#'   fetches everything.
#' @param fraction Optional share of the dataset, in \code{(0, 1]}, for a
#'   \code{full = TRUE} fetch: the live row count is looked up and
#'   \code{limit} is set to \code{ceiling(total * fraction)} (of the bundled
#'   sample's rows otherwise). Give either
#'   \code{fraction} or \code{limit}, not both.
#' @param mirror Optional base URL of an r-universe/drat mirror, or a local
#'   directory, to try before Socrata (offline-friendly fallback). Defaults to
#'   \code{getOption("rmoriedata.mirror")}. A URL is downloaded over https
#'   and checked against \code{<type>_full.parquet.sha256} when the mirror
#'   has one; if the mirror fails, Socrata is used. The mirror's
#'   \code{<type>_full.parquet} must use snappy or no compression and
#'   data pages v1: the package's own reader supports nothing else.
#' @param refresh If \code{TRUE}, ignore the cache of the
#'   complete dataset and fetch it again (the cache is rewritten). A cache
#'   file that cannot be read is discarded and refetched regardless.
#' @return A \code{data.frame}/\code{tibble}, or a length-1 character Parquet
#'   path when \code{as = "parquet_path"}.
#' @examples
#' # `type` selects the dataset; the bundled sample is returned by default.
#' comp <- chiload("complaints") # reported incidents
#' arr <- chiload("arrests") # arrests
#' nrow(comp)
#' nrow(arr)
#' head(sort(table(comp$primary_type), decreasing = TRUE), 5)
#'
#' # `as = "tibble"` returns a tibble when the package is installed.
#' if (requireNamespace("tibble", quietly = TRUE)) {
#'   tb <- chiload("complaints", as = "tibble")
#'   class(tb)
#' }
#'
#' \donttest{
#' # `as = "parquet_path"` writes a Parquet file and returns its path --
#' # the recommended bridge to Python (pandas.read_parquet). Offline: the
#' # bundled sample is written, no network.
#' pq <- chiload("arrests", as = "parquet_path")
#' file.exists(pq)
#' }
#'
#' \donttest{
#' # `full = TRUE` fetches from the live Chicago SODA API; `limit` bounds
#' # the request (seconds, not minutes) and try() keeps the example
#' # graceful when the service is unreachable. Omit `limit` for the
#' # complete multi-million-row dataset (cached, see Description); `mirror`
#' # tries an offline-friendly Parquet mirror first when set.
#' # `fraction = 0.001` takes a share of the dataset (0.1% of all rows)
#' # instead of a row count; the live total is looked up first.
#' big <- try(chiload("complaints", full = TRUE, limit = 200))
#' if (!inherits(big, "try-error")) nrow(big)
#' }
#' @export
chiload <- function(type = c("arrests", "complaints"),
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
  for (a in c("full", "refresh")) {
    v <- get(a)
    if (!is.logical(v) || length(v) != 1L || is.na(v)) {
      stop("`", a, "` must be TRUE or FALSE.", call. = FALSE)
    }
  }
  if (!is.null(limit) && !(is.numeric(limit) && length(limit) == 1L &&
                           !is.na(limit) && limit >= 1 && limit == floor(limit) &&
                           limit <= .Machine$integer.max)) {
    stop("`limit` must be a whole number of rows from 1 to ",
         .Machine$integer.max, ".", call. = FALSE)
  }
  if (!is.null(fraction) && !(is.numeric(fraction) && length(fraction) == 1L &&
                              !is.na(fraction) && fraction > 0 && fraction <= 1)) {
    stop("`fraction` must be one number above 0 and at most 1.", call. = FALSE)
  }

  df <- if (full) {
    if (!is.null(fraction)) {
      limit <- max(1L, as.integer(ceiling(.rmd_full_count(type) * fraction)))
    }
    .rmd_shape(.rmd_fetch_full(type, mirror, limit, refresh = refresh), type)
  } else {
    # the bundled sample takes the same row cap (it was ignored without full = TRUE)
    s <- .rmd_sample(type)
    if (!is.null(fraction)) limit <- max(1L, as.integer(ceiling(nrow(s) * fraction)))
    if (!is.null(limit)) s <- s[seq_len(min(nrow(s), as.integer(limit))), , drop = FALSE]
    s
  }

  switch(as,
    "data.frame" = as.data.frame(df, stringsAsFactors = FALSE),
    "tibble" = .rmd_as_tibble(df),
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
  # tempdir() unless the user names a directory: CRAN policy allows a
  # package to write outside the session's temporary directory only when
  # the user asks for it.
  d <- getOption("rmoriedata.cache_dir", NULL)
  if (is.null(d) || !nzchar(d)) d <- file.path(tempdir(), "rmoriedata-cache")
  .rmd_mkdir(d)
}

# The directory, created when missing; an error naming it when it cannot be
# created or written (a read-only directory, or a file in its place), before any
# download blames the server for it.
.rmd_mkdir <- function(d) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(d) || file.access(d, 2L) != 0L) {
    stop("rmoriedata: cannot write to the cache directory ", d,
         "; name a writable one with options(rmoriedata.cache_dir = )", call. = FALSE)
  }
  d
}

# The bundled sample's columns, in its order and types, from the raw Socrata
# export, as data-raw/arrest_sample.R and data-raw/complaint_sample.R derive them.
# A frame already in that shape (a mirror that serves it) is returned as it is.
.rmd_shape <- function(raw, type) {
  want <- names(.rmd_sample(type))
  if (identical(names(raw), want)) return(raw)
  n <- nrow(raw)
  pick <- function(...) {
    for (nm in c(...)) if (nm %in% names(raw)) return(as.character(raw[[nm]]))
    rep(NA_character_, n)
  }
  int <- function(...) suppressWarnings(as.integer(pick(...)))
  posix <- function(x) as.POSIXct(x, tz = "America/Chicago", format = "%Y-%m-%dT%H:%M:%S")
  when <- posix(if (type == "arrests") pick("arrest_date", "date") else pick("date"))
  iso <- format(when, "%Y-%m-%dT%H:%M:%S%z")
  if (type == "arrests") {
    data.frame(
      case_number = pick("case_number", "case_no", "cb_no"),
      date_iso = iso, date = when, race = pick("race"),
      charge_type = pick("charge_1_type", "charge1type"),
      charge_class = pick("charge_1_class", "charge1class"),
      charge_desc = pick("charge_1_description", "charge1description"),
      charge_statute = pick("charge_1_statute", "charge1statute"),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      case_number = pick("case_number"), date_iso = iso, date = when,
      iucr = pick("iucr"), primary_type = pick("primary_type"),
      description = pick("description"),
      arrest = as.logical(pick("arrest")), domestic = as.logical(pick("domestic")),
      beat = int("beat"), district = int("district"), ward = int("ward"),
      community_area = int("community_area"), fbi_code = pick("fbi_code"),
      year = int("year"),
      latitude = suppressWarnings(as.numeric(pick("latitude"))),
      longitude = suppressWarnings(as.numeric(pick("longitude"))),
      stringsAsFactors = FALSE
    )
  }
}

#' Clear the cache of full Chicago datasets
#'
#' Deletes the Parquet files that \code{chiload(full = TRUE)}
#' wrote to the cache directory (\code{tempdir()} by default, or the
#' directory named in \code{options(rmoriedata.cache_dir = )}): the
#' \code{<type>_full.parquet} files, their checksum files and any
#' unfinished write. Nothing else in that directory is touched.
#'
#' @return The cache directory, invisibly.
#' @examples
#' chiclr()
#' @export
chiclr <- function() {
  d <- .rmd_cache_dir()
  # only what chiload() wrote: the directory is the user's, and the hosted tables
  # are cached under it too
  mine <- list.files(d, pattern = "_full\\.parquet(\\.sha256)?$|^write-.*\\.parquet$",
                     full.names = TRUE, all.files = TRUE)
  unlink(mine[!dir.exists(mine)])
  invisible(d)
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
    df <- .rmd_cache_read(cache)
    if (!is.null(df)) return(df)
    unlink(c(cache, paste0(cache, ".sha256"))) # damaged or unverified: fetch again
  }
  # The service's own row count decides whether a response is the complete
  # dataset; without it (count endpoint down) only the shape checks apply
  # and the result is not cached.
  expected <- if (bounded) NA_real_ else .rmd_full_count_or_na(type)
  # Try the optional mirror first (offline-friendly), then Socrata.
  n <- if (bounded) as.integer(limit) else max(5000000, expected, na.rm = TRUE)
  urls <- c(
    if (!bounded && !is.null(mirror)) {
      file.path(sub("/+$", "", mirror), paste0(type, "_full.parquet"))
    },
    .rmd_full_url(type, n)
  )
  why <- character()
  for (u in urls) {
    # the connection's own warning ("Could not connect to server") is the reason this
    # source failed: it goes into the error below, not out as a stray warning
    msg <- character()
    df <- tryCatch(
      withCallingHandlers(
        if (grepl("\\.parquet$", u)) {
          .rmd_mirror_read(u)
        } else {
          # fill = FALSE: a row with a field missing or one too many is a garbled
          # export, an error here rather than a padded row in the cache. Every column
          # as text: a number guessed from the first rows loses an IUCR's leading zero.
          utils::read.csv(u, stringsAsFactors = FALSE, check.names = TRUE,
                          encoding = "UTF-8", fill = FALSE, colClasses = "character")
        },
        warning = function(w) {
          msg <<- c(msg, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      ),
      error = function(e) {
        msg <<- c(msg, conditionMessage(e))
        NULL
      }
    )
    if (is.null(df)) {
      why <- c(why, paste0(u, ": ", if (length(msg)) msg[[1L]] else "no response"))
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

# A mirror on the web is downloaded through the package's checked transport
# (.rmd_dl(), rmoriebricklayer's bldl()) and checked against the SHA-256 in
# `<file>.sha256` when the mirror serves one beside it; a local directory is read
# in place. An error sends .rmd_fetch_full() on to Socrata.
.rmd_mirror_read <- function(u) {
  if (!grepl("^[A-Za-z][A-Za-z0-9+.-]*://", u)) return(morie_read_parquet(u))
  f <- tempfile("mirror-", fileext = ".parquet")
  side <- paste0(f, ".sha256")
  on.exit(unlink(c(f, side)), add = TRUE)
  .rmd_dl(u, f, label = basename(u))
  want <- tryCatch({
    .rmd_dl(paste0(u, ".sha256"), side, label = basename(side), quiet = TRUE)
    tolower(sub("[[:space:]].*$", "", trimws(readLines(side, n = 1L, warn = FALSE))))
  }, error = function(e) NA_character_, warning = function(w) NA_character_)
  if (length(want) && !is.na(want)) {
    if (!grepl("^[0-9a-f]{64}$", want)) {
      stop("the mirror's ", basename(u), ".sha256 is not a SHA-256 digest", call. = FALSE)
    }
    have <- tolower(.rmd_bl("sha256file")(f))
    if (!identical(have, want)) {
      stop("the mirror's ", basename(u), " does not match its SHA-256", call. = FALSE)
    }
  }
  morie_read_parquet(f)
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
# A `<path>.sha256` sidecar records the digest; Parquet pages carry no
# mandatory checksum, so without it a flipped byte reads back as
# plausible different numbers.
.rmd_cache_write <- function(df, path) {
  tmp <- tempfile("write-", tmpdir = dirname(path), fileext = ".parquet")
  tmp2 <- paste0(tmp, ".sha256")
  on.exit(unlink(c(tmp, tmp2)), add = TRUE)
  morie_write_parquet(as.data.frame(df), tmp)
  writeLines(.rmd_bl("sha256file")(tmp), tmp2)
  # data first, then its digest: a reader between the two renames sees
  # the new file against the old sidecar and refetches (a wasted fetch),
  # never the new digest against the old file
  if (!file.rename(tmp, path) || !file.rename(tmp2, paste0(path, ".sha256"))) {
    stop("could not replace ", path, call. = FALSE)
  }
  invisible(path)
}

# The cached frame, or NULL when the file is unreadable, has no sidecar,
# or no longer matches it.
.rmd_cache_read <- function(path) {
  side <- paste0(path, ".sha256")
  if (!file.exists(side)) return(NULL)
  want <- readLines(side, n = 1L, warn = FALSE)
  if (!identical(.rmd_bl("sha256file")(path), want)) return(NULL)
  tryCatch(morie_read_parquet(path), error = function(e) NULL)
}

.rmd_write_parquet <- function(df, type, full) {
  # The native writer maps POSIXct to a parquet TIMESTAMP, which reads back
  # in pandas/polars; the `date_iso` string column is the lossless fallback
  # for readers that don't map the timestamp logical type.
  # Written under tempdir(), never under the user's cache: the sample is
  # bundled and a bounded fetch must not land on the `<type>_full.parquet`
  # cache path. The full-dataset cache is written by .rmd_fetch_full() alone.
  suffix <- if (isTRUE(full)) "full" else "sample"
  path <- file.path(tempdir(), paste0("rmoriedata_", type, "_", suffix, ".parquet"))
  .rmd_cache_write(df, path)
  path
}

# a tibble when tibble is installed; otherwise the data.frame, saying so (it was silent)
.rmd_as_tibble <- function(df) {
  if (!requireNamespace("tibble", quietly = TRUE)) {
    message("rmoriedata: the tibble package is not installed, so this is a data.frame ",
            "(install.packages(\"tibble\") for a tibble)")
    return(as.data.frame(df, stringsAsFactors = FALSE))
  }
  tibble::as_tibble(df)
}
