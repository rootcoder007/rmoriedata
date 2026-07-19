# R/load_siu_reports.R
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Load the Ontario SIU director's-report corpus
#'
#' Returns the bundled Ontario Special Investigations Unit (SIU)
#' director's-report table: one row per report drid, 65 structured
#' columns (police service, incident / notification / decision dates,
#' investigator and witness / subject-official counts, affected-person
#' demographics, injuries, legislation, charges verdict, director's
#' decision, and news-release linkage), plus a \code{panel_reviewed}
#' flag.
#'
#' For every English report (\code{panel_reviewed == "TRUE"}), the 16
#' key columns were verified by a multi-agent LLM review panel against
#' the full report text and the parser's guess resolved to the correct
#' value; the subject-official count is filled for 100\% of English
#' reports (witness-officer-only investigations are a genuine 0). French
#' reports carry the parser values. See the \code{siu} pipeline repo for
#' the audit provenance.
#'
#' This is the machine-readable companion to the SIU parser and
#' data-mining subsystem in \pkg{rmorie} / \pkg{morie} -- the first
#' open-source pipeline for the SIU director's-report corpus, created
#' by Vansh Singh Ruhela as part of the MORIE / MRM framework. The
#' table is regenerated from the parser over the full public corpus;
#' see \code{rmorie::morie_fetch_siu()} to rebuild it live.
#'
#' @param lang One of \code{"all"} (default), \code{"en"}, or
#'   \code{"fr"}: filter to the English-only, French-only, or all rows.
#' @param as Return format: \code{"data.frame"} (default) or
#'   \code{"tibble"}.
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
#' en <- load_siu_reports(lang = "en")   # English director's reports
#' fr <- load_siu_reports(lang = "fr")   # French director's reports
#' nrow(en); nrow(fr)
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
  if (format == "parquet") {
    if (!requireNamespace("nanoparquet", quietly = TRUE)) {
      stop("format = \"parquet\" needs the 'nanoparquet' package; ",
           "install it or use format = \"csv\".", call. = FALSE)
    }
    ppath <- system.file("extdata", "siu_directors_reports.parquet",
                         package = "rmoriedata")
    if (!nzchar(ppath)) {
      stop("bundled SIU parquet corpus not found in rmoriedata", call. = FALSE)
    }
    df <- as.data.frame(nanoparquet::read_parquet(ppath),
                        stringsAsFactors = FALSE)
  } else {
    path <- system.file("extdata", "siu_directors_reports.csv.gz",
                        package = "rmoriedata")
    if (!nzchar(path)) {
      stop("bundled SIU director's-report corpus not found in rmoriedata",
           call. = FALSE)
    }
    df <- utils::read.csv(gzfile(path), stringsAsFactors = FALSE,
                          colClasses = "character", check.names = FALSE)
  }
  if (lang != "all" && "X_language" %in% names(df)) {
    df <- df[df[["X_language"]] == lang, , drop = FALSE]
  } else if (lang != "all" && "_language" %in% names(df)) {
    df <- df[df[["_language"]] == lang, , drop = FALSE]
  }
  rownames(df) <- NULL
  if (as == "tibble" && requireNamespace("tibble", quietly = TRUE)) {
    return(tibble::as_tibble(df))
  }
  df
}
