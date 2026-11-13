# Curated datasets at data.rmorie.com: no sign-in and no key. A key that an
# earlier version stored is not read and never sent.
# The same tables the other packages pull; a manifest lists every table with
# its rows, columns, SHA-256 and the BigQuery public dataset it was built from.

# The data service, as the signed services document at rmorie.com describes it
# (read through rmoriebricklayer when it has svcs(); an older
# bricklayer leaves the address at its default). NULL when the document says
# the service is off.
.rmd_services_data <- function() {
  ns <- asNamespace("rmoriebricklayer")
  if (!exists("svcs", envir = ns, inherits = FALSE)) return(NULL)
  tryCatch(get("svcs", envir = ns)(offline = TRUE)[["data"]],
           error = function(e) NULL)
}

.rmd_data_url <- function() {
  env <- sub("/+$", "", trimws(Sys.getenv("MORIE_DATA_URL", unset = "")))
  if (nzchar(env)) return(env)
  svc <- .rmd_services_data()
  if (is.null(svc)) return("https://data.rmorie.com")
  if (!identical(svc[["mode"]], "key") || !nzchar(svc[["base_url"]] %||% "")) {
    stop("the curated-data service is not available right now (see ",
         svc[["request_access"]] %||% "https://www.rmorie.com/access/", ")",
         call. = FALSE)
  }
  svc[["base_url"]]
}

# The stored key, or NULL: sent only to the address of the signed services document,
# as rmoriebricklayer's dload() does. A key issued by data.rmorie.com does not follow
# MORIE_DATA_URL to another host.
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
  for (d in m[["datasets"]]) if (identical(d[["key"]], key)) return(d[["bytes_gz"]])
  NULL
}

# The SHA-256 the manifest lists for a table (NA when it lists none, NULL when the table
# is not listed); `refresh` fetches the manifest again first.
.rmd_manifest_sha <- function(key, refresh = FALSE) {
  d <- .rmd_manifest_entry(key, refresh)
  if (is.null(d)) return(NULL)
  if (.rmd_unserved(d)) .rmd_unserved_stop(key)
  .rmd_entry_sha(d, key)
}

# The digest of one manifest entry, read as rmoriebricklayer reads it: the field
# is sha256_gz, sha256 or sha, first present wins (631 tables carry only sha256_gz;
# reading sha256 alone used them unchecked). NA when none is present; a field that
# is present but not a SHA-256 hex digest is an error, never "no digest".
.rmd_entry_sha <- function(d, key) {
  for (f in c("sha256_gz", "sha256", "sha")) {
    s <- d[[f]]
    if (is.null(s)) next
    s <- if (is.character(s) && length(s) == 1L) sub("^sha256:", "", s) else NA
    if (!is.na(s) && grepl("^[0-9a-fA-F]{64}$", s)) return(tolower(s))
    stop(sprintf("the manifest's %s for %s is not a SHA-256 hex digest", f, key),
         call. = FALSE)
  }
  NA_character_
}

# The manifest's entry for a table, or NULL when it is not listed.
.rmd_manifest_entry <- function(key, refresh = FALSE) {
  for (d in .rmd_manifest(refresh)[["datasets"]]) {
    if (identical(d[["key"]], key)) return(d)
  }
  NULL
}

# The manifest, fetched when the cached copy is over a day old or `refresh`.
.rmd_manifest <- function(refresh = FALSE) {
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  age <- if (file.exists(p)) {
    as.numeric(difftime(Sys.time(), file.mtime(p), units = "secs"))
  } else {
    Inf
  }
  if (refresh || age >= 86400) .rmd_data_get("/manifest.json", p, timeout = 60)
  txt <- paste(readLines(p, warn = FALSE), collapse = "\n")
  .rmd_bl("fromjs")(txt, simplifyVector = FALSE)
}

# Tables data.rmorie.com does not serve: their source terms do not allow
# redistribution (ICPSR studies, the NCVS 38604 extract among them). This is the
# one list; a table the manifest itself marks (`access` other than "open" or
# "public", or `restricted: true`, on the entry or in its `meta`) is treated the
# same. They are left out of hostcat() and refused before any request.
.rmd_unserved_re <- "^(icpsr_|ncvs_38604)"

.rmd_unserved <- function(d) {
  k <- d[["key"]]
  if (is.character(k) && length(k) == 1L && grepl(.rmd_unserved_re, k)) return(TRUE)
  for (x in list(d, d[["meta"]])) {
    if (!is.list(x)) next
    a <- x[["access"]]
    if (is.character(a) && length(a) == 1L && !tolower(a) %in% c("open", "public")) {
      return(TRUE)
    }
    if (isTRUE(x[["restricted"]])) return(TRUE)
  }
  FALSE
}

.rmd_unserved_stop <- function(key) {
  if (grepl(.rmd_unserved_re, key)) {
    stop(key, " is not served by data.rmorie.com: ICPSR's terms do not allow ",
         "redistribution; download it from ICPSR (https://www.icpsr.umich.edu)",
         call. = FALSE)
  }
  stop(key, " is not served by data.rmorie.com: its source terms do not allow ",
       "redistribution; download it from its source (see hostcat())", call. = FALSE)
}

# Once per session and table: a table the manifest lists without any digest is
# used, but not silently.
.rmd_nodigest <- new.env(parent = emptyenv())

.rmd_warn_nodigest <- function(key) {
  if (!isTRUE(.rmd_nodigest[[key]])) {
    assign(key, TRUE, envir = .rmd_nodigest)
    warning(key, " is listed in the manifest of data.rmorie.com without a ",
            "SHA-256: it is used unverified", call. = FALSE)
  }
  invisible(TRUE)
}

