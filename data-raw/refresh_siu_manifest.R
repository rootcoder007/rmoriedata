# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Incremental SIU drid-manifest refresh (en + fr), standalone.
#
# Crawls both language director's-reports indexes (2026-07 layout:
# <tr class="dr-item"> rows + /ssi/get_more_drs.php infinite-scroll
# pagination), diffs against inst/extdata/siu_drid_manifest.csv.gz,
# fetches ONLY new drids' report pages at a polite 2-second rate, and
# appends rows in the existing schema. Run weekly by
# .github/workflows/siu-manifest-refresh.yml; also runnable by hand:
#   Rscript data-raw/refresh_siu_manifest.R
#
# Only new reports cost a page fetch, so the weekly run is a ~5-minute
# index crawl plus a handful of detail requests.

polite <- 2.0
ua <- "rmoriedata/manifest-refresh (+https://github.com/rootcoder007/rmoriedata)"
man_path <- "inst/extdata/siu_drid_manifest.csv.gz"
stopifnot(file.exists(man_path))

get1 <- function(url) {
  req <- httr2::request(url)
  req <- httr2::req_user_agent(req, ua)
  req <- httr2::req_timeout(req, 60L)
  req <- httr2::req_retry(req, max_tries = 3L,
    is_transient = function(r) httr2::resp_status(r) >= 500L)
  httr2::req_perform(req)
}

crawl_index <- function(lang) {
  base <- sprintf("https://www.siu.on.ca/%s/directors_reports.php", lang)
  html <- httr2::resp_body_string(get1(base), encoding = "UTF-8")
  tm <- regmatches(html, regexec('id="total_drs"[^>]*value="([0-9]+)"',
                                 html))[[1L]]
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
    u <- sprintf(
      "https://www.siu.on.ca/ssi/get_more_drs.php?lang=%s&lastCount=%d",
      lang, got)
    chunk <- tryCatch(
      httr2::resp_body_string(get1(u), encoding = "UTF-8"),
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
  message(sprintf("[index %s] %d entries (server total %s)",
                  lang, nrow(df), total))
  df
}

idx <- rbind(crawl_index("en"), crawl_index("fr"))
man <- utils::read.csv(gzfile(man_path), stringsAsFactors = FALSE,
                       check.names = FALSE)
new <- idx[!(idx$drid %in% man$drid), , drop = FALSE]
message(sprintf("manifest %d rows; %d new drids", nrow(man), nrow(new)))

if (nrow(new)) {
  now_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  rows <- vector("list", nrow(new))
  for (i in seq_len(nrow(new))) {
    d <- new$drid[i]; lg <- new$lang[i]
    u <- sprintf(
      "https://www.siu.on.ca/%s/directors_report_details.php?drid=%d",
      lg, d)
    code <- NA_integer_; bytes <- NA_integer_
    resp <- tryCatch(get1(u), error = function(e) NULL)
    if (!is.null(resp)) {
      code <- httr2::resp_status(resp)
      bytes <- nchar(httr2::resp_body_string(resp, encoding = "UTF-8"),
                     type = "bytes")
    }
    en_hit <- idx$drid[idx$lang == "en" &
                         idx$case_number == new$case_number[i]]
    rows[[i]] <- data.frame(
      drid = d, http_code = code, body_bytes = bytes, attempts = 1L,
      case_number = new$case_number[i], source = "siu.on.ca",
      retrieved_at_utc = now_utc, `_language` = lg,
      canonical_drid = if (lg == "en") d else
        if (length(en_hit)) en_hit[1L] else d,
      stringsAsFactors = FALSE, check.names = FALSE)
    Sys.sleep(polite)
  }
  add <- do.call(rbind, rows)
  names(add) <- names(man)
  man <- rbind(man, add)
  man <- man[order(man$drid), ]
  con <- gzfile(man_path, "w")
  utils::write.csv(man, con, row.names = FALSE)
  close(con)
}
message(sprintf("MANIFEST-REFRESH-DONE rows=%d new=%d", nrow(man),
                nrow(new)))
