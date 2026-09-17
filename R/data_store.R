# Data store: one CSV per table under inst/extdata, a catalog and a
# column schema beside them.
#
# Every table ships once, as the CSV that rmorie reads by file name.
# morie_data_load() reads that CSV and applies the column names and
# classes recorded in `_schema.csv`, so the result is typed the way the
# retired parquet copies were, and it keeps the result in a session cache
# so repeated loads cost nothing. Dictionaries are the JSON files the
# catalog points at.

.rmoriedata_cache <- new.env(parent = emptyenv())

.rmoriedata_extdata <- function() {
  p <- getOption("rmoriedata.store", NULL)
  if (is.null(p)) p <- system.file("extdata", package = "rmoriedata")
  if (!nzchar(p) || !dir.exists(p)) {
    stop("rmoriedata data store not found; reinstall rmoriedata.",
         call. = FALSE)
  }
  p
}

.rmoriedata_csv <- function(name) {
  f <- file.path(.rmoriedata_extdata(), name)
  if (!file.exists(f)) return(NULL)
  .rmoriedata_check_file(name)
  utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE,
                  fileEncoding = "UTF-8-BOM")
}

.rmoriedata_schema <- function() {
  s <- .rmoriedata_cache[["_schema"]]
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
#' tables `n_rows` and `n_cols`.
#'
#' @return A data frame.
#' @examples
#' cat <- morie_data_catalog()
#' tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
#' head(tbls[order(-tbls$n_rows), ])
#' @export
morie_data_catalog <- function() {
  cat <- .rmoriedata_cache[["_catalog"]]
  if (is.null(cat)) {
    cat <- .rmoriedata_csv("_catalog.csv")
    if (is.null(cat)) {
      stop("rmoriedata catalog not found; reinstall rmoriedata.",
           call. = FALSE)
    }
    cat$n_rows <- as.integer(cat$n_rows)
    cat$n_cols <- as.integer(cat$n_cols)
    assign("_catalog", cat, envir = .rmoriedata_cache)
  }
  cat
}

#' Load a bundled dataset by slug
#'
#' Reads the table's CSV and applies the column names and classes from
#' the bundled schema, so the result is the same typed data frame on
#' every platform regardless of how `read.csv()` would have guessed.
#' The first load of a table is cached for the session; later calls
#' return the cached copy unless `refresh = TRUE`.
#'
#' @param slug Dataset slug; see the `slug` column of [morie_data_catalog()].
#' @param refresh Re-read the file even if a cached copy exists.
#' @return A data frame.
#' @examples
#' d <- morie_data_load("arsau_2023_uof_main_records")
#' str(d[, 1:4])
#' @export
morie_data_load <- function(slug, refresh = FALSE) {
  if (is.null(slug) || length(slug) != 1L || is.na(slug) ||
      !is.character(slug)) {
    stop("`slug` must be a single dataset slug (character). ",
         "See morie_data_catalog() for valid slugs.", call. = FALSE)
  }
  key <- paste0("table:", slug)
  if (!isTRUE(refresh)) {
    hit <- .rmoriedata_cache[[key]]
    if (!is.null(hit)) return(hit)
  }
  cat <- morie_data_catalog()
  row <- cat[cat$slug == slug & cat$kind == "table", , drop = FALSE]
  if (!nrow(row)) {
    stop(sprintf("No dataset '%s'. See morie_data_catalog() for valid slugs.",
                 slug), call. = FALSE)
  }
  d <- .rmoriedata_csv(row$source_path[1L])
  if (is.null(d)) {
    stop(sprintf("The file for '%s' (%s) is missing; reinstall rmoriedata.",
                 slug, row$source_path[1L]), call. = FALSE)
  }
  d <- .rmoriedata_apply_schema(d, slug)
  assign(key, d, envir = .rmoriedata_cache)
  d
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
      numeric = as.numeric(v),
      logical = as.logical(v),
      character = if (is.character(v)) v else as.character(v),
      Date = as.Date(v),
      v)
  }
  rownames(d) <- NULL
  d
}

