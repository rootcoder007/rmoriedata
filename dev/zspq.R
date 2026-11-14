# SPDX-License-Identifier: AGPL-3.0-or-later
# zspq.R DIR: write the ZSTD Parquet fixtures of tests/testthat/test-zstd.R, one
# table written by nanoparquet, arrow and DuckDB (none of them a dependency of the
# package). The table is the one the test builds; keep the two in step.
out <- commandArgs(TRUE)[1]
i <- seq_len(400L)
df <- data.frame(
  id = i,
  x = ifelse(i %% 11L == 0L, NA, round(sin(i) * 1000, 3)),
  grp = ifelse(i %% 13L == 0L, NA, c("north", "south", "east", "west")[i %% 4L + 1L]),
  flag = i %% 3L == 0L,
  big = as.numeric(i) * 1e6,
  stringsAsFactors = FALSE
)
nanoparquet::write_parquet(df, file.path(out, "nanoparquet.parquet"), compression = "zstd")
arrow::write_parquet(df, file.path(out, "arrow.parquet"), compression = "zstd")
con <- DBI::dbConnect(duckdb::duckdb(shared_home = FALSE))
duckdb::duckdb_register(con, "df", df)
DBI::dbExecute(con, sprintf("COPY df TO '%s' (FORMAT parquet, COMPRESSION zstd)",
                            file.path(out, "duckdb.parquet")))
DBI::dbDisconnect(con, shutdown = TRUE)
cat("nanoparquet", format(packageVersion("nanoparquet")), "arrow",
    format(packageVersion("arrow")), "duckdb", format(packageVersion("duckdb")), "\n")
