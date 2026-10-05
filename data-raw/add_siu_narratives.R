# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Fills narrative_summary in the shipped SIU corpus
# (inst/extdata/siu_directors_reports.csv.gz) from the SIU's own report pages.
# Run from the package root with rmoriebricklayer installed, pointing
# SIU_HTML_DIR at the saved pages (<dir>/recrawl_en/<drid>.html and
# <dir>/recrawl_fr/<drid>.html, from the polite 2026-10-05 re-crawl, one request
# every 3 s):
#
#   SIU_HTML_DIR=~/siu_corpus_work Rscript data-raw/add_siu_narratives.R
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# narrative_summary is the opening of the report's own account of the incident:
#   - "Incident Narrative" (English, 2017 on) / "Description de l'incident" or
#     "Récit de l'incident" (French);
#   - reports without that section (2005-2016, re-opened files) carry their
#     account under "Notification of the SIU" / "Notification de l'UES" /
#     "Avis à l'UES" / "Initial Notification and Decision", which is used instead.
# The paragraphs of that section up to about 900 characters, cut at a sentence end
# (never more than 1,500), skipping the definition notes ("Note:", "Remarque :")
# and stopping at the next section heading. A report whose page has neither section
# keeps the value it had.
suppressPackageStartupMessages(library(rmoriebricklayer))
html_dir <- path.expand(Sys.getenv("SIU_HTML_DIR", "~/siu_corpus_work"))
path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")

end_re <- paste0("^(Relevant Legislation|Analysis and Director|Evidence|Nature of Injur|Materials obtained|",
                 "Video/Audio|Forensic|Expert|Civilian Witness|Witness Officials?|Witness Officers?|Subject Officials?|",
                 "Subject Officers?|The Scene|Scene|Communications Recordings|Conclusion|Director.s decision|",
                 "Police Service Records|Records Obtained|The Team|Mandate|Information Restrictions|",
                 "Dispositions législatives|Analyse et décision|Éléments de preuve|L.équipe|",
                 "Nature des blessures|Incident Commander|Duty Rosters)")
narrative_of <- function(file) {
  h <- paste(readLines(file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  l <- trimws(strsplit(bricklayer_siu_text(h), "\n")[[1]])
  fn <- "( \\[\\d+\\])?$"
  i <- tail(grep(paste0("^(Incident Narrative|Récit de l.incident|Description de l.incident)", fn), l,
                 ignore.case = TRUE), 1)
  src <- "narrative"
  if (!length(i)) {
    i <- tail(grep(paste0("^(Notification of the SIU|Notification de l.\\s*UES|Avis à l.\\s*UES|",
                          "Initial Notification and Decision)", fn), l, ignore.case = TRUE), 1)
    src <- "notification"
  }
  if (!length(i)) return(list(text = NA_character_, source = "none"))
  out <- character()
  for (x in l[(i + 1L):length(l)]) {
    if (!nzchar(x)) next
    if (grepl(end_re, x, ignore.case = TRUE) && nchar(x) < 90) break
    if (grepl("^(Note|Remarque)\\s*:", x)) next
    if (nchar(x) < 60) next
    out <- c(out, x)
    if (sum(nchar(out)) > 900) break
  }
  if (!length(out)) return(list(text = NA_character_, source = src))
  s <- gsub("\\s+", " ", paste(out, collapse = " "))
  if (nchar(s) > 1500) s <- sub("(.*[.!?])[^.!?]*$", "\\1", substr(s, 1, 1500))
  list(text = s, source = src)
}

s <- utils::read.csv(gzfile(path), colClasses = "character", check.names = FALSE,
                     encoding = "UTF-8", na.strings = character())
src <- rep("no page", nrow(s))
for (r in seq_len(nrow(s))) {
  f <- file.path(html_dir, paste0("recrawl_", s$`_language`[r]), paste0(s$drid[r], ".html"))
  if (!file.exists(f)) next
  v <- narrative_of(f)
  src[r] <- v$source
  if (!is.na(v$text)) s$narrative_summary[r] <- v$text
}
print(table(language = s$`_language`, section = src))
cat(sprintf("narrative_summary filled on %d of %d reports\n", sum(nzchar(s$narrative_summary)), nrow(s)))
con <- gzfile(path, "w", encoding = "UTF-8")
utils::write.csv(s, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
close(con)