#' Data dictionary for a bundled dataset
#'
#' @param slug Dictionary slug; rows with `kind == "dictionary"` in
#'   [morie_data_catalog()] list them.
#' @return The dictionary as JSON text (a length-one character vector),
#'   or `NULL` invisibly with a message when none is bundled.
#' @examples
#' d <- morie_data_dictionary("arsau_2023_dictionary")
#' substr(d, 1, 60)
#' @export
morie_data_dictionary <- function(slug) {
  cat <- morie_data_catalog()
  row <- cat[cat$slug == slug & cat$kind == "dictionary", , drop = FALSE]
  if (!nrow(row)) {
    message("No dictionary bundled for '", slug,
            "'. Rows with kind == \"dictionary\" in morie_data_catalog() ",
            "list the ones available.")
    return(invisible(NULL))
  }
  f <- file.path(.rmoriedata_extdata(), row$source_path[1L])
  if (!file.exists(f)) {
    message("No data dictionaries are bundled in this installation.")
    return(invisible(NULL))
  }
  .rmoriedata_check_file(row$source_path[1L])
  txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
  paste(txt, collapse = "\n")
}

# Integrity. Every shipped file is listed with its SHA-256 in
# `_checksums.csv`; the SHA-256 of that manifest is signed with an XMSS
# (RFC 8391, SHA-256) key whose public half ships as `_signing_key.json`.
# The signature is checked once per session and each file when it is
# first read, so a modified or corrupted install fails loudly instead of
# returning altered data. data-raw/sign_store.R produces the three files.

.rmoriedata_json <- function(name, class) {
  f <- file.path(.rmoriedata_extdata(), name)
  if (!file.exists(f)) {
    stop("rmoriedata's ", name, " is missing; reinstall rmoriedata.",
         call. = FALSE)
  }
  txt <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  out <- rmoriebricklayer::bricklayer_json_from_json(txt)
  class(out) <- c(class, "list")
  out
}

.rmoriedata_manifest <- function() {
  m <- .rmoriedata_cache[["_manifest"]]
  if (!is.null(m)) {
    return(m)
  }
  f <- file.path(.rmoriedata_extdata(), "_checksums.csv")
  if (!file.exists(f)) {
    stop("rmoriedata's checksum manifest is missing; reinstall rmoriedata.",
         call. = FALSE)
  }
  bytes <- readBin(f, "raw", n = file.size(f))
  sig <- .rmoriedata_json("_checksums.sig", "bricklayer_signature")
  pub <- .rmoriedata_json("_signing_key.json", "bricklayer_public_key")
  ok <- rmoriebricklayer::capsule_verify(rmoriebricklayer::core_sha256(bytes),
                                         sig, pub)
  if (!isTRUE(ok)) {
    stop("rmoriedata's checksum manifest does not verify against the ",
         "package's signing key: the installed data store has been ",
         "modified. Reinstall rmoriedata.", call. = FALSE)
  }
  m <- utils::read.csv(f, stringsAsFactors = FALSE,
                       colClasses = c("character", "numeric", "character"))
  assign("_manifest", m, envir = .rmoriedata_cache)
  assign("_verified", character(0), envir = .rmoriedata_cache)
  m
}

.rmoriedata_check_file <- function(rel) {
  if (rel %in% .rmoriedata_cache[["_verified"]]) {
    return(invisible(TRUE))
  }
  m <- .rmoriedata_manifest()
  row <- m[m$path == rel, , drop = FALSE]
  if (!nrow(row)) {
    stop(sprintf("'%s' is not in rmoriedata's signed manifest.", rel),
         call. = FALSE)
  }
  got <- rmoriebricklayer::sha256_file(file.path(.rmoriedata_extdata(), rel))
  if (!identical(got, row$sha256[1L])) {
    stop(sprintf(paste0("rmoriedata's bundled file '%s' does not match the ",
                        "signed manifest (expected sha256 %s, got %s): the ",
                        "installed copy has been modified or corrupted. ",
                        "Reinstall rmoriedata."),
                 rel, row$sha256[1L], got), call. = FALSE)
  }
  assign("_verified", c(.rmoriedata_cache[["_verified"]], rel),
         envir = .rmoriedata_cache)
  invisible(TRUE)
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
#' against the manifest; this function checks all of them at once.
#'
#' @return A data frame with one row per manifest entry: `path`, `bytes`,
#'   `sha256`, `ok` (the file on disk matches). The attribute
#'   `"signature"` is `TRUE` when the manifest's signature verified, and
#'   the function errors if it did not.
#' @examples
#' v <- morie_data_verify()
#' all(v$ok)
#' attr(v, "signature")
#' @export
morie_data_verify <- function() {
  m <- .rmoriedata_manifest()
  ed <- .rmoriedata_extdata()
  m$ok <- vapply(seq_len(nrow(m)), function(i) {
    f <- file.path(ed, m$path[i])
    file.exists(f) &&
      identical(rmoriebricklayer::sha256_file(f), m$sha256[i])
  }, TRUE)
  attr(m, "signature") <- TRUE
  m
}
