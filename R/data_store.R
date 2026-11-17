# Data store: one CSV per table under inst/extdata, a catalog and a
# column schema beside them.
#
# Every table ships once, as a CSV.
# mdload() reads that CSV and applies the column names and
# classes recorded in `_schema.csv`, so the result is typed the way the
# retired parquet copies were, and it keeps the result in a session cache
# so repeated loads cost nothing. Dictionaries are the JSON files the
# catalog points at.

.rmoriedata_cache <- new.env(parent = emptyenv())

.rmoriedata_extdata <- function() {
  p <- getOption("rmoriedata.store", NULL)
  if (!is.null(p) && !(is.character(p) && length(p) == 1L && !is.na(p))) {
    stop("rmoriedata data store not found: options(rmoriedata.store = ) ",
         "must be the path of one folder (a string).", call. = FALSE)
  }
  if (is.null(p)) p <- system.file("extdata", package = "rmoriedata")
  if (!nzchar(p) || !dir.exists(p)) {
    stop("rmoriedata data store not found; reinstall rmoriedata.",
         call. = FALSE)
  }
  # everything in .rmoriedata_cache (the manifest, the catalog, the schema, the
  # tables) belongs to one store: another store empties it, or a table read from the
  # first was served for the second
  id <- normalizePath(p, winslash = "/", mustWork = FALSE)
  if (!identical(.rmoriedata_cache[["_store"]], id)) {
    .rmoriedata_reset_cache()
    assign("_store", id, envir = .rmoriedata_cache)
  }
  p
}

# options(check.bounds = FALSE) for the rest of the call that runs this, as the Parquet
# reader and writer set it (the old value is restored when that call returns). Under
# check.bounds = TRUE R warns whenever a vector, list or data frame grows, which base
# R's own `$<-` for data frames and loadNamespace() do, and so did the package's code:
# under warn = 2 a valid hosted table was called damaged and deleted. Every exported
# function runs it first.
.rmd_bounds <- function(env = parent.frame()) {
  op <- options(check.bounds = FALSE)
  # first among the call's exit handlers, so that options set before it, by whatever
  # called it, are restored after it, in the reverse order they were set
  do.call(on.exit, list(call("options", op), add = TRUE, after = FALSE), envir = env)
  invisible(op)
}

# What the session cache holds for `name`, for the store in use now.
.rmd_cached <- function(name) {
  .rmoriedata_extdata()
  .rmoriedata_cache[[name]]
}

.rmoriedata_csv <- function(name, colClasses = NA) {
  f <- file.path(.rmoriedata_extdata(), name)
  if (!file.exists(f)) return(NULL)
  # encoding =, not fileEncoding =: fileEncoding re-encodes through the
  # session locale, and in a C locale every non-ASCII byte truncates the
  # field (22 of 99 tables short, 5 empty, 2026-09-18). encoding = marks
  # the strings as UTF-8 and leaves the bytes alone. The store has no BOM.
  .rmd_csv_bytes(.rmoriedata_bytes(name), check.names = FALSE,
                 stringsAsFactors = FALSE, encoding = "UTF-8", colClasses = colClasses)
}

# The bytes of the file `f`, read once (src/readfile.c), or a string saying why
# they cannot be: it is missing, is not a regular file, is larger than `max` bytes,
# or was replaced while it was read. Every file the package checks against a digest
# and then reads is read here, once, and the digest and the reader both take these
# bytes: checked by path and opened again to be read, a file replaced between the
# two was read unchecked. A path that is a FIFO, a directory or a device is refused
# before it is opened (a FIFO blocked the reader for ever).
.rmd_bytes <- function(f, max = Inf) .Call(C_rmd_readfile, f, as.numeric(max))

# The SHA-256 of a file's bytes (lower-case hex), or NA when they cannot be read or
# there are more than `max` of them: taken as the file is read through once, never
# held whole (the cache of chiload(full = TRUE) is digested as it is written).
.rmd_digest <- function(f, max = Inf) {
  v <- .rmd_vopen(f, fail = FALSE, max = max, blocks = FALSE)
  if (!is.list(v)) return(NA_character_)
  .rmd_vclose(v)
  v$sha256
}

