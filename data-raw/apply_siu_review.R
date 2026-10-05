# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Applies data-raw/siu_police_service_review.csv to the shipped SIU corpus
# (inst/extdata/siu_directors_reports.csv.gz). Run from the package root after
# fix_siu_corpus.R:
#
#   Rscript data-raw/apply_siu_review.R                                     # the 0.3.4 table
#   Rscript data-raw/apply_siu_review.R data-raw/siu_round8_review.csv      # round 8 (0.3.5)
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# Each review row names one report (drid + language), one field, the value the
# corpus holds now and the value it should hold, with the reason read from the
# report. police_service is the service of the subject officials: the English
# rows carry the reviewed value (24 corrected after reading the report), the
# French rows the same service as their English report, under the name the
# SIU's French pages use. Field "_drop" removes a row that holds no director's
# report (an empty page, an annual-report page, a second copy of a French
# report); field "_language" relabels a French report filed under /en/. A field the
# corpus does not have yet (round 8's "corrigenda", the SIU's correction notice of a report,
# carried on the report it corrects) is added as an empty column first.
#
# A row whose current value differs from old_value is not touched and is
# reported: the table was built against one state of the corpus.
path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")
s <- utils::read.csv(gzfile(path), colClasses = "character", check.names = FALSE,
                     encoding = "UTF-8", na.strings = character())
args <- commandArgs(trailingOnly = TRUE)
table <- if (length(args)) args[[1L]] else file.path("data-raw", "siu_police_service_review.csv")
rv <- utils::read.csv(table, colClasses = "character", encoding = "UTF-8", na.strings = character())
for (f in setdiff(unique(rv$field), c("_drop", names(s)))) s[[f]] <- ""
n0 <- nrow(s)
row_of <- function(drid, lang) which(s$drid == drid & s[["_language"]] == lang)
stale <- character()
drop <- integer()
done <- 0L
for (k in seq_len(nrow(rv))) {
  i <- row_of(rv$drid[k], rv$language[k])
  if (length(i) != 1L) {
    stale <- c(stale, sprintf("%s/%s: %d rows", rv$drid[k], rv$language[k], length(i)))
    next
  }
  f <- rv$field[k]
  if (f == "_drop") {
    drop <- c(drop, i)
  } else if (!identical(s[[f]][i], rv$old_value[k])) {
    stale <- c(stale, sprintf("%s/%s %s: %s", rv$drid[k], rv$language[k], f, s[[f]][i]))
    next
  } else {
    s[[f]][i] <- rv$new_value[k]
  }
  done <- done + 1L
}
if (length(drop)) s <- s[-drop, , drop = FALSE]
con <- gzfile(path, "w", encoding = "UTF-8")
utils::write.csv(s, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
close(con)
message(sprintf("%d of %d review rows applied; %d -> %d rows", done, nrow(rv), n0, nrow(s)))
if (length(stale)) {
  message("not applied (corpus differs from the table):\n  ", paste(utils::head(stale, 20), collapse = "\n  "))
}
