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
  if (nzchar(env)) {
    # an address, not a bare host: the failure would otherwise be laid on
    # data.rmorie.com, which was never asked
    # (a scheme is written in either case: RFC 3986, section 3.1)
    if (!grepl(.rmd_http_re, env)) {
      stop("the environment variable MORIE_DATA_URL is ", sQuote(env, FALSE), ", which ",
           "is not an http(s) address: unset it, or give one such as ",
           "https://data.rmorie.com", call. = FALSE)
    }
    return(env)
  }
  svc <- .rmd_services_data()
  if (is.null(svc)) return("https://data.rmorie.com")
  u <- .rmd_svc_field(svc, "base_url")
  if (!identical(.rmd_svc_field(svc, "mode"), "key") || is.null(u) ||
        !grepl(.rmd_http_re, u)) {
    stop("the curated-data service is not available right now (see ",
         .rmd_svc_field(svc, "request_access") %||% "https://www.rmorie.com/access/",
         ")", call. = FALSE)
  }
  u
}

# An http(s) address with a host: the scheme in either case, spelled out rather
# than matched with ignore.case, which follows the locale.
.rmd_http_re <- "^[Hh][Tt][Tt][Pp][Ss]?://[^/[:space:]]+"

# A field of the services document's entry for the data service when it is one
# string, else NULL: a document in another shape (not an object, a field that is a
# list, several strings, NA) says the service is not available, never where it is.
.rmd_svc_field <- function(svc, name) {
  v <- if (is.list(svc)) svc[[name]]
  if (.rmd_string(v)) v
}

# The stored key, or NULL: sent only to the address of the signed services document,
# as rmoriebricklayer's dload() does. A key issued by data.rmorie.com does not follow
# MORIE_DATA_URL to another host.
.rmd_data_cache_dir <- function() {
  .rmd_mkdir(file.path(.rmd_cache_dir(), "hosted"))
}

.rmd_hosted_size <- function(path) {
  # the cached manifest knows the compressed size: a percent bar instead of a spinner
  if (!grepl("\\.csv\\.gz$", path)) return(NULL)
  key <- sub("\\.csv\\.gz$", "", sub("^/", "", path))
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  # read under the manifest's lock, as .rmd_manifest() reads it: unlocked, the
  # read could meet another session renaming its copy into place
  m <- .rmd_locked(paste0(p, ".lock"), "the manifest of data.rmorie.com",
                   function() if (file.exists(p)) .rmd_manifest_parse(p))
  if (!is.list(m)) return(NULL)
  d <- .rmd_entry_of(m[["datasets"]], key)
  if (is.null(d)) NULL else .rmd_size_ok(d[["bytes_gz"]], key)
}

# The largest table size believed from a manifest (1 TiB): a size past it, or one that
# is not a positive whole number, is a damaged manifest, not a plan for 10^9 parts.
.rmd_size_cap <- 2^40

.rmd_size_ok <- function(v, key) {
  if (is.null(v)) return(NULL)
  if (!(is.numeric(v) && length(v) == 1L && is.finite(v) && v >= 1 &&
        v == floor(v) && v <= .rmd_size_cap)) {
    stop(sprintf(paste0("the manifest of data.rmorie.com gives %s a size of %s bytes, ",
                        "which is not a whole number from 1 to 2^40 (1 TiB); the ",
                        "manifest is damaged: try again later, or run ",
                        "hostcat(refresh = TRUE)"),
                 key, paste(if (is.numeric(v)) .rmd_ntxt(v) else format(v),
                            collapse = " ")), call. = FALSE)
  }
  v
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
    if (!is.na(s) && grepl("^[0-9a-fA-F]{64}$", s, useBytes = TRUE)) return(.rmd_lower(s))
    stop(sprintf("the manifest's %s for %s is not a SHA-256 hex digest", f, key),
         call. = FALSE)
  }
  NA_character_
}

# The manifest's entry for a table, or NULL when it is not listed.
.rmd_manifest_entry <- function(key, refresh = FALSE) {
  .rmd_entry_of(.rmd_manifest(refresh)[["datasets"]], key)
}

# The entry the datasets `ds` list for `key`, or NULL. A key listed more than once
# is one table: an entry that is not served decides it (the first served one was
# used, and an entry marked restricted after it was ignored), and entries that
# differ in anything else are a damaged manifest, not a choice.
.rmd_entry_of <- function(ds, key) {
  hit <- Filter(function(d) identical(d[["key"]], key), ds)
  if (length(hit) < 2L) return(if (length(hit)) hit[[1L]])
  off <- vapply(hit, .rmd_unserved, NA)
  if (any(off)) return(hit[[which(off)[1L]]])
  if (!all(vapply(hit, identical, NA, hit[[1L]]))) {
    stop("the manifest of data.rmorie.com lists ", key, " ", length(hit), " times, ",
         "not all the same; the manifest is damaged: try again later, or run ",
         "hostcat(refresh = TRUE)", call. = FALSE)
  }
  hit[[1L]]
}

