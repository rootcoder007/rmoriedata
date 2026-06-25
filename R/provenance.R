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
#'   \code{file}, \code{bytes}, and \code{sha256}.
#' @examples
#' head(morie_data_checksums())
#' @export
morie_data_checksums <- function() {
  dir <- system.file("extdata", package = "rmoriedata")
  empty <- data.frame(
    file = character(), bytes = numeric(), sha256 = character(),
    stringsAsFactors = FALSE
  )
  if (!nzchar(dir) || !dir.exists(dir)) {
    return(empty)
  }
  files <- list.files(dir, full.names = TRUE, recursive = TRUE)
  if (length(files) == 0L) {
    return(empty)
  }
  data.frame(
    file   = basename(files),
    bytes  = file.size(files),
    sha256 = vapply(files, rmoriebricklayer::sha256_file, character(1)),
    row.names = NULL,
    stringsAsFactors = FALSE
  )
}
