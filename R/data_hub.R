# Curated datasets at data.rmorie.com, with no sign-in; a MORIE key that rmorie,
# morie or rmoriebricklayer stored earlier in $XDG_CONFIG_HOME/morie/credentials.json
# is still sent.
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
  d <- tryCatch(.rmd_bl("fromjs")(txt),
                error = function(e) NULL)
  key <- d$hosted_key
  if (is.character(key) && length(key) == 1L && nzchar(key)) key else NULL
}

# The data service, as the signed services document at rmorie.com describes it
# (read through rmoriebricklayer when it has svcs(); an older
# bricklayer leaves the address at its default). NULL when the document says
# the service is off.
.rmd_services_data <- function() {
  ns <- asNamespace("rmoriebricklayer")
  if (!exists("svcs", envir = ns, inherits = FALSE)) return(NULL)
  tryCatch(get("svcs", envir = ns)(offline = TRUE)$data,
           error = function(e) NULL)
}

.rmd_access_hint <- function() {
  svc <- .rmd_services_data()
  sprintf("keys are personal: sign in with GitHub or an emailed code, or ask at %s",
          svc$request_access %||% "https://www.rmorie.com/access/")
}

.rmd_data_url <- function() {
  env <- sub("/+$", "", trimws(Sys.getenv("MORIE_DATA_URL", unset = "")))
  if (nzchar(env)) return(env)
  svc <- .rmd_services_data()
  if (is.null(svc)) return("https://data.rmorie.com")
  if (!identical(svc$mode, "key") || !nzchar(svc$base_url %||% "")) {
    stop("the curated-data service is not available right now (see ",
         svc$request_access %||% "https://www.rmorie.com/access/", ")", call. = FALSE)
  }
  svc$base_url
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
  m <- tryCatch(.rmd_bl("fromjs")(txt, simplifyVector = FALSE),
                error = function(e) NULL)
  for (d in m$datasets) if (identical(d$key, key)) return(d$bytes_gz)
  NULL
}

# The tables whose source licence asks more than attribution (ICPSR studies, the NCVS
# 38604 extract, the a2aj case law): data.rmorie.com opens them once the terms are
# accepted.
.rmd_restricted <- function(key) grepl("^(icpsr_|ncvs_38604|a2aj_)", key)

# The SHA-256 the manifest lists for a table (NA when it lists none, NULL when the table
# is not listed); `refresh` fetches the manifest again first.
.rmd_manifest_sha <- function(key, refresh = FALSE) {
  hostcat(refresh = refresh)  # fetches the manifest when stale or asked
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  m <- .rmd_bl("fromjs")(txt, simplifyVector = FALSE)
  for (d in m$datasets) {
    if (identical(d$key, key)) {
      s <- d$sha256
      ok <- is.character(s) && length(s) == 1L && nzchar(s)
      return(if (ok) tolower(s) else NA_character_)
    }
  }
  NULL
}

# A downloaded table is used only when it matches the manifest's SHA-256 (fetched again
# once before a mismatch is called a damaged or tampered file); a table the manifest
# lists without a digest is used as it is.
.rmd_check_sha <- function(key, dest) {
  unlisted <- function() {
    unlink(dest)
    stop(key, " is not listed in the manifest of data.rmorie.com", call. = FALSE)
  }
  want <- .rmd_manifest_sha(key)
  if (is.null(want)) unlisted()
  if (is.na(want)) return(invisible(TRUE))
  have <- tolower(.rmd_bl("sha256file")(dest))
  if (!identical(have, want)) {
    want <- .rmd_manifest_sha(key, refresh = TRUE)
    if (is.null(want)) unlisted()
    if (is.na(want)) return(invisible(TRUE))
  }
  if (!identical(have, want)) {
    unlink(dest)
    stop(sprintf(paste0("%s does not match the manifest's SHA-256 (%s... vs %s...): ",
                        "the file was deleted; run again, and if it still fails it ",
                        "was altered in transit"),
                 key, substr(have, 1L, 12L), substr(want, 1L, 12L)), call. = FALSE)
  }
  invisible(TRUE)
}