# The manifest, fetched when the cached copy is over a day old or `refresh`.
# Fetched and read under a lock on "manifest.json.lock", as a table is: sessions
# that started together each fetched it and renamed their copy over the cached
# one while another was reading it, and on Windows, where a file that is being
# replaced cannot be opened, that read failed with "cannot open the connection".
.rmd_manifest <- function(refresh = FALSE) {
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  .rmd_locked(paste0(p, ".lock"), "the manifest of data.rmorie.com",
              function() .rmd_manifest_get(p, refresh))
}

# The body of .rmd_manifest(), run while its lock is held.
.rmd_manifest_get <- function(p, refresh) {
  age <- if (file.exists(p)) {
    as.numeric(difftime(Sys.time(), file.mtime(p), units = "secs"))
  } else {
    Inf
  }
  fresh <- refresh || age >= 86400
  # a refresh that failed a moment ago for this same cached copy is not tried
  # again within one call (hostload() reads the manifest more than once)
  if (fresh && !refresh && is.finite(age) && identical(.rmd_stale$path, p) &&
      identical(.rmd_stale$mtime, file.mtime(p)) &&
      as.numeric(difftime(Sys.time(), .rmd_stale$when, units = "secs")) < 300) {
    fresh <- FALSE
  }
  if (fresh && !refresh && is.finite(age)) {
    # past a day old: fetched again, but when that fails (offline, the service
    # down) the cached copy that still parses is used, with one message. The tables
    # are still checked against the digests it lists, so a cached table is used
    # only when it matches them.
    got <- tryCatch(.rmd_data_get("/manifest.json", p, timeout = 60),
                    error = function(e) e)
    if (inherits(got, "error")) {
      old <- .rmd_manifest_parse(p)
      if (!is.list(old)) stop(got)
      .rmd_stale$path <- p
      .rmd_stale$mtime <- file.mtime(p)
      .rmd_stale$when <- Sys.time()
      message("rmoriedata: the manifest of data.rmorie.com could not be refreshed (",
              conditionMessage(got), "); using the copy cached on ",
              format(file.mtime(p), "%Y-%m-%d"))
      return(old)
    }
  } else if (fresh) {
    # no copy is cached, or refresh = TRUE: then the manifest must be fetched,
    # and a fetch that fails is an error, never the cached copy
    tryCatch(.rmd_data_get("/manifest.json", p, timeout = 60),
             error = function(e) {
               if (!is.finite(age)) stop(e)
               stop(conditionMessage(e), "; with refresh = TRUE the cached ",
                    "manifest is not used", call. = FALSE)
             })
  }
  m <- .rmd_manifest_parse(p)
  if (!is.list(m) && !fresh) {
    # a damaged cached copy is treated as absent: fetched again, once
    message("rmoriedata: the cached manifest of data.rmorie.com could not be read; ",
            "fetching it again")
    .rmd_data_get("/manifest.json", p, timeout = 60)
    m <- .rmd_manifest_parse(p)
  }
  if (!is.list(m)) {
    stop("data.rmorie.com sent a manifest that could not be read (", m, "); ",
         "try again later", call. = FALSE)
  }
  m
}

# The cached manifest whose refresh last failed (its path, under the cache folder in
# use then, and its time stamp), and when.
.rmd_stale <- new.env(parent = emptyenv())

# The parsed manifest, or the reason it does not parse (a string). Its shape is
# checked here, once, for every reader: a JSON object whose `datasets` is an
# array of objects. A string, an array of numbers or a top-level array stopped
# hostcat() and hostload() with "subscript out of bounds", or read as an empty
# catalogue.
.rmd_manifest_parse <- function(p) {
  # read once, a regular file only (a FIFO in its place blocked the reader)
  b <- .rmd_bytes(p)
  if (!is.raw(b)) return(paste("the file", b))
  m <- tryCatch(.rmd_bl("fromjs")(paste(.rmd_lines(b), collapse = "\n"),
                                  simplifyVector = FALSE),
                error = function(e) e)
  # memory that ran short says nothing about the file: an error, and the copy is kept
  # (read as damaged, it was fetched again over a valid copy)
  if (inherits(m, "error") && .pq_alloc_failed(conditionMessage(m))) {
    stop("not enough memory to read the manifest of data.rmorie.com (",
         conditionMessage(m), ")", call. = FALSE)
  }
  if (inherits(m, "error")) return(conditionMessage(m))
  if (!is.list(m) || is.null(names(m))) return("not a JSON object")
  ds <- m[["datasets"]]
  obj <- function(x) is.list(x) && (!length(x) || !is.null(names(x)))
  if (!is.list(ds) || (length(ds) && !is.null(names(ds))) ||
        !all(vapply(ds, obj, NA))) {
    return("its datasets are not an array of objects")
  }
  m
}

# Tables data.rmorie.com does not serve: their source terms do not allow
# redistribution (ICPSR studies, the NCVS 38604 extract among them). This is the
# one list; a table the manifest itself marks is treated the same. They are left
# out of hostcat() and refused before any request.
# A mark fails closed: an entry is served only when its key is one string and every
# mark it carries, on the entry or in its `meta` object, is one the package knows to
# be open, in the shape it knows: `access` absent or the one string "open" or
# "public" (in any case), and `restricted` absent or JSON false. Any other value,
# type or length ("closed", ["open"], which is parsed as a list, "true", 1, null,
# two values) is a table not served, and so is a `meta` that is an array.
.rmd_unserved_re <- "^(icpsr_|ncvs_38604)"

