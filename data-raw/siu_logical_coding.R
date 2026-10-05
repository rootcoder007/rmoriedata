# SPDX-License-Identifier: AGPL-3.0-or-later
#
# charges_recommended in the logical coding panel_reviewed uses ("TRUE" / "FALSE" / empty),
# so the typed table (_schema.csv: logical) reads both the same way from CSV and Parquet.
# The review table and the round-8 rules write "True" / "False"; run this after them, then
#   Rscript data-raw/sign_store.R; reinstall; Rscript data-raw/build_parquet_store.R;
#   Rscript data-raw/sign_store.R
path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")
s <- utils::read.csv(gzfile(path), colClasses = "character", check.names = FALSE,
                     na.strings = character(), encoding = "UTF-8")
v <- s[["charges_recommended"]]
stopifnot(all(v %in% c("", "True", "False", "TRUE", "FALSE")))
v[v == "True"] <- "TRUE"
v[v == "False"] <- "FALSE"
s[["charges_recommended"]] <- v
con <- gzfile(path, "w", encoding = "UTF-8")
utils::write.csv(s, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
close(con)
print(table(s[["charges_recommended"]], useNA = "always"))
