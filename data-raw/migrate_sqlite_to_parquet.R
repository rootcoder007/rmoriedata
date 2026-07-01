# SPDX-License-Identifier: AGPL-3.0-or-later
#
# One-time (re-runnable) migration: convert the bundled SQLite store
# (inst/extdata/rmoriedata.sqlite) into a Parquet store
# (inst/extdata/parquet/<name>.parquet), so rmoriedata no longer needs RSQLite
# (whose vendored boost is a slow/timeout-prone source compile on r-universe
# Windows). Parquet is cross-language (R / Python / DuckDB / Arrow).
#
# Reads via RSQLite (build-time only), writes via nanoparquet. Deterministic.
# Does NOT delete the .sqlite -- verify equivalence first, remove separately.
#
#   Rscript data-raw/migrate_sqlite_to_parquet.R

stopifnot(
  requireNamespace("DBI", quietly = TRUE),
  requireNamespace("RSQLite", quietly = TRUE),
  requireNamespace("nanoparquet", quietly = TRUE)
)

db     <- "inst/extdata/rmoriedata.sqlite"
outdir <- "inst/extdata/parquet"
if (!file.exists(db)) stop("SQLite store not found: ", db)
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

con  <- DBI::dbConnect(RSQLite::SQLite(), db)
on.exit(DBI::dbDisconnect(con), add = TRUE)
tabs <- DBI::dbListTables(con)
cat("SQLite tables:", length(tabs), "\n")

for (t in tabs) {
  df <- DBI::dbReadTable(con, t)
  nanoparquet::write_parquet(df, file.path(outdir, paste0(t, ".parquet")))
}
cat("Wrote", length(tabs), "parquet files ->", outdir, "\n")

# ---- Verify equivalence (row/col/names + values) ----------------------------
mismatch <- character()
for (t in tabs) {
  sq <- DBI::dbReadTable(con, t)
  pq <- as.data.frame(nanoparquet::read_parquet(file.path(outdir, paste0(t, ".parquet"))))
  same_shape <- nrow(sq) == nrow(pq) && ncol(sq) == ncol(pq) &&
    identical(names(sq), names(pq))
  same_vals  <- isTRUE(all.equal(sq, pq, check.attributes = FALSE))
  if (!same_shape || !same_vals) {
    mismatch <- c(mismatch, t)
    cat(sprintf("  MISMATCH %-45s sqlite %dx%d | parquet %dx%d | vals=%s\n",
      t, nrow(sq), ncol(sq), nrow(pq), ncol(pq), same_vals))
  }
}
if (length(mismatch)) {
  stop("VERIFICATION FAILED for: ", paste(mismatch, collapse = ", "))
}
sz_sql <- file.info(db)$size
sz_pq  <- sum(file.info(list.files(outdir, full.names = TRUE))$size)
cat(sprintf("VERIFIED: all %d tables equivalent.\n", length(tabs)))
cat(sprintf("Size: sqlite %.2f MB -> parquet %.2f MB\n",
  sz_sql / 1e6, sz_pq / 1e6))
