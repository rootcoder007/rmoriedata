#!/usr/bin/env Rscript
# data-raw/build_db.R
#
# Reproducibly build inst/extdata/rmoriedata.sqlite from the bundled tabular
# fixtures. Every CSV (and the gzipped SIU manifest) becomes one table; the
# JSON data dictionaries are folded into a `_dictionaries` table; a `_catalog`
# table records the slug -> source-path mapping and row/col counts.
#
# Re-run after changing any fixture:
#   Rscript data-raw/build_db.R
#
# The loose CSV/JSON sources live in git history; the shipped artifact is the
# single .sqlite. Markdown docs and the .Rds describe-corpus stay as files.

suppressWarnings(suppressMessages({
  stopifnot(requireNamespace("DBI", quietly = TRUE),
            requireNamespace("RSQLite", quietly = TRUE))
}))

root <- normalizePath(".")                          # run from the package root
if (!dir.exists(file.path(root, "inst", "extdata")))
  stop("run this from the rmoriedata package root (inst/extdata not found)",
       call. = FALSE)
extdata <- file.path(root, "inst", "extdata")
db_path <- file.path(extdata, "rmoriedata.sqlite")

slugify <- function(rel) gsub("_+", "_",
                              gsub("[^A-Za-z0-9]+", "_",
                                   sub("\\.(csv|csv\\.gz|json)$", "", rel)))

if (file.exists(db_path)) file.remove(db_path)
con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
on.exit(DBI::dbDisconnect(con))

catalog <- list()

## --- tabular sources: every .csv plus the gzipped manifest ----------------
csvs <- list.files(extdata, pattern = "\\.csv(\\.gz)?$", recursive = TRUE,
                   full.names = TRUE)
for (f in csvs) {
  rel  <- sub(paste0("^", extdata, "/"), "", f)
  slug <- slugify(rel)
  conn <- if (grepl("\\.gz$", f)) gzfile(f) else f
  df   <- utils::read.csv(conn, stringsAsFactors = FALSE, check.names = FALSE)
  DBI::dbWriteTable(con, slug, df, overwrite = TRUE)
  catalog[[length(catalog) + 1L]] <- data.frame(
    slug = slug, source_path = rel, kind = "table",
    n_rows = nrow(df), n_cols = ncol(df), stringsAsFactors = FALSE)
  message(sprintf("  table  %-45s %d x %d", slug, nrow(df), ncol(df)))
}

## --- JSON data dictionaries -> a single _dictionaries table ----------------
jsons <- list.files(extdata, pattern = "\\.json$", recursive = TRUE,
                    full.names = TRUE)
if (length(jsons)) {
  dicts <- do.call(rbind, lapply(jsons, function(f) {
    rel <- sub(paste0("^", extdata, "/"), "", f)
    data.frame(slug = slugify(rel), source_path = rel,
               dictionary_json = paste(readLines(f, warn = FALSE), collapse = "\n"),
               stringsAsFactors = FALSE)
  }))
  DBI::dbWriteTable(con, "_dictionaries", dicts, overwrite = TRUE)
  for (i in seq_len(nrow(dicts)))
    catalog[[length(catalog) + 1L]] <- data.frame(
      slug = dicts$slug[i], source_path = dicts$source_path[i],
      kind = "dictionary", n_rows = NA_integer_, n_cols = NA_integer_,
      stringsAsFactors = FALSE)
  message(sprintf("  %d dictionaries -> _dictionaries", nrow(dicts)))
}

DBI::dbWriteTable(con, "_catalog", do.call(rbind, catalog), overwrite = TRUE)
message(sprintf("Built %s with %d tabular + %d dictionary entries.",
                basename(db_path), length(csvs), length(jsons)))