# A file opened once (src/readfile.c) and read a range at a time, never held whole.
# With `verify` it is read through once first, its SHA-256 kept in `$sha256`, and (with
# `blocks`) every range read later is checked against the digests of the blocks it
# covers, so what is parsed is what was hashed. A file over `max` bytes is not opened.
# When it cannot be opened: an error naming the file, or with `fail = FALSE` the
# reason, a string. Closed by .rmd_vclose().
.rmd_vopen <- function(f, verify = TRUE, fail = TRUE, max = Inf, blocks = verify) {
  mode <- if (!verify) 0L else if (blocks) 2L else 1L
  v <- .Call(C_rmd_vopen, f, mode, as.numeric(max))
  if (is.list(v)) return(structure(v, class = "rmd_vfile"))
  if (!fail) return(v)
  stop(basename(f), " ", v, call. = FALSE)
}

.rmd_vclose <- function(v) invisible(.Call(C_rmd_vclose, v$handle))

# An error that proves a file's bytes bad: they do not match the digest they are
# checked against, a gzip member in them is damaged, or a record has more or fewer
# fields than the header. Only such an error lets the package delete a cached or
# downloaded copy. Running out of memory, an interrupt, a read that failed, a file
# replaced while it was read, a session option, or any other error proves nothing
# about the file, and the file stays.
.rmd_damage <- function(...) {
  stop(errorCondition(paste0(...), class = "rmd_damage", call = NULL))
}

# The text of gzip bytes (src/gzip.c): every member inflated, and NUL bytes after the
# last one ignored, as gzip -d ignores them. Anything else after the last member is
# refused, naming it: it is part of no member, so it is neither text of the file nor
# to be dropped unseen (read through gzcon(), padding made a valid table "damaged",
# and text after it became a row). A damaged member is damage (.rmd_damage()); bytes
# after the members are not, and keep the file.
.rmd_gunzip <- function(b) {
  x <- .Call(C_rmd_gunzip, b)
  if (is.raw(x)) return(x)
  if (x[[1L]] == "damage") .rmd_damage(x[[2L]])
  stop(x[[2L]], call. = FALSE)
}

# A text-mode connection over bytes, plain or gzip: read.csv() and count.fields() push
# lines back, which only a text-mode connection allows. The text (inflated by
# .rmd_gunzip()) that is valid UTF-8, without a NUL byte and under 2^31 bytes (every
# store file) is one string, left unmarked so that its bytes pass as they are in any
# locale, read through a text connection: the fastest way (readLines() of a raw
# connection took half again the time of reading the file). Other text goes through
# gzcon(text = TRUE) (a text connection stops at a byte 0xff), which drops a last line
# that has no newline: one is added, and the blank line it can make is skipped by the
# readers. gzcon() passes bytes through as they are unless they start as gzip does;
# text that does is handed to it as one stored gzip member, or it was inflated twice.
.rmd_textcon <- function(b) {
  x <- if (.rmd_gz(b)) .rmd_gunzip(b) else b
  s <- if (length(x) < 2^31 - 1 && !length(grepRaw(as.raw(0L), x, fixed = TRUE))) {
    rawToChar(x)
  }
  if (!is.null(s) && validUTF8(s)) return(textConnection(s))
  y <- c(x, as.raw(10L))
  if (.rmd_gz(y)) y <- .Call(C_rmd_gzip_store, y)
  gzcon(rawConnection(y), text = TRUE)
}

# Whether bytes start as gzip does.
.rmd_gz <- function(b) {
  length(b) >= 2L && b[[1L]] == as.raw(0x1f) && b[[2L]] == as.raw(0x8b)
}

# read.csv() of bytes, as of the file they were read from.
.rmd_csv_bytes <- function(b, ...) {
  con <- .rmd_textcon(b)
  on.exit(close(con))
  utils::read.csv(con, ...)
}