.rmd_unserved <- function(d) {
  k <- d[["key"]]
  m <- d[["meta"]]
  array <- is.list(m) && length(m) && is.null(names(m))
  !.rmd_key_ok(k) || grepl(.rmd_unserved_re, k) || array ||
    !.rmd_open_marks(d) || !.rmd_open_marks(if (is.list(m)) m)
}

# One string, not NA.
.rmd_string <- function(x) is.character(x) && length(x) == 1L && !is.na(x)

# Whether `key` is a key as the manifest writes them: two or more segments joined by
# single slashes, each of ASCII letters, digits, "_", "-" and ".", not starting with
# a dot. Nothing else names a table, so nothing else is looked up, requested or
# made into a file name: "db/./t", "db/x/../t" and "./db/t" were requested (a
# client removes the dot segments, so the request named "db/t", which the manifest
# closes), and ".." would leave the cache folder.
.rmd_key_ok <- function(key) {
  .rmd_string(key) &&
    grepl("^[A-Za-z0-9_-][A-Za-z0-9_.-]*(/[A-Za-z0-9_-][A-Za-z0-9_.-]*)+$", key,
          useBytes = TRUE)
}

# Whether every `access` and `restricted` mark of the object `x` (a field given
# twice is checked twice) is a known open value in its known shape.
.rmd_open_marks <- function(x) {
  nm <- names(x)
  # ASCII case only: in Turkish tolower("PUBLIC") has a dotless i, and the table was
  # not served
  open <- function(a) .rmd_string(a) && .rmd_lower(a) %in% c("open", "public")
  all(vapply(x[nm %in% "access"], open, NA)) &&
    all(vapply(x[nm %in% "restricted"], identical, NA, FALSE))
}

