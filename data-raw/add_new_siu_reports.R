# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Add the SIU director's reports published since the corpus was last built. Run from the package
# root:
#
#   SIU_NEW_HTML=<cache dir> Rscript data-raw/add_new_siu_reports.R
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# Crawls both language indexes of siu.on.ca (the same crawl as refresh_siu_manifest.R), and for
# every report id the corpus lacks fetches its page once (rmoriebricklayer::bricklayer_fetch_siu,
# one request, then a 2-second pause; pages are cached in SIU_NEW_HTML so a rerun fetches
# nothing twice), parses it with bricklayer_parse_siu(), and appends a corpus row and a manifest
# row. Fields the parser does not read stay empty, as in the rest of the corpus.
suppressPackageStartupMessages(library(rmoriebricklayer))
polite <- 2.0
ua <- "rmoriedata/corpus-refresh (+https://github.com/rootcoder007/rmoriedata)"
cor_path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")
man_path <- file.path("inst", "extdata", "siu_drid_manifest.csv.gz")
cache <- Sys.getenv("SIU_NEW_HTML", file.path(tempdir(), "siu_new_html"))
langs <- strsplit(Sys.getenv("SIU_LANGS", "en,fr"), ",")[[1]]
# SIU_STAGE=<dir>: write the new rows there (corpus_rows.csv, manifest_rows.csv) and leave the
# shipped files alone, to be appended later
stage <- Sys.getenv("SIU_STAGE")
dir.create(cache, showWarnings = FALSE, recursive = TRUE)

get1 <- function(url) {
  req <- httr2::req_user_agent(httr2::request(url), ua)
  req <- httr2::req_retry(httr2::req_timeout(req, 60L), max_tries = 3L,
                          is_transient = function(r) httr2::resp_status(r) >= 500L)
  httr2::req_perform(req)
}
crawl_index <- function(lang) {
  html <- httr2::resp_body_string(get1(sprintf("https://www.siu.on.ca/%s/directors_reports.php", lang)),
                                  encoding = "UTF-8")
  tm <- regmatches(html, regexec('id="total_drs"[^>]*value="([0-9]+)"', html))[[1L]]
  total <- if (length(tm) == 2L) as.integer(tm[2L]) else NA_integer_
  pat <- paste0("(?s)<nobr>\\s*([0-9]{2}-[A-Z]{2,4}-[0-9]+)\\s*</nobr>",
                '.*?href="[^"]*directors_report_details\\.php\\?drid=([0-9]+)"')
  harvest <- function(h) {
    mm <- regmatches(h, gregexpr(pat, h, perl = TRUE))[[1L]]
    if (!length(mm)) return(NULL)
    parts <- regmatches(mm, regexec(pat, mm, perl = TRUE))
    data.frame(case_number = vapply(parts, `[[`, character(1), 2L),
               drid = as.integer(vapply(parts, `[[`, character(1), 3L)))
  }
  out <- list(harvest(html))
  got <- if (is.null(out[[1L]])) 0L else nrow(out[[1L]])
  while (!is.na(total) && got < total) {
    chunk <- tryCatch(httr2::resp_body_string(get1(sprintf(
      "https://www.siu.on.ca/ssi/get_more_drs.php?lang=%s&lastCount=%d", lang, got)), encoding = "UTF-8"),
      error = function(e) "")
    h <- harvest(chunk)
    if (is.null(h) || !nrow(h)) break
    out[[length(out) + 1L]] <- h
    got <- got + nrow(h)
    Sys.sleep(polite)
  }
  df <- do.call(rbind, out)
  df <- df[!duplicated(df$drid), , drop = FALSE]
  df$lang <- lang
  message(sprintf("[index %s] %d entries (server total %s)", lang, nrow(df), total))
  df
}

cor <- utils::read.csv(gzfile(cor_path), colClasses = "character", check.names = FALSE,
                       encoding = "UTF-8", na.strings = character())
