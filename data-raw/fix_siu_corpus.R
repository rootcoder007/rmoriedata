# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Repairs to the shipped SIU director's-report corpus
# (inst/extdata/siu_directors_reports.csv.gz). Run from the package root:
#
#   SIU_FR_HTML=<dir of fr_<drid>.html pages> Rscript data-raw/fix_siu_corpus.R
#   Rscript data-raw/add_new_siu_reports.R      # reports published since (see its header)
#   Rscript data-raw/apply_siu_review.R         # the reviewed corrections
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# The French pages are fetched once with rmoriebricklayer::bricklayer_fetch_siu(drid, dest,
# lang = "fr") at a polite rate (one request, then a 2-second pause). What changes:
#   * rows for report ids that hold no report (no case number and nothing parsed beyond the
#     id, URL and timestamps) are removed;
#   * a row whose language was "unknown" takes it from its URL (/en/ or /fr/);
#   * French rows get their police service from the page (the corpus parser read only the
#     English label), as bricklayer_parse_siu() reads it;
#   * an incident date written out ("July 18, 2021") in date_of_incident_iso becomes ISO;
#   * age_affected text that is not an age (stray sentence fragments, a value above 110) is
#     cleared.
# Rows sharing a case number are kept: the SIU publishes several reports for one case
# (reconsiderations, further reports), each with its own drid; (drid, _language) is the key.
suppressPackageStartupMessages(library(rmoriebricklayer))
path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")
s <- utils::read.csv(gzfile(path), colClasses = "character", check.names = FALSE,
                     encoding = "UTF-8", na.strings = character())
n0 <- nrow(s)

lang <- s[["_language"]]
url_lang <- sub("^.*siu\\.on\\.ca/([a-z]{2})/.*$", "\\1", s$source_url_report)
fix_lang <- lang == "unknown" & url_lang %in% c("en", "fr")
s[["_language"]][fix_lang] <- url_lang[fix_lang]

ids <- c("drid", "nrid", "source_url_report", "source_url_news", "scraped_at_utc",
         "parser_version", "_language", "case_number", "panel_reviewed")
filled <- rowSums(vapply(s[setdiff(names(s), ids)], nzchar, logical(nrow(s))))
placeholder <- !nzchar(s$case_number) & filled <= 1L
s <- s[!placeholder, , drop = FALSE]

dir <- Sys.getenv("SIU_FR_HTML")
fr <- which(s[["_language"]] == "fr" & !nzchar(s$police_service))
got <- 0L
if (nzchar(dir)) {
  for (i in fr) {
    f <- file.path(dir, sprintf("fr_%s.html", s$drid[i]))
    if (!file.exists(f)) next
    p <- tryCatch(as.list(bricklayer_parse_siu(f)), error = function(e) NULL)
    ps <- if (is.null(p)) "" else as.character(p[["police_service"]] %||% "")
    if (length(ps) == 1L && !is.na(ps) && nzchar(ps)) {
      s$police_service[i] <- ps
      got <- got + 1L
    }
  }
}

iso <- s$date_of_incident_iso
bad_iso <- nzchar(iso) & !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", iso)
s$date_of_incident_iso[bad_iso] <- bricklayer_siu_iso_date(sub(",", "", iso[bad_iso]))

age <- s$age_affected
num <- suppressWarnings(as.numeric(age))
junk <- nzchar(age) & ((!is.na(num) & num > 110) | !grepl("[0-9]|unknown|inconnu", age, ignore.case = TRUE))
s$age_affected[junk] <- ""

con <- gzfile(path, "w", encoding = "UTF-8")
utils::write.csv(s, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
close(con)
message(sprintf(paste0("%d -> %d rows (%d placeholders removed); language from URL for %d; ",
                       "French police service for %d of %d; %d incident dates to ISO; %d ages cleared"),
                n0, nrow(s), sum(placeholder), sum(fix_lang), got, length(fr), sum(bad_iso), sum(junk)))