# Which datasets `ds` are not served: their own marks, or their key listed again in
# an entry that is not served (.rmd_entry_of()).
.rmd_off <- function(ds) {
  off <- vapply(ds, .rmd_unserved, NA)
  keys <- vapply(ds, function(d) {
    if (.rmd_string(d[["key"]])) d[["key"]] else NA_character_
  }, "")
  off | keys %in% keys[off]
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

# Once per session, table and cache folder: a table the manifest lists without any
# digest is used, but not silently; a manifest in another cache folder warns again.
.rmd_nodigest <- new.env(parent = emptyenv())

.rmd_warn_nodigest <- function(key) {
  id <- paste0(.rmd_data_cache_dir(), "\n", key)
  if (!isTRUE(.rmd_nodigest[[id]])) {
    assign(id, TRUE, envir = .rmd_nodigest)
    warning(key, " is listed in the manifest of data.rmorie.com without a ",
            "SHA-256: it is used unverified", call. = FALSE)
  }
  invisible(TRUE)
}

# A downloaded table is used only when it matches the manifest's SHA-256 (fetched again
# once before a mismatch is called a damaged or tampered file); a table the manifest
# lists without a digest is used with a warning (once per session). The file is read
# once and its bytes returned: they are what was checked, and what hostload() reads
# (checked by path and read again by path, a copy replaced between the two was read
# unchecked).
.rmd_check_sha <- function(key, dest) {
  # neither proves the file bad: it is left as it is
  unlisted <- function() {
    stop(key, " is not listed in the manifest of data.rmorie.com", call. = FALSE)
  }
  want <- .rmd_manifest_sha(key)
  if (is.null(want)) unlisted()
  b <- .rmd_bytes(dest)
  if (!is.raw(b)) {
    stop(sprintf("the cached copy of %s %s; it was left in place: run again", key, b),
         call. = FALSE)
  }
  if (is.na(want)) {
    .rmd_warn_nodigest(key)
    return(b)
  }
  have <- .Call(C_morie_core_sha256, b)
  if (!identical(have, want)) {
    want <- .rmd_manifest_sha(key, refresh = TRUE)
    if (is.null(want)) unlisted()
    if (is.na(want)) {
      .rmd_warn_nodigest(key)
      return(b)
    }
  }
  if (!identical(have, want)) {
    unlink(dest)
    stop(sprintf(paste0("%s does not match the manifest's SHA-256 (%s... vs %s...): ",
                        "the file was deleted; run again, and if it still fails it ",
                        "was altered in transit"),
                 key, substr(have, 1L, 12L), substr(want, 1L, 12L)), call. = FALSE)
  }
  b
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
  # written beside `dest` under a name of its own and renamed when whole: sessions
  # fetching the manifest at once each write their own file, and none reads a half
  tmp <- tempfile(paste0(basename(dest), ".get"), tmpdir = dirname(dest))
  on.exit(unlink(tmp), add = TRUE)
  rc <- tryCatch(
    .rmd_dl(paste0(.rmd_data_url(), path), tmp, headers = hdr, timeout = timeout,
            label = label, size = size),
    error = function(e) e, warning = function(w) w
  )
  if (inherits(rc, "condition")) .rmd_data_failed(rc, label)
  if (file.exists(tmp)) .rmd_move(tmp, dest)
  invisible(dest)
}

# Renames a finished file over `dest` (one step: a reader sees the old file or the
# new one, never a half), or stops in words.
.rmd_move <- function(from, dest) {
  if (!suppressWarnings(file.rename(from, dest))) {
    stop(sprintf(paste0("cannot move the downloaded %s into place as %s: the folder ",
                        "cannot be written, or %s is in use"),
                 basename(dest), dest, basename(dest)), call. = FALSE)
  }
  invisible(dest)
}

# Downloads a hosted table into `dest` for hostload(), one R session at a time.
# Sessions downloading the same table take turns on an operating-system lock on
# "<dest>.lock" (src/flock.c): the kernel releases it when its holder exits or is
# killed, so it is never left stale, and no session has to guess whether another
# is still alive. Under the lock the table is fetched to "<dest>.dl" (its parts in
# "<dest>.dl.parts"; names only the holder uses, so they are fixed and a killed
# download resumes from its parts), checked against the manifest's SHA-256, and
# only then renamed over `dest`. A session that waited and finds a table finished
# while it waited uses it. Join and download files left by a killed session are
# removed: under the lock, no live session owns one. Returns the table's bytes, read
# once under the lock and checked.
.rmd_fetch <- function(key, path, dest, refresh) {
  before <- file.mtime(dest)
  .rmd_locked(paste0(dest, ".lock"), key, function() {
    now <- file.mtime(dest)
    if (!is.na(now) && (!refresh || !identical(now, before))) {
      return(.rmd_check_sha(key, dest))
    }
    tmp <- paste0(dest, ".dl")
    left <- list.files(dirname(dest), full.names = TRUE)
    stale <- startsWith(basename(left), paste0(basename(tmp), ".join")) |
      startsWith(basename(left), paste0(basename(tmp), ".get"))
    unlink(c(tmp, left[stale]))
    on.exit(unlink(tmp), add = TRUE)
    .rmd_data_get(path, tmp)
    b <- .rmd_check_sha(key, tmp)
    .rmd_move(tmp, dest)
    b
  })
}

# Runs fn() holding the lock file `lock`, waiting (with one message) while another
# R session holds it. The wait ends with an error once the holder's download has not
# grown for `options(rmoriedata.lockwait = )` seconds (600 by default): a session
# that is stalled (a hung connection, a stopped process) holds the lock, and the
# others would otherwise wait for ever. A download that is making progress is
# waited for however long it takes.
.rmd_locked <- function(lock, label, fn) {
  busy <- new.env()
  said <- FALSE
  wait <- .rmd_lock_wait()
  dest <- sub("\\.lock$", "", lock)
  last <- NULL
  since <- Sys.time()
  repeat {
    r <- .Call(C_rmd_flock_with, lock, fn, busy)
    if (!identical(r, busy)) return(invisible(r))
    if (!said) {
      message("rmoriedata: another R session is downloading ", label,
              "; waiting for it to finish")
      said <- TRUE
    }
    now <- .rmd_progress(dest)
    if (!identical(now, last)) {
      last <- now
      since <- Sys.time()
    } else if (as.numeric(difftime(Sys.time(), since, units = "secs")) > wait) {
      stop(sprintf(paste0("another R session has held the download of %s for %g ",
                          "seconds without the download growing: that session may ",
                          "be stalled. Stop it (its lock is released when it exits) ",
                          "and run again, or wait longer with ",
                          "options(rmoriedata.lockwait = <seconds>)"),
                   label, wait), call. = FALSE)
    }
    Sys.sleep(0.1)
  }
}

# How long a session waits for a lock holder whose download does not grow
# (option rmoriedata.lockwait, seconds).
.rmd_lock_wait <- function() {
  v <- getOption("rmoriedata.lockwait", 600)
  if (!(is.numeric(v) && length(v) == 1L && !is.na(v) && v > 0)) {
    stop("option rmoriedata.lockwait must be a positive number of seconds",
         call. = FALSE)
  }
  v
}

# The sizes and times of the files a download of `dest` writes ("<dest>.dl...", the
# parts in "<dest>.dl.parts"), and of `dest` itself: they change while it progresses.
.rmd_progress <- function(dest) {
  b <- basename(dest)
  f <- list.files(dirname(dest), full.names = TRUE, all.files = TRUE, no.. = TRUE)
  f <- f[basename(f) == b | startsWith(basename(f), paste0(b, ".dl"))]
  f <- c(f, list.files(paste0(dest, ".dl.parts"), full.names = TRUE))
  i <- file.info(f, extra_cols = FALSE)
  c(sum(i$size, na.rm = TRUE), suppressWarnings(max(as.numeric(i$mtime), na.rm = TRUE)))
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
  msg <- .rmd_why(msg)
  # the transport's message names the address it tried; when it does not, the service
  stop(sprintf("%s could not download %s%s: %s", .rmd_ctx$fn %||% "rmoriedata", label,
               if (grepl("://", msg, fixed = TRUE)) "" else " from data.rmorie.com", msg),
       call. = FALSE)
}

# The function the user called, for messages raised deep in a download (set by
# hostcat() and hostload(); NULL otherwise).
.rmd_ctx <- new.env(parent = emptyenv())

# A transport's error text without the name of the dependency's function in front
# ("bldl: ...", "blfetch: ..."): the user called an rmoriedata function.
.rmd_why <- function(msg) sub("^bl[a-z]*: ", "", msg)

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
  # a failed run keeps the parts it finished, never an empty directory
  on.exit(if (!length(list.files(pdir))) unlink(pdir, recursive = TRUE), add = TRUE)
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
    got <- file.size(pfile[i])
    if (!is.na(got) && got > want) {
      # the server ignored the Range header and sent the whole file (HTTP 200):
      # keep it when it is the whole file, else fetch it once in one piece
      unlink(dest)
      if (got != size || !file.rename(pfile[i], dest)) {
        rc <- tryCatch(
          .rmd_dl(paste0(.rmd_data_url(), path), dest, headers = hdr, label = label,
                  size = size, timeout = timeout),
          error = function(e) e, warning = function(w) w
        )
        if (inherits(rc, "condition")) .rmd_data_failed(rc, label)
      }
      unlink(pdir, recursive = TRUE)
      return(invisible(dest))
    }
    if (!identical(got, want)) {
      unlink(pfile[i])
      stop(sprintf(paste("data.rmorie.com: part %d of %s came back with %.0f bytes,",
                         "not %.0f; run again to resume from that part"),
                   i, label, got, want), call. = FALSE)
    }
  }
  .rmd_join(pfile, dest)
  unlink(pdir, recursive = TRUE)
  invisible(dest)
}