# A downloaded table is used only when it matches the manifest's SHA-256 (fetched again
# once before a mismatch is called a damaged or tampered file); a table the manifest
# lists without a digest is used with a warning (once per session).
.rmd_check_sha <- function(key, dest) {
  unlisted <- function() {
    unlink(dest)
    stop(key, " is not listed in the manifest of data.rmorie.com", call. = FALSE)
  }
  want <- .rmd_manifest_sha(key)
  if (is.null(want)) unlisted()
  if (is.na(want)) return(.rmd_warn_nodigest(key))
  have <- tolower(.rmd_bl("sha256file")(dest))
  if (!identical(have, want)) {
    want <- .rmd_manifest_sha(key, refresh = TRUE)
    if (is.null(want)) unlisted()
    if (is.na(want)) return(.rmd_warn_nodigest(key))
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
  # the tables need no key, and none is sent: only the package's User-Agent
  old <- options(timeout = max(getOption("timeout", 60), timeout))
  on.exit(options(old), add = TRUE)
  hdr <- c("User-Agent" = "rmoriedata/1 (+https://rmorie.com)")
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
  if (inherits(rc, "condition")) .rmd_data_failed(rc, label)
  invisible(dest)
}

# Says why a download from data.rmorie.com failed.
.rmd_data_failed <- function(rc, label) {
  msg <- conditionMessage(rc)
  # the status the server answered, not digits that happen to sit in the table's own name
  # (statcan_indigenous/tbl_41100401 is a real key)
  code <- sub("^.*(answered HTTP|HTTP status was|HTTP error|HTTP)[ '\"]*([0-9]{3})\\b.*$",
              "\\2", msg)
  if (identical(code, msg)) code <- ""
  if (identical(code, "410") && grepl(.rmd_unserved_re, label)) {
    stop(label, " is not served by data.rmorie.com: ICPSR's terms do not allow ",
         "redistribution; download it from ICPSR (https://www.icpsr.umich.edu)",
         call. = FALSE)
  }
  if (identical(code, "410")) {
    stop(label, " is no longer served by data.rmorie.com: its source does not allow ",
         "redistribution; get it from its source.", call. = FALSE)
  }
  if (code %in% c("401", "403")) {
    stop("data.rmorie.com refused ", label, ": the tables need no sign-in; ",
         "update the package, or try again later.", call. = FALSE)
  }
  stop("data.rmorie.com: ", msg, call. = FALSE)
}

# The size of one part of a large download (option rmoriedata.dpart, 90 MB).
.rmd_part_bytes <- function() {
  v <- getOption("rmoriedata.dpart", 90 * 2^20)
  if (!(is.numeric(v) && length(v) == 1L && is.finite(v) && v >= 2^20)) {
    stop("option rmoriedata.dpart must be a number of bytes, at least 1 MB",
         call. = FALSE)
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
      .rmd_data_failed(rc, label)
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
#' Beyond the open data this package ships, the MORIE project keeps
#' databases materialised from Google BigQuery public datasets (Chicago
#' crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
#' Ethereum, World Bank, ...) and serves their tables from the edge. They
#' need no sign-in and no key; a key that an earlier version of rmorie,
#' morie or rmoriebricklayer stored is not read and never sent.
#' \code{hostcat()} returns every table with its key,
#' description, rows and BigQuery source (the manifest is kept for a day);
#' tables whose source terms do not allow redistribution (ICPSR studies,
#' among them the NCVS 38604 extract, and any table the manifest marks
#' restricted) are not served: they are left out, with a message counting
#' them, and \code{hostload()} refuses them before any request.
#' \code{hostload()} checks each table against the SHA-256 the manifest
#' lists for it (\code{sha256_gz}, \code{sha256} or \code{sha}) and refuses
#' a file that does not match; a table listed without any digest is used
#' with a warning, once per session.
#' \code{hostload("db/table")} returns one table, cached under
#' the package cache directory (\code{tempdir()} unless
#' \code{options(rmoriedata.cache_dir = )} names a persistent one).
#'
#' @param refresh Fetch again even when a day-old copy is cached.
#' @param key A \code{db/table} key from the catalog.
#' @return \code{hostcat()}: a data frame with \code{key},
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
  ds <- .rmd_manifest(refresh)[["datasets"]]
  off <- vapply(ds, .rmd_unserved, NA)
  if (any(off)) {
    message(sprintf(
      ngettext(sum(off), "%d table is not served: its source terms do not",
               "%d tables are not served: their source terms do not"),
      sum(off)), " allow redistribution")
    ds <- ds[!off]
  }
  if (!length(ds)) {
    return(data.frame(key = character(), name = character(), rows = integer(),
                      source = character(), stringsAsFactors = FALSE))
  }
  pick <- function(d, what) {
    v <- if (identical(what, "name")) d[["meta"]][["description"]] else d[[what]]
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
    rows = vapply(ds, function(d) {
      as.integer(if (is.null(d[["rows"]])) NA else d[["rows"]])
    }, 1L),
    source = vapply(ds, pick, "", what = "source"),
    stringsAsFactors = FALSE)
}

#' @rdname hostcat
#' @export
hostload <- function(key, refresh = FALSE) {
  ok <- is.character(key) && length(key) == 1L && grepl("/", key, fixed = TRUE) &&
    !startsWith(key, "/") && !endsWith(key, "/")
  if (!ok) {
    stop("key must be db/table (see hostcat())", call. = FALSE)
  }
  # a table that is not served is refused here, before any request: by its key
  # (no network at all), or as the manifest marks it
  if (grepl(.rmd_unserved_re, key)) .rmd_unserved_stop(key)
  d <- .rmd_manifest_entry(key)
  if (!is.null(d) && .rmd_unserved(d)) .rmd_unserved_stop(key)
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