.rmd_data_get <- function(path, dest, timeout = 600) {
  # the open tables need no key; a stored one is still sent
  key <- .rmd_hosted_key()
  old <- options(timeout = max(getOption("timeout", 60), timeout))
  on.exit(options(old), add = TRUE)
  hdr <- c(if (!is.null(key)) c(Authorization = paste("Bearer", key)),
           "User-Agent" = "rmoriedata/1 (+https://rmorie.com)")
  label <- sub("\\.csv\\.gz$", "", sub("^/", "", path))
  size <- .rmd_hosted_size(path)
  part <- .rmd_part_bytes()
  if (!is.null(size) && is.finite(size) && size > 2 * part) {
    return(.rmd_get_parts(path, dest, hdr, label, size, part, timeout))
  }
  rc <- tryCatch(
    .rmd_dl(paste0(.rmd_data_url(), path), dest, headers = hdr, timeout = timeout,
            label = label, size = size),
    error = function(e) e, warning = function(w) w
  )
  if (inherits(rc, "condition")) .rmd_data_failed(rc, label, is.null(key))
  invisible(dest)
}

# Says why a download from data.rmorie.com failed.
.rmd_data_failed <- function(rc, label, keyless) {
  msg <- conditionMessage(rc)
  if (grepl("\\b410\\b|Gone", msg)) {
    stop(label, " is not served by data.rmorie.com: ICPSR's terms do not allow ",
         "redistribution; download it from ICPSR (https://www.icpsr.umich.edu)",
         call. = FALSE)
  }
  if (grepl("403|Forbidden", msg) && .rmd_restricted(label)) {
    stop(label, " is a restricted table (its source asks more than a citation): ",
         "read and accept the terms at https://data.rmorie.com/terms, signed in ",
         "with your key, then ask again.", call. = FALSE)
  }
  if (grepl("401|403|Unauthorized|Forbidden", msg) && keyless) {
    stop("data.rmorie.com asked for a key for ", label, ": run ",
         "hostlogin(token = ) once, or update the package.", call. = FALSE)
  }
  if (grepl("401|403|Unauthorized|Forbidden", msg)) {
    stop("the curated-data service rejected the stored key; store a valid one with ",
         "hostlogin(token = ) or sign in again.", call. = FALSE)
  }
  stop("data.rmorie.com: ", msg, call. = FALSE)
}

# The size of one part of a large download (option rmoriedata.dpart, 90 MB).
.rmd_part_bytes <- function() {
  v <- getOption("rmoriedata.dpart", 90 * 2^20)
  if (!(is.numeric(v) && length(v) == 1L && is.finite(v) && v >= 2^20)) {
    stop("option rmoriedata.dpart must be a number of bytes, at least 1 MB", call. = FALSE)
  }
  v
}

# Downloads a large table in parts, each a byte range of the file: a broken
# connection costs at most one part, each part is kept once whole, and a later
# run resumes from the first part still missing. The caller checks the joined
# file against the manifest SHA-256.
.rmd_get_parts <- function(path, dest, hdr, label, size, part, timeout) {
  starts <- seq(0, size - 1, by = part)
  n <- length(starts)
  pdir <- paste0(dest, ".parts")
  dir.create(pdir, recursive = TRUE, showWarnings = FALSE)
  pfile <- file.path(pdir, sprintf("%05d", seq_len(n)))
  for (i in seq_len(n)) {
    a <- starts[i]
    want <- min(a + part, size) - a
    if (file.exists(pfile[i]) && identical(file.size(pfile[i]), want)) next
    unlink(pfile[i])
    rc <- tryCatch(
      .rmd_dl(paste0(.rmd_data_url(), path), pfile[i],
              headers = c(hdr, Range = sprintf("bytes=%.0f-%.0f", a, a + want - 1)),
              label = sprintf("%s (part %d of %d)", label, i, n), size = want,
              timeout = timeout),
      error = function(e) e, warning = function(w) w
    )
    if (inherits(rc, "condition")) {
      .rmd_data_failed(rc, label, !("Authorization" %in% names(hdr)))
    }
    if (!identical(file.size(pfile[i]), want)) {
      got <- file.size(pfile[i])
      unlink(pfile[i])
      stop(sprintf(paste("data.rmorie.com: part %d of %s came back with %.0f bytes,",
                         "not %.0f; run again to resume from that part"),
                   i, label, got, want), call. = FALSE)
    }
  }
  out <- file(dest, "wb")
  for (f in pfile) {
    con <- file(f, "rb")
    repeat {
      buf <- readBin(con, "raw", 2^24)
      if (!length(buf)) break
      writeBin(buf, out)
    }
    close(con)
  }
  close(out)
  unlink(pdir, recursive = TRUE)
  invisible(dest)
}