# The lines of bytes, plain or gzip, as readLines() reads them from the file, a last
# line without its newline included; a NUL byte, which no R string holds, is dropped.
.rmd_lines <- function(b) {
  con <- rawConnection(if (.rmd_gz(b)) .rmd_gunzip(b) else b)
  on.exit(close(con))
  readLines(con, warn = FALSE, skipNul = TRUE, encoding = "UTF-8")
}

# Numbers as text, the same whatever options(scipen, OutDec, digits) say: as
# R writes them by default (15 significant digits), and in 17 where 15 do not read
# back as the same double. Whole numbers are written in full: as.character(1e5) is
# "1e+05", and under options(scipen = -5) as.character(3) is "3e+00".
.rmd_ntxt <- function(x) {
  x <- as.numeric(x)
  s <- sprintf("%.15g", x)
  far <- !is.na(x) & is.finite(x) & .rmd_num(s) != x
  s[far] <- sprintf("%.17g", x[far])
  s[is.na(x) & !is.nan(x)] <- NA_character_
  s
}

# A column as text: a double through .rmd_ntxt(), anything else by as.character().
.rmd_text <- function(x) {
  if (is.double(x) && !is.object(x)) .rmd_ntxt(x) else as.character(x)
}

# Text compared without regard to ASCII case, the same in every locale: tolower()
# follows the locale, and in Turkish "I" is lowered to a dotless "i" (U+0131), so
# "INJURY" did not match "injury". Other letters are left as they are.
.rmd_lower <- function(x) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
}

# Decimal text as doubles, the same on every platform (src/strtod.c): R's own
# conversion, behind read.csv(), as.numeric(), type.convert() and scan(), is not
# correctly rounded and gives a different last bit on x86-64 and on ARM64 for some
# text ("1.239042694"). The C library's strtod() is correctly rounded. A string that
# is not a plain decimal or exponent number is NA; with `special`, "Inf", "-Inf" and
# "NaN" are read as write.csv() writes them.
.rmd_num <- function(x, special = FALSE) {
  out <- .Call(C_rmd_strtod, as.character(x))
  if (special) {
    out[x %in% "Inf"] <- Inf
    out[x %in% "-Inf"] <- -Inf
    out[x %in% "NaN"] <- NaN
  }
  out
}

.rmoriedata_schema <- function() {
  s <- .rmd_cached("_schema")
  if (is.null(s)) {
    s <- .rmoriedata_csv("_schema.csv")
    if (is.null(s)) {
      stop("rmoriedata schema not found; reinstall rmoriedata.", call. = FALSE)
    }
    assign("_schema", s, envir = .rmoriedata_cache)
  }
  s
}

#' Catalog of the bundled datasets
#'
#' One row per bundled table or dictionary: `slug`, `source_path`
#' (relative to the package's `extdata` directory), `kind`, and for
#' tables `n_rows`, `n_cols` and `parquet_path` (the same table as a
#' Parquet file, see [mdpath()]).
#'
#' @return A data frame: `slug`, `source_path`, `kind` (table, dictionary, ...),
#'   `n_rows`, `n_cols`, `parquet_path`, and `synthetic`, TRUE for the tables that are
#'   generated stand-ins with the published schema rather than published data (the
#'   ARSAU use-of-force tables and the `*_synthetic` ones).
#' @examples
#' cat <- mdcat()
#' cat$slug[cat$synthetic]
#' tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
#' head(tbls[order(-tbls$n_rows), ])
#' @export
mdcat <- function() {
  .rmd_bounds()
  cat <- .rmd_cached("_catalog")
  if (is.null(cat)) {
    cat <- .rmoriedata_csv("_catalog.csv")
    if (is.null(cat)) {
      stop("rmoriedata catalog not found; reinstall rmoriedata.",
           call. = FALSE)
    }
    cat$n_rows <- as.integer(cat$n_rows)
    cat$n_cols <- as.integer(cat$n_cols)
    if (!is.null(cat$synthetic)) cat$synthetic <- as.logical(cat$synthetic)
    assign("_catalog", cat, envir = .rmoriedata_cache)
  }
  cat
}

