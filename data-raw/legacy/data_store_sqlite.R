# SPDX-License-Identifier: AGPL-3.0-or-later
#
# ============================================================================
# LEGACY / ARCHIVE — the pre-2026-07-01 SQLite loader for R/data_store.R.
# Kept for safekeeping / rollback reference ONLY. NOT sourced or shipped:
# `data-raw/` is .Rbuildignore'd, so this file is never part of the built
# package. The live loader now reads the Parquet store via nanoparquet
# (see R/data_store.R + data-raw/migrate_sqlite_to_parquet.R).
#
# To roll back to SQLite: restore this content into R/data_store.R, restore
# inst/extdata/rmoriedata.sqlite (backed up at
# /Volumes/VSR/rootcoderfiles/rmoriedata-sqlite-backups/ and
# zeus:/mnt/nvme/rootcoderfiles/rmoriedata-sqlite-backups/, sha256 71c456fa...),
# and re-add DBI + RSQLite to DESCRIPTION Suggests.
# ============================================================================

.rmoriedata_db_path <- function() {
  p <- system.file("extdata", "rmoriedata.sqlite", package = "rmoriedata")
  if (!nzchar(p))
    stop("rmoriedata.sqlite not found; reinstall rmoriedata.", call. = FALSE)
  p
}

.rmoriedata_need_db <- function() {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE))
    stop("This function needs the 'DBI' and 'RSQLite' packages. ",
         "Install with install.packages(c(\"DBI\", \"RSQLite\")).",
         call. = FALSE)
}

#' Catalogue of bundled datasets
#'
#' Lists every dataset in the bundled SQLite store, including row/column
#' counts and the original source path each table was built from.
#'
#' @return A `data.frame` with columns `slug`, `source_path`, `kind`,
#'   `nrows`, `n_cols`.
#' @seealso [mdload()], [mddict()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   cat <- mdcat()
#'   head(cat[cat$kind == "table", c("slug", "nrows", "n_cols")])
#' }
#' @export
mdcat <- function() {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  DBI::dbReadTable(con, "_catalog")
}

#' Load a bundled dataset by slug
#'
#' @param slug Dataset slug; see the `slug` column of [mdcat()].
#' @return A `data.frame`.
#' @seealso [mdcat()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   df <- mdload("chicagoiucrcodes")
#'   str(df)
#' }
#' @export
mdload <- function(slug) {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  tables <- DBI::dbListTables(con)
  if (!slug %in% tables)
    stop(sprintf("No dataset '%s'. See mdcat() for valid slugs.",
                 slug), call. = FALSE)
  DBI::dbReadTable(con, slug)
}

#' Data dictionary (JSON) for a dataset, if one is bundled
#'
#' @param slug Dictionary slug; see [mdcat()] rows where
#'   `kind == "dictionary"`.
#' @return A character scalar of JSON, or `NULL` if no dictionary exists.
#' @seealso [mdcat()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   dicts <- mdcat()
#'   subset(dicts, kind == "dictionary", "slug")
#' }
#' @export
mddict <- function(slug) {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  if (!"_dictionaries" %in% DBI::dbListTables(con)) return(NULL)
  d <- DBI::dbReadTable(con, "_dictionaries")
  row <- d[d$slug == slug, , drop = FALSE]
  if (!nrow(row)) return(NULL)
  row$dictionary_json[[1]]
}
