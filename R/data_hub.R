# Curated datasets at data.rmorie.com, opened by the MORIE key that rmorie,
# morie or rmoriebricklayer store in $XDG_CONFIG_HOME/morie/credentials.json.
# The same tables the other packages pull; a manifest lists every table with
# its rows, columns, SHA-256 and the BigQuery public dataset it was built from.

.rmd_credentials_path <- function() {
  base <- trimws(Sys.getenv("XDG_CONFIG_HOME", unset = ""))
  if (!nzchar(base)) base <- file.path(path.expand("~"), ".config")
  file.path(base, "morie", "credentials.json")
}

.rmd_hosted_key <- function() {
  env <- trimws(Sys.getenv("MORIE_HOSTED_KEY", unset = ""))
  if (nzchar(env)) return(env)
  p <- .rmd_credentials_path()
  if (!file.exists(p)) return(NULL)
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  d <- tryCatch(rmoriebricklayer::bricklayer_json_from_json(txt),
                error = function(e) NULL)
  key <- d$hosted_key
  if (is.character(key) && length(key) == 1L && nzchar(key)) key else NULL
}

.rmd_data_url <- function() {
  sub("/+$", "", Sys.getenv("MORIE_DATA_URL", "https://data.rmorie.com"))
}

.rmd_data_cache_dir <- function() {
  d <- file.path(.rmd_cache_dir(), "hosted")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

.rmd_hosted_size <- function(path) {
  # the cached manifest knows the compressed size: a percent bar instead of a spinner
  if (!grepl("\\.csv\\.gz$", path)) return(NULL)
  key <- sub("\\.csv\\.gz$", "", sub("^/", "", path))
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  if (!file.exists(p)) return(NULL)
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  m <- tryCatch(rmoriebricklayer::bricklayer_json_from_json(txt, simplifyVector = FALSE),
                error = function(e) NULL)
  for (d in m$datasets) if (identical(d$key, key)) return(d$bytes_gz)
  NULL
}

.rmd_data_get <- function(path, dest, timeout = 600) {
  key <- .rmd_hosted_key()
  if (is.null(key)) {
    stop("data.rmorie.com needs your MORIE key: run ",
         "morie_data_hosted_login() once (or `rmorie login`).",
         call. = FALSE)
  }
  old <- options(timeout = max(getOption("timeout", 60), timeout))
  on.exit(options(old), add = TRUE)
  hdr <- c(Authorization = paste("Bearer", key),
           "User-Agent" = "rmoriedata/1 (+https://rmorie.com)")
  rc <- tryCatch(
    .rmd_dl(paste0(.rmd_data_url(), path), dest, headers = hdr, timeout = timeout,
            label = sub("\\.csv\\.gz$", "", sub("^/", "", path)),
            size = .rmd_hosted_size(path)),
    error = function(e) e, warning = function(w) w
  )
  if (inherits(rc, "condition")) {
    msg <- conditionMessage(rc)
    if (grepl("401|403|Unauthorized|Forbidden", msg)) {
      stop("data.rmorie.com rejected the stored key; sign in again.", call. = FALSE)
    }
    stop("data.rmorie.com: ", msg, call. = FALSE)
  }
  invisible(dest)
}

#' Curated datasets at data.rmorie.com
#'
#' Beyond the open data this package ships, the MORIE project keeps 160
#' databases materialised from Google BigQuery public datasets (Chicago
#' crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
#' Ethereum, World Bank, ...) and serves their tables from the edge. They
#' open with the MORIE key that rmorie, morie or rmoriebricklayer store
#' (\code{rmorie login}, \code{rmorie::morie_llm_login()},
#' \code{rmoriebricklayer::bricklayer_llm_login()}).
#' \code{morie_data_hosted_catalog()} returns every table with its key,
#' description, rows and BigQuery source (the manifest is kept for a day);
#' \code{morie_data_hosted_load("db/table")} returns one table, cached under
#' the package cache directory (\code{tempdir()} unless
#' \code{options(rmoriedata.cache_dir = )} names a persistent one).
#'
#' @param refresh Fetch again even when a day-old copy is cached.
#' @param key A \code{db/table} key from the catalog.
#' @return \code{morie_data_hosted_login()}: the key, invisibly, after storing it
#'   in the shared credentials file.
#'   \code{morie_data_hosted_catalog()}: a data frame with \code{key},
#'   \code{name}, \code{rows} and \code{source};
#'   \code{morie_data_hosted_load()}: the table as a data frame.
#' @examples
#' \dontrun{
#' head(morie_data_hosted_catalog())
#' df <- morie_data_hosted_load("chicago_crime/incidents")
#' }
#' @export
morie_data_hosted_catalog <- function(refresh = FALSE) {
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  age <- if (file.exists(p)) {
    as.numeric(difftime(Sys.time(), file.mtime(p), units = "secs"))
  } else {
    Inf
  }
  fresh <- age < 86400
  if (refresh || !fresh) .rmd_data_get("/manifest.json", p, timeout = 60)
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  m <- rmoriebricklayer::bricklayer_json_from_json(txt, simplifyVector = FALSE)
  ds <- m$datasets
  if (!length(ds)) {
    return(data.frame(key = character(), name = character(), rows = integer(),
                      source = character(), stringsAsFactors = FALSE))
  }
  pick <- function(d, what) {
    v <- if (identical(what, "name")) d$meta$description else d[[what]]
    if (is.null(v) || !length(v)) "" else as.character(v)[[1L]]
  }
  data.frame(
    key = vapply(ds, pick, "", what = "key"),
    name = vapply(ds, function(d) {
      n <- pick(d, "name")
      if (nzchar(n)) return(n)
      s <- pick(d, "source")
      if (nzchar(s)) s else pick(d, "key")
    }, ""),
    rows = vapply(ds, function(d) as.integer(if (is.null(d$rows)) NA else d$rows), 1L),
    source = vapply(ds, pick, "", what = "source"),
    stringsAsFactors = FALSE)
}

#' @rdname morie_data_hosted_catalog
#' @param token,email,code,open_browser Passed to
#'   \code{rmoriebricklayer::bricklayer_llm_login()}: a key you already hold,
#'   or an email address (a 6-digit code is sent; pass it as \code{code} in a
#'   non-interactive session). With neither, the GitHub device flow runs.
#' @export
morie_data_hosted_login <- function(token = NULL, email = NULL, code = NULL,
                                    open_browser = interactive()) {
  key <- rmoriebricklayer::bricklayer_llm_login(token = token, email = email,
                                                code = code,
                                                open_browser = open_browser)
  invisible(key)
}

#' @rdname morie_data_hosted_catalog
#' @export
morie_data_hosted_load <- function(key, refresh = FALSE) {
  ok <- is.character(key) && length(key) == 1L && grepl("/", key, fixed = TRUE) &&
    !startsWith(key, "/") && !endsWith(key, "/")
  if (!ok) {
    stop("key must be db/table (see morie_data_hosted_catalog())", call. = FALSE)
  }
  parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
  dest <- file.path(.rmd_data_cache_dir(),
                    paste0(gsub("/", "__", key, fixed = TRUE), ".csv.gz"))
  if (refresh || !file.exists(dest)) {
    .rmd_data_get(sprintf("/%s/%s.csv.gz", parts[[1L]],
                          paste(parts[-1L], collapse = "/")), dest)
  }
  utils::read.csv(gzfile(dest), stringsAsFactors = FALSE)
}