man <- utils::read.csv(gzfile(man_path), stringsAsFactors = FALSE, check.names = FALSE)
idx <- do.call(rbind, lapply(langs, crawl_index))
# a report id is one page: compare ids alone (rows the corpus holds as "unknown" language are
# already there and must not come back as new)
new <- idx[!idx$drid %in% as.integer(cor$drid), , drop = FALSE]
message(sprintf("corpus %d rows; %d reports on the site not in it", nrow(cor), nrow(new)))

now_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S+00:00", tz = "UTC")
pver <- paste0("rmoriebricklayer ", utils::packageVersion("rmoriebricklayer"))
rows <- list()
mrows <- list()
for (i in seq_len(nrow(new))) {
  d <- new$drid[i]
  lg <- new$lang[i]
  f <- file.path(cache, sprintf("%s_%d.html", lg, d))
  if (!file.exists(f) || file.size(f) < 1000) {
    ok <- tryCatch({ bricklayer_fetch_siu(d, f, lang = lg); TRUE }, error = function(e) FALSE)
    Sys.sleep(polite)
    if (!ok) { message("could not fetch ", lg, " ", d); next }
  }
  p <- tryCatch(as.list(bricklayer_parse_siu(f)), error = function(e) NULL)
  if (is.null(p)) { message("could not parse ", lg, " ", d); next }
  # the parser names the subject-officer count as the schema did before the corpus renamed it
  if (!is.null(p[["number_of_subject_officers"]])) p[["number_of_subject_officials"]] <- p[["number_of_subject_officers"]]
  r <- stats::setNames(as.list(rep("", ncol(cor))), names(cor))
  for (nm in intersect(names(p), names(cor))) {
    v <- as.character(p[[nm]])
    if (length(v) == 1L && !is.na(v)) r[[nm]] <- v
  }
  r$case_number <- new$case_number[i]
  r$drid <- as.character(d)
  r$source_url_report <- sprintf("https://www.siu.on.ca/%s/directors_report_details.php?drid=%d", lg, d)
  r$scraped_at_utc <- now_utc
  r$parser_version <- pver
  r[["_language"]] <- lg
  r$panel_reviewed <- "FALSE"
  rows[[length(rows) + 1L]] <- as.data.frame(r, check.names = FALSE, stringsAsFactors = FALSE)
  if (!d %in% man$drid) {
    en_hit <- idx$drid[idx$lang == "en" & idx$case_number == new$case_number[i]]
    mrows[[length(mrows) + 1L]] <- stats::setNames(data.frame(
      d, 200L, as.integer(file.size(f)), 1L, new$case_number[i], "siu.on.ca", now_utc, lg,
      if (lg == "en" || !length(en_hit)) d else en_hit[1L], stringsAsFactors = FALSE), names(man))
  }
}
if (nzchar(stage)) {
  dir.create(stage, showWarnings = FALSE, recursive = TRUE)
  if (length(rows)) utils::write.csv(do.call(rbind, rows), file.path(stage, "corpus_rows.csv"), row.names = FALSE, na = "",
                                     fileEncoding = "UTF-8")
  if (length(mrows)) utils::write.csv(do.call(rbind, mrows), file.path(stage, "manifest_rows.csv"), row.names = FALSE)
  message(sprintf("SIU-ADD-STAGED %d corpus rows, %d manifest rows in %s", length(rows), length(mrows), stage))
  quit(save = "no")
}
if (length(rows)) {
  cor <- rbind(cor, do.call(rbind, rows))
  cor <- cor[order(as.integer(cor$drid), cor[["_language"]]), , drop = FALSE]
  con <- gzfile(cor_path, "w", encoding = "UTF-8")
  utils::write.csv(cor, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  close(con)
}
if (length(mrows)) {
  man <- rbind(man, do.call(rbind, mrows))
  man <- man[order(man$drid), , drop = FALSE]
  con <- gzfile(man_path, "w")
  utils::write.csv(man, con, row.names = FALSE)
  close(con)
}
message(sprintf("SIU-ADD-DONE added %d corpus rows (%d new manifest rows); corpus now %d",
                length(rows), length(mrows), nrow(cor)))