#' Load a bundled dataset by slug
#'
#' Reads the table's CSV and applies the column names and classes from
#' the bundled schema, so the result is the same typed data frame on
#' every platform regardless of how `read.csv()` would have guessed.
#' Every table also ships as a Parquet file holding the same typed
#' frame; `format = "parquet"` reads that copy instead. The first load
#' of a table is cached for the session; later calls return the cached
#' copy unless `refresh = TRUE`. The cached copy is what the file held when
#' it was checked; when [mdverify()] finds the file changed since, the
#' cached copy is dropped, and the next load reads the file again and
#' refuses it.
#'
#' @param slug Dataset slug; see the `slug` column of [mdcat()].
#' @param refresh Re-read the file, and check it against the signed manifest
#'   again, even if a cached copy exists.
#' @param format `"csv"` (default) or `"parquet"`: which shipped copy to
#'   read. Both give the same data frame, value for value: decimal text in
#'   the CSV is read as the nearest double, the same on every platform.
#' @return A data frame.
#' @examples
#' d <- mdload("arsau_2023_uof_main_records")
#' str(d[, 1:4])
#' @export
mdload <- function(slug, refresh = FALSE,
                            format = c("csv", "parquet")) {
  .rmd_bounds()
  if (!is.character(slug) || length(slug) != 1L || is.na(slug)) {
    stop("`slug` must be a single dataset slug (character). ",
         "See mdcat() for valid slugs.", call. = FALSE)
  }
  .rmd_nobytes(slug, "slug")
  # no slug is this long, and R cannot keep a name of 10,000 bytes
  if (nchar(slug, "bytes") > 200L) {
    stop(sprintf("No dataset '%s...'. See mdcat() for valid slugs.",
                 substr(slug, 1L, 40L)), call. = FALSE)
  }
  if (!is.logical(refresh) || length(refresh) != 1L || is.na(refresh)) {
    stop("`refresh` must be TRUE or FALSE.", call. = FALSE)
  }
  format <- .rmd_arg(format, "format")
  key <- paste0("table:", format, ":", slug)
  if (!isTRUE(refresh)) {
    hit <- .rmd_cached(key)
    if (!is.null(hit)) return(hit)
  }
  cat <- mdcat()
  row <- cat[cat$slug == slug & cat$kind == "table", , drop = FALSE]
  if (!nrow(row)) {
    if (any(cat$slug == slug & cat$kind == "dictionary")) {
      stop(sprintf(paste0("'%s' is a data dictionary, not a table: load it ",
                          "with mddict(\"%s\")."), slug, slug),
           call. = FALSE)
    }
    stop(sprintf("No dataset '%s'. See mdcat() for valid slugs.",
                 slug), call. = FALSE)
  }
  if (format == "parquet") {
    rel <- row$parquet_path[1L]
    f <- file.path(.rmoriedata_extdata(), rel)
    if (is.na(rel) || !nzchar(rel) || !file.exists(f)) {
      stop(sprintf("The Parquet file for '%s' is missing; reinstall rmoriedata.",
                   slug), call. = FALSE)
    }
    # the bytes that were checked are the bytes that are read
    d <- as.data.frame(morie_read_parquet(.rmoriedata_bytes(rel)),
                       stringsAsFactors = FALSE)
  } else {
    # the double columns are read as text and converted here, correctly rounded
    s <- .rmoriedata_schema()
    s <- s[s$slug == slug, , drop = FALSE]
    cc <- NA
    if (nrow(s)) cc <- ifelse(s$class[order(s$position)] == "numeric", "character", NA)
    d <- .rmoriedata_csv(row$source_path[1L], colClasses = cc)
    if (is.null(d)) {
      stop(sprintf("The file for '%s' (%s) is missing; reinstall rmoriedata.",
                   slug, row$source_path[1L]), call. = FALSE)
    }
    d <- .rmoriedata_apply_schema(d, slug)
  }
  assign(key, d, envir = .rmoriedata_cache)
  d
}

