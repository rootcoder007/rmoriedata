# Build the Parquet copy of the data store. Run from the package root with
# the current tree installed (the CSV loaders and the schema are the
# source of truth):
#
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# Writes inst/extdata/parquet/<slug>.parquet for every table (typed
# exactly as morie_data_load(slug) returns it), parquet/_catalog.parquet,
# parquet/siu_directors_reports_corpus.parquet, and the `parquet_path` column of
# inst/extdata/_catalog.csv. data-raw is .Rbuildignore'd; the parquet
# directory ships.
suppressMessages(library(rmoriedata))
wp <- rmoriedata:::morie_write_parquet
ed <- file.path("inst", "extdata")
pq <- file.path(ed, "parquet")
dir.create(pq, showWarnings = FALSE)
cat <- utils::read.csv(file.path(ed, "_catalog.csv"), stringsAsFactors = FALSE,
                       encoding = "UTF-8", na.strings = "")
cat$parquet_path <- NA_character_
for (i in seq_len(nrow(cat))) {
  if (cat$kind[i] != "table") next
  d <- morie_data_load(cat$slug[i], refresh = TRUE)
  rel <- file.path("parquet", paste0(cat$slug[i], ".parquet"))
  wp(as.data.frame(d), file.path(ed, rel))
  back <- rmoriedata:::morie_read_parquet(file.path(ed, rel))
  stopifnot(identical(dim(back), dim(d)), identical(names(back), names(d)))
  cat$parquet_path[i] <- rel
}
utils::write.csv(cat, file.path(ed, "_catalog.csv"), row.names = FALSE,
                 na = "", fileEncoding = "UTF-8")
wp(cat, file.path(pq, "_catalog.parquet"))
# the SIU corpus as load_siu_reports() returns it (all character, the CSV
# header verbatim); the typed table copy is parquet/siu_directors_reports.parquet
siu <- load_siu_reports()
wp(siu, file.path(pq, "siu_directors_reports_corpus.parquet"))
message(sum(!is.na(cat$parquet_path)), " tables written to ", pq,
        "; catalog and SIU corpus too")