#' Curated datasets at data.rmorie.com
#'
#' Beyond the open data this package ships, the MORIE project keeps more than 160
#' databases materialised from Google BigQuery public datasets (Chicago
#' crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
#' Ethereum, World Bank, ...) and serves their tables from the edge. They
#' need no sign-in; a MORIE key stored earlier by rmorie, morie or
#' rmoriebricklayer is still sent.
#' \code{hostcat()} returns every table with its key,
#' description, rows and BigQuery source (the manifest is kept for a day);
#' \code{hostload("db/table")} returns one table, cached under
#' the package cache directory (\code{tempdir()} unless
#' \code{options(rmoriedata.cache_dir = )} names a persistent one).
#'
#' @param refresh Fetch again even when a day-old copy is cached.
#' @param key A \code{db/table} key from the catalog.
#' @return \code{hostlogin()}: the key, invisibly, after storing it
#'   in the shared credentials file.
#'   \code{hostcat()}: a data frame with \code{key},
#'   \code{name}, \code{rows} and \code{source};
#'   \code{hostload()}: the table as a data frame.
#' @examples
#' \dontrun{
#' head(hostcat())
#' df <- hostload("chicago_crime/incidents")
#' }
#' @export
hostcat <- function(refresh = FALSE) {
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE", call. = FALSE)
  }
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  age <- if (file.exists(p)) {
    as.numeric(difftime(Sys.time(), file.mtime(p), units = "secs"))
  } else {
    Inf
  }
  fresh <- age < 86400
  if (refresh || !fresh) .rmd_data_get("/manifest.json", p, timeout = 60)
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  m <- .rmd_bl("fromjs")(txt, simplifyVector = FALSE)
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

#' @rdname hostcat
#' @param token,email,code,openbro Passed to
#'   \code{rmoriebricklayer::dlogin()}: a key you already hold (no
#'   longer needed for the tables, which open without sign-in), or an email
#'   address (a one-time code is
#'   sent; pass it as \code{code} in a non-interactive session). With neither,
#'   the GitHub device flow runs. The service address comes from the signed
#'   services document (\code{rmoriebricklayer::svcs()}).
#' @param ... Passed to \code{rmoriebricklayer::dlogin()}: the
#'   data access terms and who is asking, which a new key needs
#'   (\code{accter}, \code{name}, \code{affiliation}, \code{purpose},
#'   \code{restricted}, \code{supnm}, \code{suprole},
#'   \code{supemail}); what is not given is asked at the console.
#' @export
hostlogin <- function(token = NULL, email = NULL, code = NULL,
                                    openbro = interactive(), ...) {
  key <- .rmd_bl("dlogin")(token = token, email = email,
                                                code = code,
                                                openbro = openbro, ...)
  invisible(key)
}

#' @rdname hostcat
#' @export
hostload <- function(key, refresh = FALSE) {
  ok <- is.character(key) && length(key) == 1L && grepl("/", key, fixed = TRUE) &&
    !startsWith(key, "/") && !endsWith(key, "/")
  if (!ok) {
    stop("key must be db/table (see hostcat())", call. = FALSE)
  }
  parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
  dest <- file.path(.rmd_data_cache_dir(),
                    paste0(gsub("/", "__", key, fixed = TRUE), ".csv.gz"))
  if (refresh || !file.exists(dest)) {
    .rmd_data_get(sprintf("/%s/%s.csv.gz", parts[[1L]],
                          paste(parts[-1L], collapse = "/")), dest)
  }
  .rmd_check_sha(key, dest)
  # fill = FALSE: a row with a field missing or one too many is a damaged download;
  # it is removed so the next call fetches it again instead of padding the rows
  tryCatch(
    utils::read.csv(gzfile(dest), stringsAsFactors = FALSE, fill = FALSE),
    error = function(e) {
      unlink(dest)
      stop(sprintf(paste0("the table %s did not parse (%s); ",
                          "the damaged copy was removed, try again"),
                   key, conditionMessage(e)), call. = FALSE)
    }
  )
}

`%||%` <- function(a, b) if (is.null(a)) b else a