#' Path of a bundled table's shipped file
#'
#' The absolute path of the CSV or Parquet copy of a table, verified
#' against the signed manifest first. The Parquet path is the bridge to
#' Python: `pandas.read_parquet(path)` gives the same typed table
#' [mdload()] returns.
#'
#' Every call checks the file again: its SHA-256 is computed and compared
#' with the manifest's (the store's files are small; the largest takes a few
#' tens of milliseconds), so a file changed since an earlier call is refused,
#' whatever else about it stayed the same. What is not covered: a change
#' made after the path is returned, before it is read. [mdload()] has no such
#' gap: it reads a file's bytes once, checks them and reads the table from them.
#'
#' @param slug Dataset slug; see the `slug` column of [mdcat()].
#' @param format `"parquet"` (default) or `"csv"`. A dictionary or other non-table
#'   slug has one file, which is returned either way.
#' @return A length-1 character path.
#' @examples
#' p <- mdpath("arsau_2023_uof_main_records")
#' file.exists(p)
#' basename(mdpath("arsau_2023_uof_main_records", "csv"))
#' @export
mdpath <- function(slug, format = c("parquet", "csv")) {
  .rmd_bounds()
  format <- .rmd_arg(format, "format")
  if (!is.character(slug) || length(slug) != 1L || is.na(slug)) {
    stop("`slug` must be a single dataset slug (character). ",
         "See mdcat() for valid slugs.", call. = FALSE)
  }
  .rmd_nobytes(slug, "slug")
  cat <- mdcat()
  row <- cat[cat$slug == slug, , drop = FALSE]
  if (!nrow(row)) {
    stop(sprintf("No dataset '%s'. See mdcat() for valid slugs.",
                 slug), call. = FALSE)
  }
  # a dictionary or document is its one file; only a table has a parquet copy
  table <- row$kind[1L] == "table"
  rel <- if (format == "parquet" && table) row$parquet_path[1L] else row$source_path[1L]
  f <- file.path(.rmoriedata_extdata(), rel)
  if (is.na(rel) || !nzchar(rel) || !file.exists(f)) {
    stop(sprintf("The %s file for '%s' is missing; reinstall rmoriedata.",
                 format, slug), call. = FALSE)
  }
  .rmoriedata_bytes(rel)
  normalizePath(f, winslash = "/")
}

# Column names and classes come from the schema, by position: the CSV
# header may carry a byte-order mark or characters make.names() would
# mangle, and an all-NA column reads as logical where the table's type
# is integer.
.rmoriedata_apply_schema <- function(d, slug) {
  s <- .rmoriedata_schema()
  s <- s[s$slug == slug, , drop = FALSE]
  if (!nrow(s)) return(d)
  s <- s[order(s$position), , drop = FALSE]
  if (nrow(s) != ncol(d)) {
    stop(sprintf("schema for '%s' has %d columns but the file has %d",
                 slug, nrow(s), ncol(d)), call. = FALSE)
  }
  names(d) <- s$name
  for (j in seq_len(ncol(d))) {
    cls <- s$class[j]
    v <- d[[j]]
    d[[j]] <- switch(cls,
      integer = as.integer(v),
      numeric = if (is.character(v)) .rmd_num(v, special = TRUE) else as.numeric(v),
      logical = as.logical(v),
      character = if (is.character(v)) v else .rmd_text(v),
      Date = as.Date(v),
      v)
  }
  rownames(d) <- NULL
  d
}

#' Data dictionary for a bundled dataset
#'
#' @param slug Dictionary slug; rows with `kind == "dictionary"` in
#'   [mdcat()] list them.
#' @return The dictionary as JSON text (a length-one character vector),
#'   or `NULL` invisibly with a message when none is bundled.
#' @examples
#' d <- mddict("arsau_2023_dictionary")
#' substr(d, 1, 60)
#' @export
mddict <- function(slug) {
  .rmd_bounds()
  if (!is.character(slug) || length(slug) != 1L || is.na(slug) || !nzchar(slug)) {
    stop("`slug` must be a single name from mdcat().", call. = FALSE)
  }
  .rmd_nobytes(slug, "slug")
  cat <- mdcat()
  row <- cat[cat$slug == slug & cat$kind == "dictionary", , drop = FALSE]
  if (!nrow(row)) {
    message("No dictionary bundled for '", slug,
            "'. Rows with kind == \"dictionary\" in mdcat() ",
            "list the ones available.")
    return(invisible(NULL))
  }
  f <- file.path(.rmoriedata_extdata(), row$source_path[1L])
  if (!file.exists(f)) {
    message("No data dictionaries are bundled in this installation.")
    return(invisible(NULL))
  }
  paste(.rmd_lines(.rmoriedata_bytes(row$source_path[1L])), collapse = "\n")
}

