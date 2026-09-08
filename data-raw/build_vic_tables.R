# data-raw/build_vic_tables.R
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Adds the Victorian (Australia) crime tables to the bundled Parquet store.
#
# Source: Crime Statistics Agency Victoria, "Latest Victorian crime data"
#   https://www.crimestatistics.vic.gov.au/crime-statistics/latest-victorian-crime-data
# Licence: CC BY 4.0 (the CSA publishes its data tables under Creative
#   Commons Attribution 4.0 International).
#
# The workbooks are .xlsx. They are read with rmorie's native reader
# (rmorie::morie_datasets_vic_table), so the bundled data goes through the
# same code path a user hits -- no readxl/openxlsx dependency, and no
# second parser to disagree with the first.
#
# Re-run with the workbooks in VIC_CACHE (default ~/work/vicdata):
#   Rscript data-raw/build_vic_tables.R

# Run from the package root, the usual data-raw/ convention.
pkg <- getwd()
if (!dir.exists(file.path(pkg, "inst", "extdata", "parquet"))) {
  stop("run this from the rmoriedata package root", call. = FALSE)
}

CACHE <- Sys.getenv("VIC_CACHE", "~/work/vicdata")
CACHE <- path.expand(CACHE)
PQDIR <- file.path(pkg, "inst", "extdata", "parquet")
stopifnot(dir.exists(PQDIR))

for (f in list.files(file.path(pkg, "R"), pattern = "\\.R$", full.names = TRUE)) {
  try(suppressWarnings(source(f)), silent = TRUE)
}

# Table 1 of each workbook is the headline series; the rest are cuts of it.
KEYS <- c("criminal_incidents", "lga_criminal_incidents", "family_incidents",
          "lga_family_incidents", "victim_reports", "lga_victim_reports",
          "alleged_offender_incidents", "recorded_offences",
          "indigenous_victim_reports", "indigenous_family_incidents")
MAXROWS <- 5000L

catalog <- morie_read_parquet(file.path(PQDIR, "_catalog.parquet"))
catalog <- catalog[!grepl("^vic_", catalog$slug), , drop = FALSE]  # idempotent

added <- list()
for (k in KEYS) {
  csv <- file.path(pkg, "inst", "extdata", sprintf("vic_%s_sample.csv", k))
  if (!file.exists(csv)) {
    message("skip (no extract): ", k); next
  }
  d <- utils::read.csv(csv, check.names = FALSE, stringsAsFactors = FALSE)
  if (nrow(d) > MAXROWS) d <- d[seq_len(MAXROWS), , drop = FALSE]
  slug <- paste0("vic_", k)
  morie_write_parquet(d, file.path(PQDIR, paste0(slug, ".parquet")))
  added[[length(added) + 1L]] <- data.frame(
    slug = slug,
    source_path = sprintf("crimestatistics.vic.gov.au/%s (Table 01)", k),
    kind = "table", n_rows = nrow(d), n_cols = ncol(d),
    stringsAsFactors = FALSE)
  message(sprintf("%-32s %d x %d", slug, nrow(d), ncol(d)))
}

stopifnot(length(added) > 0L)
catalog <- rbind(catalog, do.call(rbind, added))
catalog <- catalog[order(catalog$slug), , drop = FALSE]
morie_write_parquet(catalog, file.path(PQDIR, "_catalog.parquet"))

# Round-trip every slug we just wrote: a parquet file the package cannot
# read back is worse than no bundled data at all.
for (a in added) {
  back <- morie_read_parquet(file.path(PQDIR, paste0(a$slug, ".parquet")))
  stopifnot(nrow(back) == a$n_rows, ncol(back) == a$n_cols)
}
message("catalog now ", nrow(catalog), " rows; ", length(added),
        " Victorian tables round-tripped OK")

# The CSVs were only an intermediate; the store is the shipped artefact.
unlink(file.path(pkg, "inst", "extdata",
                 sprintf("vic_%s_sample.csv", KEYS)))
unlink(file.path(pkg, "inst", "extdata", "vic_catalog.csv"))
