# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Loader API over the bundled SQLite store (inst/extdata/rmoriedata.sqlite).
# The store consolidates every bundled tabular fixture into one queryable
# file plus a `_catalog` and `_dictionaries` table. Built by data-raw/build_db.R.

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
#'   `n_rows`, `n_cols`.
#' @seealso [morie_data_load()], [morie_data_dictionary()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   cat <- morie_data_catalog()
#'   head(cat[cat$kind == "table", c("slug", "n_rows", "n_cols")])
#' }
#' @export
morie_data_catalog <- function() {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  DBI::dbReadTable(con, "_catalog")
}

#' Load a bundled dataset by slug
#'
#' @param slug Dataset slug; see the `slug` column of [morie_data_catalog()].
#' @return A `data.frame`.
#' @seealso [morie_data_catalog()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   df <- morie_data_load("chicago_iucr_codes")
#'   str(df)
#' }
#' @export
morie_data_load <- function(slug) {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  tables <- DBI::dbListTables(con)
  if (!slug %in% tables)
    stop(sprintf("No dataset '%s'. See morie_data_catalog() for valid slugs.",
                 slug), call. = FALSE)
  DBI::dbReadTable(con, slug)
}

#' Data dictionary (JSON) for a dataset, if one is bundled
#'
#' @param slug Dictionary slug; see [morie_data_catalog()] rows where
#'   `kind == "dictionary"`.
#' @return A character scalar of JSON, or `NULL` if no dictionary exists.
#' @seealso [morie_data_catalog()]
#' @examples
#' if (requireNamespace("RSQLite", quietly = TRUE)) {
#'   dicts <- morie_data_catalog()
#'   subset(dicts, kind == "dictionary", "slug")
#' }
#' @export
morie_data_dictionary <- function(slug) {
  .rmoriedata_need_db()
  con <- DBI::dbConnect(RSQLite::SQLite(), .rmoriedata_db_path())
  on.exit(DBI::dbDisconnect(con))
  if (!"_dictionaries" %in% DBI::dbListTables(con)) return(NULL)
  d <- DBI::dbReadTable(con, "_dictionaries")
  row <- d[d$slug == slug, , drop = FALSE]
  if (!nrow(row)) return(NULL)
  row$dictionary_json[[1]]
}