# Joins the parts of a download into `dest`. The file is written beside `dest`
# and renamed when whole, so a join cut short leaves nothing that looks
# finished; each part is deleted once it is joined (the two together took
# twice the table's size); and a write that fails is an error in words:
# writeBin() only warns when the disk is full, and the short file then failed
# its checksum as if it had been tampered with. Every part is checked to be there
# and readable before the first is joined, so a missing or unreadable part stops
# the join with all parts kept, and the next run downloads only what is missing.
# A part that goes missing during the join is an error in words; the parts already
# joined are gone, and the next run downloads them again. The file being written
# has a name of its own per call. hostload() downloads a table under a lock
# (.rmd_fetch()), so no other session touches these parts meanwhile.
.rmd_join <- function(pfile, dest) {
  gone <- which(!file.exists(pfile) | file.access(pfile, 4L) != 0L)
  if (length(gone)) {
    stop(sprintf(paste0("cannot join the parts of %s: part %d (%s) is missing or ",
                        "cannot be read; no part was joined or deleted. Run again ",
                        "to download it."),
                 basename(dest), gone[[1L]], pfile[[gone[[1L]]]]), call. = FALSE)
  }
  tmp <- tempfile(paste0(basename(dest), ".join"), tmpdir = dirname(dest))
  total <- sum(file.size(pfile))
  full <- function() {
    stop(sprintf(paste0("cannot join the parts of %s: the folder %s is full or cannot ",
                        "be written (the file needs %.0f MB). Name a folder with ",
                        "room in options(rmoriedata.cache_dir = ) and run again."),
                 basename(dest), dirname(dest), total / 2^20), call. = FALSE)
  }
  out <- file(tmp, "wb")
  open <- TRUE
  on.exit({
    if (open) close(out)
    unlink(tmp)
  }, add = TRUE)
  for (i in seq_along(pfile)) {
    con <- tryCatch(file(pfile[[i]], "rb"), warning = function(w) NULL,
                    error = function(e) NULL)
    if (is.null(con)) {
      stop(sprintf(paste0("cannot join the parts of %s: part %d (%s) went missing ",
                          "or could not be read during the join; run again to ",
                          "download what is missing."),
                   basename(dest), i, pfile[[i]]), call. = FALSE)
    }
    ok <- tryCatch({
      repeat {
        buf <- readBin(con, "raw", 2^24)
        if (!length(buf)) break
        .rmd_write_raw(buf, out)
      }
      TRUE
    }, warning = function(w) FALSE, error = function(e) FALSE, finally = close(con))
    if (!ok) full()
    unlink(pfile[[i]])
  }
  close(out)
  open <- FALSE
  if (!identical(as.numeric(file.size(tmp)), as.numeric(total))) full()
  unlink(dest)
  if (!file.rename(tmp, dest)) full()
  invisible(dest)
}

# writeBin(), under a name the tests can replace.
.rmd_write_raw <- function(buf, out) {
  writeBin(buf, out)
  invisible(NULL)
}

