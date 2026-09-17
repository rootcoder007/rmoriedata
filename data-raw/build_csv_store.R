# Build the CSV data store from the (retired) parquet store.
#
# rmoriedata 0.3.3 ships every table once, as the CSV that rmorie reads by
# name. morie_data_load() reads that CSV and applies the column names and
# classes recorded in inst/extdata/_schema.csv, so a table comes back
# exactly as the parquet copy did. This script, run once against a tree
# that still has inst/extdata/parquet/, writes:
#
#   inst/extdata/_catalog.csv   slug, source_path, kind, n_rows, n_cols
#   inst/extdata/_schema.csv    slug, position, name, class
#   inst/extdata/vic/*.csv      the Victoria tables, which existed only as
#                               parquet
#
# It is not shipped (data-raw is .Rbuildignore'd) and needs the parquet
# reader, so run it from the package root before the parquet directory is
# deleted: Rscript data-raw/build_csv_store.R

pkg <- normalizePath(".")
ed <- file.path(pkg, "inst", "extdata")
pq <- file.path(ed, "parquet")
stopifnot(dir.exists(pq))
suppressMessages(library(rmoriedata))  # 0.3.2: still has the parquet reader
read_pq <- function(name) rmoriedata:::morie_read_parquet(file.path(pq, paste0(name, ".parquet")))

cat <- read_pq("_catalog")
dict <- read_pq("_dictionaries")

schema <- list()
for (i in seq_len(nrow(cat))) {
  if (cat$kind[i] != "table") next
  slug <- cat$slug[i]
  d <- read_pq(slug)
  src <- file.path(ed, cat$source_path[i])
  if (!file.exists(src)) {
    # parquet-only table: materialise it as CSV under vic/ (or the slug's
    # own name), NA as an empty cell, UTF-8, no row names
    rel <- file.path("vic", paste0(slug, ".csv"))
    dir.create(file.path(ed, "vic"), showWarnings = FALSE)
    utils::write.csv(d, file.path(ed, rel), row.names = FALSE, na = "",
                     fileEncoding = "UTF-8")
    cat$source_path[i] <- rel
    message("materialised ", slug, " -> ", rel)
  }
  cat$n_rows[i] <- nrow(d)
  cat$n_cols[i] <- ncol(d)
  schema[[slug]] <- data.frame(slug = slug, position = seq_len(ncol(d)),
                               name = names(d),
                               class = vapply(d, function(z) class(z)[1L], ""),
                               stringsAsFactors = FALSE)
}
schema <- do.call(rbind, schema)
rownames(schema) <- NULL
utils::write.csv(cat, file.path(ed, "_catalog.csv"), row.names = FALSE,
                 na = "", fileEncoding = "UTF-8")
utils::write.csv(schema, file.path(ed, "_schema.csv"), row.names = FALSE,
                 na = "", fileEncoding = "UTF-8")
# dictionaries already ship as their JSON files; confirm each catalog row
# points at one
for (i in which(cat$kind == "dictionary")) {
  stopifnot(file.exists(file.path(ed, cat$source_path[i])))
}
message(nrow(cat), " catalog rows, ", nrow(schema), " schema rows written")