# Integrity. Every shipped file is listed with its SHA-256 in
# `_checksums.csv`; the SHA-256 of that manifest is signed with an XMSS
# (RFC 8391, SHA-256) key whose public half ships as `_signing_key.json`.
# The signature is checked once per session and each file every time it is
# read, so a modified or corrupted install fails loudly instead of
# returning altered data. data-raw/sign_store.R produces the three files.

.rmoriedata_json <- function(name, class) {
  f <- file.path(.rmoriedata_extdata(), name)
  if (!file.exists(f)) {
    stop("rmoriedata's ", name, " is missing; reinstall rmoriedata.",
         call. = FALSE)
  }
  txt <- paste(.rmd_lines(.rmoriedata_trust_bytes(f, name)), collapse = "\n")
  out <- .rmd_bl("fromjs")(txt)
  class(out) <- c(class, "list")
  out
}

.rmoriedata_manifest <- function() {
  m <- .rmd_cached("_manifest")
  if (!is.null(m)) {
    return(m)
  }
  f <- file.path(.rmoriedata_extdata(), "_checksums.csv")
  if (!file.exists(f)) {
    stop("rmoriedata's checksum manifest is missing; reinstall rmoriedata.",
         call. = FALSE)
  }
  # read once: the bytes whose signature is checked are the manifest that is read
  bytes <- .rmoriedata_trust_bytes(f, "checksum manifest")
  sig <- .rmoriedata_json("_checksums.sig", "bricklayer_signature")
  pub <- .rmoriedata_json("_signing_key.json", "bricklayer_public_key")
  # The trust root is pinned here, not read from the same directory the
  # signature protects: a consistent re-sign of extdata with another key
  # would otherwise verify. Changing the signing key means changing this
  # constant in package code, which is the visible change it should be.
  root_ok <- identical(as.character(pub$root), .rmoriedata_signing_root)
  # the public seed is named pubseed by rmoriebricklayer 1.1.1 and pub_seed
  # by the versions before it
  seed <- if (is.null(pub$pubseed)) pub$pub_seed else pub$pubseed
  seed_ok <- identical(as.character(seed), .rmoriedata_signing_seed)
  if (!root_ok || !seed_ok) {
    stop("rmoriedata's shipped signing key does not match the root pinned ",
         "in the package: the installed data store has been re-signed. ",
         "Reinstall rmoriedata.", call. = FALSE)
  }
  # hex as the signer writes it, lower case: a re-cased signature is the
  # same bytes, but not the signature that was made
  hex <- unlist(sig[c("signature", "auth", "randomizer")])
  ok <- is.character(hex) && length(hex) == 3L &&
    all(grepl("^[0-9a-f]+$", hex)) &&
    isTRUE(.rmd_bl("cpsvrf")(.rmd_bl("csha256")(bytes), sig, pub))
  if (!isTRUE(ok)) {
    stop("rmoriedata's checksum manifest does not verify against the ",
         "package's signing key: the installed data store has been ",
         "modified. Reinstall rmoriedata.", call. = FALSE)
  }
  m <- .rmd_csv_bytes(bytes, stringsAsFactors = FALSE,
                      colClasses = c("character", "numeric", "character"))
  assign("_manifest", m, envir = .rmoriedata_cache)
  m
}