#' Curated datasets at data.rmorie.com
#'
#' Beyond the open data this package ships, the MORIE project keeps
#' databases materialised from Google BigQuery public datasets (Chicago
#' crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
#' Ethereum, World Bank, ...) and serves their tables from the edge. They
#' need no sign-in and no key; a key that an earlier version of this or a
#' related package stored is not read and never sent.
#' \code{hostcat()} returns every table with its key,
#' description, rows and BigQuery source (the manifest is kept for a day);
#' tables whose source terms do not allow redistribution (ICPSR studies,
#' among them the NCVS 38604 extract, and any table the manifest marks
#' restricted) are not served: they are left out, with a message counting
#' them, and \code{hostload()} refuses them before any request. A table is
#' served only when its \code{access} mark, if any, is \code{"open"} or
#' \code{"public"} and its \code{restricted} mark, if any, is \code{false};
#' a mark of any other value or shape counts as restricted.
#' \code{hostload()} checks each table against the SHA-256 the manifest
#' lists for it (\code{sha256_gz}, \code{sha256} or \code{sha}) and refuses
#' a file that does not match; a table listed without any digest is used
#' with a warning, once per session.
#' \code{hostload("db/table")} returns one table, cached under
#' the package cache directory (\code{tempdir()} unless
#' \code{options(rmoriedata.cache_dir = )} names a persistent one).
#'
#' \code{hostload()} returns the table as the file holds it, as the bundled
#' tables are read: the column names as written (as the manifest lists
#' them); an empty field is missing in a logical or number column and
#' \code{""} in a text column (the text \code{"NA"} is a value).
#' A column is logical, integer or double only when every value in it is
#' written the way R writes such a value: \code{TRUE} or \code{FALSE};
#' whole numbers without a leading zero or a plus sign; for double, numbers
#' without a leading zero, whole ones of at most 15 digits (which a double
#' holds exactly) and decimal ones of at most 17 significant digits (zeros
#' after the decimal point are formatting, and \code{"6.0"} is 6), or in R's
#' own exponent form (\code{1e-05}). Any other column is text, so a code
#' such as \code{"046"} keeps its leading zero, and \code{"+3"},
#' \code{".5"}, \code{"0x1A"}, \code{"Inf"} or an identifier of 16 or more
#' digits keep every character. A column with no value at all is logical
#' \code{NA}.
#' Text is marked UTF-8, whatever the session's locale; bytes that are not
#' valid UTF-8 are marked \code{"bytes"}, and a NUL byte, which no R string
#' holds, is dropped. Quoted fields may hold commas,
#' quotes and line breaks (a Windows line end inside a field reads as
#' \code{"\\n"}); Windows line ends and a byte-order mark are allowed. A
#' record with more or fewer fields than the header is a damaged download:
#' the copy is deleted and the call fails, so the next call fetches it again.
#' A table's file is its gzip members, each one read: NUL bytes after the
#' last member are ignored, as \code{gzip -d} ignores them, and any other
#' bytes after it are refused, never read as rows. A cached copy is deleted
#' only when it does not match the manifest's digest or is damaged itself;
#' a table that cannot be read for another reason (memory that runs short,
#' bytes after its gzip data, a session option) stops with the copy left in
#' place. Each table is cached in a file of its own under
#' \code{hosted/tables} in the cache folder, named from its key so that no
#' two keys share one (two that differ only in case included); tables that
#' versions before 0.4.3 cached under \code{hosted/} are not read, and are
#' fetched again once.
#'
#' The manifest is fetched again once the cached copy is a day old. When
#' that fails (offline, or the service is down) the cached copy is used, with
#' a message, so a table already cached in a persistent
#' \code{rmoriedata.cache_dir} still loads offline; every table is still
#' checked against the digest the manifest lists, and one that does not
#' match is not used. With \code{refresh = TRUE} the manifest must be fetched:
#' when it cannot be, \code{hostcat()} and \code{hostload()} stop with an
#' error instead of using the cached copy.
#'
#' R sessions loading the same table take turns: while one downloads it, or
#' checks its cached copy, the others wait. A session whose wait sees the
#' download not grow for \code{options(rmoriedata.lockwait = )} seconds
#' (600 by default) stops with an error saying the other session may be
#' stalled.
#'
#' @param refresh Fetch again even when a day-old copy is cached.
#' @param key A \code{db/table} key from the catalog: segments of ASCII
#'   letters, digits, \code{_}, \code{-} and \code{.}, none starting with a dot,
#'   joined by single slashes. Any other key is refused before anything is
#'   requested, and a manifest entry whose key is not of this form is not served.
#' @return \code{hostcat()}: a data frame with \code{key},
#'   \code{name}, \code{rows} (\code{NA} where the manifest gives no whole
#'   count) and \code{source};
#'   \code{hostload()}: the table as a data frame.
#' @examples
#' \dontrun{
#' head(hostcat())
#' df <- hostload("chicago_crime/incidents")
#' }
#' @export
hostcat <- function(refresh = FALSE) {
  .rmd_bounds()
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE", call. = FALSE)
  }
  .rmd_ctx$fn <- "hostcat()"
  on.exit(.rmd_ctx$fn <- NULL, add = TRUE)
  ds <- .rmd_manifest(refresh)[["datasets"]]
  off <- .rmd_off(ds)
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
    # `meta` that is not an object has no description (a string's [[ ]] failed)
    m <- d[["meta"]]
    v <- if (!identical(what, "name")) d[[what]] else if (is.list(m)) {
      m[["description"]]
    }
    if (is.null(v) || !length(v)) "" else .rmd_text(v)[[1L]]
  }
  data.frame(
    key = vapply(ds, pick, "", what = "key"),
    name = vapply(ds, function(d) {
      n <- pick(d, "name")
      if (nzchar(n)) return(n)
      s <- pick(d, "source")
      if (nzchar(s)) s else pick(d, "key")
    }, ""),
    # a count that is not a whole number from 0 to the integer range is NA,
    # read without base R's coercion warning ("many", 1e12)
    rows = vapply(ds, function(d) {
      v <- d[["rows"]]
      if (is.character(v)) v <- .rmd_num(v)
      ok <- is.numeric(v) && length(v) == 1L && !is.na(v) && v >= 0 &&
        v == floor(v) && v <= .Machine$integer.max
      if (ok) as.integer(v) else NA_integer_
    }, 1L),
    source = vapply(ds, pick, "", what = "source"),
    stringsAsFactors = FALSE)
}

