# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Loader API over the bundled Parquet store (inst/extdata/parquet/).
# Migrated from SQLite -> Parquet on 2026-07-01 so the package no longer needs
# RSQLite (whose vendored boost is a slow/timeout-prone source compile on
# r-universe Windows). Parquet is cross-language (R / Python / DuckDB / Arrow).
# Each table is one <slug>.parquet, plus `_catalog.parquet` and
# `_dictionaries.parquet`. Rebuilt by data-raw/migrate_sqlite_to_parquet.R.

.rmoriedata_parquet_dir <- function() {
  p <- system.file("extdata", "parquet", package = "rmoriedata")
  if (!nzchar(p) || !dir.exists(p)) {
    stop("rmoriedata parquet store not found; reinstall rmoriedata.",
      call. = FALSE)
  }
  p
}

.rmoriedata_read <- function(name) {
  f <- file.path(.rmoriedata_parquet_dir(), paste0(name, ".parquet"))
  if (!file.exists(f)) {
    return(NULL)
  }
  as.data.frame(nanoparquet::read_parquet(f))
}

#' Catalogue of bundled datasets
#'
#' Lists every dataset in the bundled Parquet store, including row/column
#' counts and the original source path each table was built from.
#'
#' @return A `data.frame` with columns `slug`, `source_path`, `kind`,
#'   `n_rows`, `n_cols`.
#' @seealso [morie_data_load()], [morie_data_dictionary()]
#' @examples
#' cat <- morie_data_catalog()
#' str(cat)
#'
#' # How many datasets of each kind are bundled?
#' table(cat$kind)
#'
#' # The tables, largest first.
#' tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
#' head(tbls[order(-tbls$n_rows), ])
#'
#' # Every slug you can pass to morie_data_load().
#' head(cat$slug, 10)
#'
#' # Where each table was originally built from.
#' head(cat[, c("slug", "source_path")])
#' @export
morie_data_catalog <- function() {
  cat <- .rmoriedata_read("_catalog")
  if (is.null(cat)) {
    stop("rmoriedata catalog not found; reinstall rmoriedata.", call. = FALSE)
  }
  cat
}

#' Load a bundled dataset by slug
#'
#' @param slug Dataset slug; see the `slug` column of [morie_data_catalog()].
#' @return A `data.frame`.
#' @seealso [morie_data_catalog()]
#' @examples
#' # Load a bundled lookup table by its slug.
#' iucr <- morie_data_load("chicago_iucr_codes")
#' str(iucr)
#' head(iucr)
#'
#' # Any slug from the catalogue works the same way.
#' hoods   <- morie_data_load("chicago_neighborhoods")
#' offense <- morie_data_load("nyc_nypd_offense_codes")
#' nrow(hoods); nrow(offense)
#'
#' # Slugs are validated: an unknown one errors with guidance.
#' try(morie_data_load("no_such_dataset"))
#'
#' # Pattern: pick a slug programmatically from the catalogue, then load it.
#' cat  <- morie_data_catalog()
#' slug <- cat$slug[cat$kind == "table"][1]
#' head(morie_data_load(slug))
#' @export
morie_data_load <- function(slug) {
  if (is.null(slug) || length(slug) != 1L || is.na(slug) || !is.character(slug)) {
    stop("`slug` must be a single dataset slug (character). ",
         "See morie_data_catalog() for valid slugs.", call. = FALSE)
  }
  f <- file.path(.rmoriedata_parquet_dir(), paste0(slug, ".parquet"))
  if (!file.exists(f)) {
    stop(sprintf("No dataset '%s'. See morie_data_catalog() for valid slugs.",
      slug), call. = FALSE)
  }
  as.data.frame(nanoparquet::read_parquet(f))
}

#' Data dictionary (JSON) for a dataset, if one is bundled
#'
#' @param slug Dictionary slug; see [morie_data_catalog()] rows where
#'   `kind == "dictionary"`.
#' @return A character scalar of JSON, or `NULL` if no dictionary exists.
#' @seealso [morie_data_catalog()]
#' @examples
#' # Which dictionaries are bundled?
#' cat  <- morie_data_catalog()
#' dict_slugs <- cat$slug[cat$kind == "dictionary"]
#' dict_slugs
#'
#' # Fetch one dictionary's JSON (returns a character scalar of JSON).
#' if (length(dict_slugs)) {
#'   js <- morie_data_dictionary(dict_slugs[1])
#'   substr(js, 1, 200)
#'   # Parse it if you have jsonlite:
#'   if (requireNamespace("jsonlite", quietly = TRUE))
#'     str(jsonlite::fromJSON(js), max.level = 1)
#' }
#'
#' # Unknown / non-dictionary slug: informative message, returns NULL.
#' morie_data_dictionary("no_such_dictionary")
#' @export
morie_data_dictionary <- function(slug) {
  d <- .rmoriedata_read("_dictionaries")
  if (is.null(d)) {
    message("No data dictionaries are bundled in this installation.")
    return(invisible(NULL))
  }
  row <- d[d$slug == slug, , drop = FALSE]
  if (!nrow(row)) {
    message("No dictionary bundled for '", slug,
            "'. Rows with kind == \"dictionary\" in morie_data_catalog() list the ones available.")
    return(invisible(NULL))
  }
  row$dictionary_json[[1]]
}
