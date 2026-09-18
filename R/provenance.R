# SPDX-License-Identifier: AGPL-3.0-or-later

#' SHA256 checksums of bundled rmoriedata files
#'
#' Computes the SHA256 digest of every file rmoriedata bundles in
#' \code{inst/extdata}, using the shared provenance layer
#' (\code{\link[rmoriebricklayer]{sha256_file}}). This lets an analysis
#' verify it used the exact data slice rmoriedata shipped, and is
#' rmoriedata's integration with the bricklayer provenance layer.
#'
#' @return A data frame with one row per bundled file and columns
#'   \code{path} (relative to the extdata root, forward slashes, unique),
#'   \code{file} (the bare basename), \code{bytes}, and \code{sha256}.
#'   Use \code{path} to locate a file; several basenames recur in more
#'   than one directory.
#' @examples
#' # One row per bundled file: name, size in bytes, SHA256 digest.
#' ck <- morie_data_checksums()
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
#'   again <- morie_data_checksums()
#'   stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
#' }
#' @export
morie_data_checksums <- function() {
  dir <- system.file("extdata", package = "rmoriedata")
  empty <- data.frame(
    path = character(), file = character(), bytes = numeric(),
    sha256 = character(), stringsAsFactors = FALSE
  )
  if (!nzchar(dir) || !dir.exists(dir)) {
    return(empty)
  }
  files <- list.files(dir, full.names = TRUE, recursive = TRUE)
  if (length(files) == 0L) {
    return(empty)
  }
  data.frame(
    path = substring(files, nchar(dir) + 2L),
    file = basename(files),
    bytes = file.size(files),
    sha256 = vapply(files, rmoriebricklayer::sha256_file, character(1)),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}
