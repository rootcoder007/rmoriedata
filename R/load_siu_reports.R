# SIU director's-report corpus loaders.
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Load the Ontario SIU director's-report corpus
#'
#' Returns the bundled Ontario Special Investigations Unit (SIU)
#' director's-report table: one row per report drid, 66 structured
#' columns (police service, incident / notification / decision dates,
#' investigator and witness / subject-official counts, affected-person
#' demographics, injuries, legislation, charges verdict, director's
#' decision, and news-release linkage), plus a \code{panel_reviewed}
#' flag.
#'
#' For the English reports marked \code{panel_reviewed == "TRUE"}, the 16
#' key columns were verified by a multi-agent LLM review panel against
#' the full report text and the parser's guess resolved to the correct
#' value; the subject-official count is filled for every one of them
#' (witness-officer-only investigations are a genuine 0). A French report
#' carries its English report's reviewed case facts (the dates, the team,
#' the counts, the affected person's age and sex, the charges and the
#' director's view) and \code{panel_reviewed == "FALSE"}; its text fields
#' stay French, and its \code{police_service} is its English report's
#' service under the name the SIU's French pages use.
#'
#' \code{charges_recommended} is \code{"FALSE"}, \code{"TRUE"} or empty here
#' (every column is text); in the typed table,
#' \code{morie_data_load("siu_directors_reports")}, it is logical
#' (\code{FALSE}, \code{TRUE}, or \code{NA} when the report does not say).
#' \code{corrigenda} holds the SIU's correction notice of a report (a
#' corrigendum is applied to the report it corrects, not counted as a
#' report). \code{narrative_summary} is empty except where the scrape held
#' report text (it held the SIU's mandate paragraph or the page title), and
#' \code{supplemental_materials} lists the legislation and case-law links a
#' report cites.
#'
#' \code{police_service} is the service of the subject officials -- not the
#' force that notified the SIU, which is often a custody, requesting or
#' neighbouring service. Each correction to it is listed with the reason
#' read from the report in \code{data-raw/siu_police_service_review.csv}
#' of the source repository.
#'
#' One row is one published report, keyed by \code{drid} and
#' \code{_language}. A case number can appear on more than one row: the SIU
#' publishes a further report when a case is reconsidered or reported again,
#' each with its own \code{drid}. Some schema columns (for example the raw
#' times of injury and notification, evidence types, and weapons used) are
#' not stated in the published reports and are empty throughout; they are
#' kept so the table's shape matches the parser's schema.
#'
#' This is the machine-readable companion to the SIU parser and
#' data-mining subsystem in \pkg{rmorie} / \pkg{morie} -- the first
#' open-source pipeline for the SIU director's-report corpus, created
#' by Vansh Singh Ruhela as part of the MORIE / MRM framework. The
#' table is regenerated from the parser over the full public corpus;
#' see \code{rmorie::morie_fetch_siu()} to rebuild it live.
#'
#' This loader returns the corpus as text: every column is character and
#' an empty cell is \code{""}, which is the form the SIU parser writes and
#' \pkg{rmorie} reads back. The same table is also in the typed data
#' store: \code{morie_data_load("siu_directors_reports")} applies the
#' bundled schema (integer \code{drid} and counts, \code{NA} for empty
#' cells), so counts of missing values differ between the two entry
#' points by construction; pick the typed store for analysis and this
#' loader for the parser round trip.
#'
#' @param lang One of \code{"all"} (default), \code{"en"}, or
#'   \code{"fr"}: filter to the English-only, French-only, or all rows.
#' @param as Return format: \code{"data.frame"} (default) or
#'   \code{"tibble"}.
#' @param format \code{"csv"} (the gzip CSV, default) or \code{"parquet"}
#'   (the same rows and columns, read from the typed store's Parquet copy and
#'   returned as text).
#' @return A \code{data.frame} (or tibble) of SIU director's-report rows.
#' @source Ontario Special Investigations Unit director's reports,
#'   \url{https://www.siu.on.ca/en/directors_reports.php} (post-2018)
#'   and the Ontario Government archive (pre-2018). Parsed with the
#'   \pkg{rmorie} SIU subsystem.
#' @examples
#' # Default: every parsed report, as a base data.frame.
#' all <- load_siu_reports()
#' nrow(all)
#' ncol(all)
#'
#' # `lang` filters the corpus by report language.
#' en <- load_siu_reports(lang = "en") # English director's reports
#' fr <- load_siu_reports(lang = "fr") # French director's reports
#' nrow(en)
#' nrow(fr)
#'
#' # `as = "tibble"` returns a tibble when the tibble package is present.
#' if (requireNamespace("tibble", quietly = TRUE)) {
#'   tb <- load_siu_reports(lang = "en", as = "tibble")
#'   class(tb)
#' }
#'
#' # The five police services with the most reports.
#' if (nrow(en)) {
#'   top <- sort(table(en$police_service), decreasing = TRUE)
#'   head(top, 5)
#' }
#' @export
load_siu_reports <- function(lang = c("all", "en", "fr"),
                             as = c("data.frame", "tibble"),
                             format = c("csv", "parquet")) {
  lang <- match.arg(lang)
  as <- match.arg(as)
  format <- match.arg(format)
  rel <- "siu_directors_reports.csv.gz"
  path <- system.file("extdata", rel, package = "rmoriedata")
  if (!nzchar(path)) {
    stop("bundled SIU director's-report corpus not found in rmoriedata",
      call. = FALSE
    )
  }
  df <- if (format == "parquet") {
    # the typed table's Parquet copy as text: the corpus ships one Parquet copy, not two
    d <- morie_data_load("siu_directors_reports", format = "parquet")
    d[] <- lapply(d, function(z) {
      z <- as.character(z)
      z[is.na(z)] <- ""
      z
    })
    d
  } else {
    .rmoriedata_check_file(rel)
    utils::read.csv(gzfile(path),
      stringsAsFactors = FALSE, encoding = "UTF-8",
      colClasses = "character", check.names = FALSE
    )
  }
  if (lang != "all" && "X_language" %in% names(df)) {
    df <- df[df[["X_language"]] == lang, , drop = FALSE]
  } else if (lang != "all" && "_language" %in% names(df)) {
    df <- df[df[["_language"]] == lang, , drop = FALSE]
  }
  rownames(df) <- NULL
  if (as == "tibble") return(.rmd_as_tibble(df))
  df
}