#' @rdname hostcat
#' @export
hostload <- function(key, refresh = FALSE) {
  .rmd_bounds()
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE", call. = FALSE)
  }
  .rmd_nobytes(key, "key")
  # checked before any lookup, request or file name is made from it
  if (!.rmd_key_ok(key)) {
    stop("key must be db/table as hostcat() lists it: segments of ASCII letters, ",
         "digits, \"_\", \"-\" and \".\", none starting with a dot, joined by single ",
         "slashes", call. = FALSE)
  }
  .rmd_ctx$fn <- "hostload()"
  on.exit(.rmd_ctx$fn <- NULL, add = TRUE)
  # a table that is not served is refused here, before any request: by its key
  # (no network at all), or as the manifest marks it
  if (grepl(.rmd_unserved_re, key)) .rmd_unserved_stop(key)
  d <- .rmd_manifest_entry(key, refresh)
  if (!is.null(d) && .rmd_unserved(d)) .rmd_unserved_stop(key)
  parts <- strsplit(key, "/", fixed = TRUE)[[1L]]
  dest <- .rmd_host_file(key)
  # a cached copy is checked under the same lock as a download: checked unlocked, a
  # copy another session had just refreshed could be hashed half replaced, called
  # damaged and deleted
  b <- .rmd_fetch(key, sprintf("/%s/%s.csv.gz", parts[[1L]],
                               paste(parts[-1L], collapse = "/")), dest, refresh)
  d <- .rmd_parse_hosted(key, b, dest)
  # the copy an earlier version kept beside the manifest, under a name two keys
  # could share: nothing reads it now, and the table is held under its own name
  unlink(file.path(.rmd_data_cache_dir(),
                   paste0(gsub("/", "__", key, fixed = TRUE), ".csv.gz")))
  d
}

# The table from its checked bytes `b`. Damage in the bytes themselves (a damaged gzip
# member, a record with a field missing or one too many) removes the copy, so the next
# call fetches it again instead of padding the rows; it is removed only while it still
# holds those bytes (another session may have fetched it again meanwhile). Any other
# error (memory, bytes after the gzip data, a session option) proves nothing about the
# copy, which stays.
.rmd_parse_hosted <- function(key, b, dest) {
  # one handler, not two: a second one would catch the first one's stop()
  why <- NULL
  d <- tryCatch(.rmd_read_hosted(b), error = function(e) {
    why <<- e
    NULL
  })
  if (is.null(why)) return(d)
  if (inherits(why, "rmd_damage")) {
    .rmd_drop(dest, .Call(C_morie_core_sha256, b))
    stop(sprintf(paste0("the table %s did not parse (%s); ",
                        "the damaged copy was removed, try again"),
                 key, conditionMessage(why)), call. = FALSE)
  }
  stop(sprintf("the table %s could not be read (%s); the copy was left in place",
               key, conditionMessage(why)), call. = FALSE)
}

# The file a hosted table is cached in, one per key and the same on a file system that
# ignores case: the key with "_" written "__", "/" written "_-", and each upper-case
# letter written "_" and the letter in lower case, so no two keys share a name and no
# name holds an upper-case letter. They are kept in a folder of their own: earlier
# versions cached "a__b/c" and "a/b__c" both as a__b__c.csv.gz beside the manifest,
# and a file named that way is never read now (such a table is fetched again once).
.rmd_host_file <- function(key) {
  n <- gsub("/", "_-", gsub("_", "__", key, fixed = TRUE), fixed = TRUE)
  n <- .rmd_lower(gsub("([A-Z])", "_\\1", n, perl = TRUE))
  file.path(.rmd_mkdir(file.path(.rmd_data_cache_dir(), "tables")), paste0(n, ".csv.gz"))
}

# Deletes the file `f` (and the files `also`) only while its SHA-256 is still `sha`, the
# digest of bytes proven bad: a copy written over it since is not touched.
.rmd_drop <- function(f, sha, also = character()) {
  same <- identical(.rmd_digest(f), sha)
  if (same) unlink(c(f, also))
  invisible(same)
}

