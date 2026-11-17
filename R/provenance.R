# SPDX-License-Identifier: AGPL-3.0-or-later

#' SHA256 checksums of bundled rmoriedata files
#'
#' Computes the SHA256 digest of every file rmoriedata bundles in
#' \code{inst/extdata}, each file read once and only when it is a regular file
#' (\code{NA} for any other path, and for a file larger than 1 GiB), and compares
#' each with
#' the digest the signed manifest records for it (\code{in_manifest}).
#' For the full check, signature included, use [mdverify()]; this
#' function is the per-file record an analysis can pin and compare later.
#'
#' @return A data frame with one row per bundled file, in the byte order of
#'   \code{path} (the same in every locale), and columns
#'   \code{path} (relative to the extdata root, forward slashes, unique),
#'   \code{file} (the bare basename), \code{bytes}, \code{sha256}, and
#'   \code{in_manifest} (TRUE when the signed manifest lists the file with
#'   this digest; NA for the manifest's own files).
#'   Use \code{path} to locate a file; several basenames recur in more
#'   than one directory.
#' @examples
#' # One row per bundled file: name, size in bytes, SHA256 digest.
#' ck <- mdsums()
#' str(ck)
#' head(ck)
#'
#' # Total bundled payload and the largest few files.
#' sum(ck$bytes)
#' head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#'
#' # Provenance workflow: pin the digest of a file you depend on, then
#' # assert it hasn't changed under you in a later session / reinstall.
#' if (nrow(ck)) {
#'   pinned <- ck$sha256[1]
#'   again <- mdsums()
#'   stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
#' }
#' @export
mdsums <- function() {
  .rmd_bounds()
  # the store the manifest is read from (options(rmoriedata.store = ) or the install)
  dir <- tryCatch(.rmoriedata_extdata(), error = function(e) "")
  empty <- data.frame(
    path = character(), file = character(), bytes = numeric(),
    sha256 = character(), in_manifest = logical(), stringsAsFactors = FALSE
  )
  if (!nzchar(dir) || !dir.exists(dir)) {
    return(empty)
  }
  # in C (byte) order, the same in every locale: list.files() sorts by the session's
  # collation, and the record's rows came out in another order under LC_ALL=C
  files <- sort(list.files(dir, full.names = TRUE, recursive = TRUE, all.files = TRUE,
                           no.. = TRUE), method = "radix")
  if (length(files) == 0L) {
    return(empty)
  }
  out <- data.frame(
    path = substring(files, nchar(dir) + 2L),
    file = basename(files),
    bytes = file.size(files),
    # read once each, a regular file only (a FIFO blocked this): NA otherwise
    sha256 = vapply(files, .rmd_digest, character(1), max = .rmd_extra_max),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
  man <- tryCatch(.rmoriedata_manifest(), error = function(e) NULL)
  trust <- c("_checksums.csv", "_checksums.sig", "_signing_key.json")
  out$in_manifest <- if (is.null(man)) NA else
    ifelse(out$path %in% trust, NA,
           (out$sha256 == man$sha256[match(out$path, man$path)]) %in% TRUE)
  out
}