# The bytes of one of the trust files (the manifest, its signature, the key), or an
# error naming it: one that is not a regular file is not read.
.rmoriedata_trust_bytes <- function(f, what) {
  b <- .rmd_bytes(f)
  if (!is.raw(b)) {
    stop("rmoriedata's ", what, " ", b, "; reinstall rmoriedata.", call. = FALSE)
  }
  b
}

# The bytes of the store file `rel`, checked against the signed manifest: read once
# (.rmd_bytes()), and what is returned is what was hashed. Every call reads and hashes
# the file: the store is small (14 MB in 210 files, the largest 2.3 MB), at most
# about 50 ms. A list of the files verified once was returned unchecked after the
# file changed in place, even after mdverify() had reported it; and a file checked
# by its path and then opened again to be read could be replaced between the two.
# A file larger than the manifest says is not read past that size.
.rmoriedata_bytes <- function(rel) {
  m <- .rmoriedata_manifest()
  row <- m[m$path == rel, , drop = FALSE]
  if (!nrow(row)) {
    stop(sprintf("'%s' is not in rmoriedata's signed manifest.", rel),
         call. = FALSE)
  }
  f <- file.path(.rmoriedata_extdata(), rel)
  if (file.exists(f) && !.rmoriedata_inside(f, .rmoriedata_extdata())) {
    stop(sprintf(paste0("rmoriedata's bundled file '%s' is a link out of ",
                        "the data store: only the store's own files are ",
                        "trusted. Reinstall rmoriedata."), rel), call. = FALSE)
  }
  b <- .rmd_bytes(f, row$bytes[1L])
  got <- if (is.raw(b)) .Call(C_morie_core_sha256, b)
  if (!identical(got, row$sha256[1L])) {
    why <- if (is.null(got)) paste("the file", b) else
      sprintf("expected sha256 %s, got %s", row$sha256[1L], got)
    stop(sprintf(paste0("rmoriedata's bundled file '%s' does not match the ",
                        "signed manifest (%s): the ",
                        "installed copy has been modified or corrupted. ",
                        "Reinstall rmoriedata."),
                 rel, why), call. = FALSE)
  }
  b
}

# Drops what the session cache built from the store files `bad`: the catalog, the
# schema (and with it every table read from a CSV, which it typed) and the tables
# read from them, so the next load reads the file again, checks it and refuses it.
.rmoriedata_forget <- function(bad) {
  if (!length(bad)) return(invisible(NULL))
  keys <- ls(.rmoriedata_cache, all.names = TRUE)
  cat <- .rmoriedata_cache[["_catalog"]]
  csv <- grep("^table:csv:", keys, value = TRUE)
  drop <- c(if ("_catalog.csv" %in% bad) "_catalog",
            if ("_schema.csv" %in% bad) c("_schema", csv),
            paste0("table:csv:", cat$slug[cat$source_path %in% bad]),
            paste0("table:parquet:", cat$slug[cat$parquet_path %in% bad]))
  rm(list = intersect(drop, keys), envir = .rmoriedata_cache)
  invisible(NULL)
}

# Whether a store file resolves inside the store: a listed file replaced by a
# link to an identical copy elsewhere verified, where rmoriebricklayer's bundle
# check refuses a link out of its directory. A link inside the store is a file
# of the store.
.rmoriedata_inside <- function(f, dir) {
  real <- normalizePath(f, winslash = "/", mustWork = FALSE)
  base <- sub("/+$", "", normalizePath(dir, winslash = "/", mustWork = FALSE))
  startsWith(real, paste0(base, "/"))
}

.rmoriedata_reset_cache <- function() {
  rm(list = ls(.rmoriedata_cache, all.names = TRUE), envir = .rmoriedata_cache)
  invisible(NULL)
}