# A hosted table's csv.gz as the file holds it, the way the bundled tables are read:
# - column names as written (check.names = FALSE), a byte-order mark before the
#   first one dropped;
# - every field read as text first; an empty field is missing in a logical or number
#   column and "" in a text column (the text "NA" is a value);
# - a column takes a type only when every non-empty value in it is written the way
#   R writes that value: TRUE/FALSE for logical; a whole number in the integer range,
#   without a leading zero or a plus sign, for integer; for double, a number without
#   a leading zero, whole of at most 15 digits or decimal of at most 17 significant
#   digits (trailing zeros after the point are formatting: "6.0" is 6), or one in R's
#   own exponent form such as 1e-05. Anything else keeps the column as text, so
#   "046", "+3", ".5", "0x1A", "Inf" and a 17-digit identifier keep every character.
#   A column with no value at all is logical NA, as read.csv() gives;
# - text that is valid UTF-8 is marked UTF-8, whatever the session's locale; other
#   bytes are marked "bytes";
# - a record with more or fewer fields than the header is an error.
.rmd_read_hosted <- function(b) {
  # the bytes that were checked (a path is read once, for the tests)
  if (!is.raw(b)) b <- .rmd_bytes(b)
  con <- .rmd_textcon(b)
  nf <- tryCatch(utils::count.fields(con, sep = ",", quote = "\"", comment.char = "",
                                     blank.lines.skip = TRUE), finally = close(con))
  nf <- nf[!is.na(nf)]
  bad <- which(nf != nf[1L])
  if (length(bad)) {
    .rmd_damage(sprintf("record %d has %d fields, the header %d", bad[[1L]],
                        nf[[bad[[1L]]]], nf[[1L]]))
  }
  d <- .rmd_csv_bytes(b, colClasses = "character", na.strings = character(),
                       check.names = FALSE, stringsAsFactors = FALSE, encoding = "UTF-8",
                       fill = FALSE, comment.char = "", strip.white = FALSE,
                       row.names = NULL)
  nm <- names(d)
  if (length(nm)) {
    b <- charToRaw(nm[[1L]])
    if (length(b) >= 3L && identical(b[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) {
      nm[[1L]] <- rawToChar(b[-(1:3)])
    }
    names(d) <- .rmd_mark_utf8(nm)
  }
  d[] <- lapply(d, function(x) {
    e <- !nzchar(x)
    y <- .rmd_settle(replace(x, e, NA_character_))
    # a text column is as written: an empty field in it is "", not missing
    if (is.character(y)) y[e] <- ""
    y
  })
  rownames(d) <- NULL
  d
}

# One text column as its type (see .rmd_read_hosted()).
.rmd_settle <- function(x) {
  v <- x[!is.na(x)]
  if (!length(v) || all(v %in% c("TRUE", "FALSE"))) return(as.logical(x))
  whole <- grepl("^(0|-?[1-9][0-9]*)$", v, useBytes = TRUE)
  if (all(whole) && all(nchar(v) <= 11L)) {
    n <- .rmd_num(v)
    if (all(abs(n) <= .Machine$integer.max)) return(as.integer(x))
  }
  if (all(.rmd_canon_num(v))) return(.rmd_num(x))
  .rmd_mark_utf8(x)
}

# Whether each string is a finite number written as a number is written: decimal
# notation with no leading zero, a whole number of at most 15 digits (exact in a
# double) or a decimal of at most 17 significant digits (a double printed in full;
# trailing zeros after the point are formatting: NOAA and others write a fixed
# number of decimals, "6.0"), or R's own exponent form (as.character(1e-05) is
# "1e-05"). A code such as "046" is not a number here.
.rmd_canon_num <- function(v) {
  dec <- grepl("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$", v, useBytes = TRUE) & v != "-0"
  pt <- grepl(".", v, fixed = TRUE, useBytes = TRUE)
  core <- ifelse(pt, sub("\\.?0+$", "", v, useBytes = TRUE), v)
  sig <- nchar(sub("^0+", "", gsub("[^0-9]", "", core, useBytes = TRUE), useBytes = TRUE),
               type = "bytes")
  n <- .rmd_num(v)
  # a whole number of more than 15 digits is an identifier a double cannot hold;
  # a decimal of up to 17 is a double printed in full (as Python and JSON print them)
  ok <- dec & sig <= ifelse(pt, 17L, 15L) & !is.na(n) & (n == 0 | abs(n) >= 1e-300)
  ex <- !ok & grepl("e", v, fixed = TRUE, useBytes = TRUE) & !is.na(n) & is.finite(n)
  ok[ex] <- .rmd_rtxt(n[ex]) == v[ex]
  ok
}

# as.character() of numbers as it is under the default options: R's own form, which
# options(scipen = ) changes ("1e-05" was a number at scipen 0 and text at 100).
.rmd_rtxt <- function(x) {
  op <- options(scipen = 0L, OutDec = ".")
  on.exit(options(op))
  as.character(x)
}

# Text marked UTF-8 where it is valid UTF-8, and "bytes" where it is not.
.rmd_mark_utf8 <- function(x) {
  ok <- is.na(x) | validUTF8(x)
  Encoding(x[ok]) <- "UTF-8"
  Encoding(x[!ok]) <- "bytes"
  x
}

`%||%` <- function(a, b) if (is.null(a)) b else a