#' Verify the bundled data store against its signed manifest
#'
#' Every file rmoriedata ships is listed with its SHA-256 in a manifest,
#' and the manifest is signed with an XMSS (RFC 8391, SHA-256) key whose
#' public half ships with the package. Loading a table checks its file
#' against the manifest; this function checks all of them at once. What the
#' session has cached from a file found changed or missing (a table loaded
#' by [mdload()], the catalog, the schema) is dropped, so the next load reads
#' the file again and refuses it.
#'
#' A file present in the installed store but absent from the manifest is
#' reported too, hidden (dot) files included, as a row with
#' `listed = FALSE` and `ok = FALSE`: a file added to the store is as much
#' a change as a file altered in it.
#'
#' What is covered: every file under the package's `extdata` directory (or
#' the directory named by `options(rmoriedata.store = )`), which holds
#' every table, dictionary, catalog and Parquet copy that [mdload()],
#' [mdpath()], [mddict()], [siuload()] and [cihitbls()] read. What is not
#' covered: the package's R code, its compiled code, and the two lazy-data
#' objects [complaint_sample] and [arrest_sample] (stored in the package's
#' `data` database, not in `extdata`); these are installed files of the
#' package itself, which `tools::checkMD5sums("rmoriedata")` checks
#' against the `MD5` file of a CRAN install.
#'
#' A listed path that holds anything but the file (it is missing, a directory, a
#' FIFO, a device, a link that loops or leaves the store, or cannot be read) is
#' a row with `ok = FALSE`; nothing at such a path is waited on.
#'
#' @return A data frame with one row per manifest entry, then one per
#'   unlisted file (in the byte order of their paths, the same in every
#'   locale): `path`, `bytes`, `sha256` (the manifest digest, or the
#'   file's own for an unlisted file: `NA` when it is not a regular file or is
#'   larger than 1 GiB), `listed`, `ok` (the file on disk is
#'   listed and matches). The attribute `"signature"` is `TRUE` when the
#'   manifest's signature verified, and the function errors if it did not.
#' @examples
#' v <- mdverify()
#' all(v$ok)
#' attr(v, "signature")
#' @export
mdverify <- function() {
  .rmd_bounds()
  m <- .rmoriedata_manifest()
  ed <- .rmoriedata_extdata()
  m$listed <- rep(TRUE, nrow(m))
  # whatever is at the path (missing, a directory, a FIFO, a device, a link that
  # loops, a file that cannot be read) is a row that is not ok, never an error or a
  # wait: a directory stopped this function, and a FIFO blocked it
  m$ok <- vapply(seq_len(nrow(m)), function(i) {
    f <- file.path(ed, m$path[i])
    file.exists(f) && .rmoriedata_inside(f, ed) &&
      identical(.rmd_digest(f, m$bytes[i]), m$sha256[i])
  }, TRUE)
  # the manifest, its signature and the public key are the trust machinery, not data
  # hidden files too: a dot-file added to the store is as much a change as any other
  present <- list.files(ed, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  trust <- c("_checksums.csv", "_checksums.sig", "_signing_key.json")
  # in C (byte) order, the same in every locale (list.files() follows the collation)
  extra <- sort(setdiff(present, c(m$path, trust)), method = "radix")
  if (length(extra)) {
    fx <- file.path(ed, extra)
    m <- rbind(m, data.frame(
      path = extra, bytes = file.size(fx),
      sha256 = vapply(fx, .rmd_digest, character(1), max = .rmd_extra_max,
                      USE.NAMES = FALSE),
      listed = FALSE, ok = FALSE, stringsAsFactors = FALSE
    )[names(m)])
  }
  .rmoriedata_forget(m$path[m$listed & !m$ok])
  attr(m, "signature") <- TRUE
  m
}

# The largest unlisted file mdverify() and mdsums() hash (1 GiB): the store's own
# files are small, and the digest of a file that is not the store's is only shown.
.rmd_extra_max <- 2^30

# XMSS public root and public seed of the store's signing key (RFC 8391,
# SHA-256). Pinned in code so the verifier's trust anchor does not travel
# with the data it verifies.
.rmoriedata_signing_root <- paste0("bee8b88de2e19b5bafa398f1ccc0d48d",
                                   "a5ee75e561e6b39d06f5e8b2421bd23d")
.rmoriedata_signing_seed <- paste0("9e5d6ac1acea1d247139755cd3956889",
                                   "0c894c113b095b285be7a8b12ad9a539")
