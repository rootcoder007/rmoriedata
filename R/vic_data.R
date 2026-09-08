# R/vic_data.R -- documentation for the bundled Victorian (Australia) crime
# tables. No exported code: the tables are reached through
# morie_data_load("vic_<key>") like every other slug in the store.
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Victorian crime statistics (Crime Statistics Agency Victoria)
#'
#' Ten tables from the Crime Statistics Agency's "Latest Victorian crime
#' data" release, bundled in the Parquet store and reached by slug through
#' [morie_data_load()]. Each is Table 01 -- the headline series -- of the
#' corresponding published workbook, for the year ending March 2026.
#'
#' \describe{
#'   \item{\code{vic_criminal_incidents}}{Criminal incidents by offence
#'     division, subdivision and subgroup, with rate per 100,000.}
#'   \item{\code{vic_recorded_offences}}{Recorded offences on the same
#'     offence hierarchy.}
#'   \item{\code{vic_victim_reports}}{Victim reports by offence.}
#'   \item{\code{vic_alleged_offender_incidents}}{Alleged offender
#'     incidents, including age and sex breakdowns.}
#'   \item{\code{vic_family_incidents}}{Family incidents by category and
#'     outcome.}
#'   \item{\code{vic_lga_criminal_incidents}, \code{vic_lga_victim_reports},
#'     \code{vic_lga_family_incidents}}{The same measures by police region
#'     and Local Government Area.}
#'   \item{\code{vic_indigenous_victim_reports},
#'     \code{vic_indigenous_family_incidents}}{Aboriginal and/or Torres
#'     Strait Islander status breakdowns, as published.}
#' }
#'
#' The workbooks are .xlsx. They were read with rmorie's native reader, so
#' the bundled data comes through the same code path a user hits -- no
#' \pkg{readxl} or \pkg{openxlsx} dependency, and no second parser that
#' could disagree with the first. Rebuild with
#' \code{data-raw/build_vic_tables.R}.
#'
#' Counts are as published by the CSA and are subject to its own
#' revisions: figures for a given year change between releases as
#' incidents are reclassified, so a table bundled here is a snapshot of
#' the March 2026 release, not a permanent record of that year.
#'
#' @source Crime Statistics Agency Victoria, "Latest Victorian crime data".
#'   \url{https://www.crimestatistics.vic.gov.au/crime-statistics/latest-victorian-crime-data}
#'   Released under CC BY 4.0.
#' @seealso [morie_data_catalog()], [morie_data_load()]
#' @examples
#' # Every bundled Victorian table, by slug.
#' cat <- morie_data_catalog()
#' cat[grepl("^vic_", cat$slug), c("slug", "n_rows", "n_cols")]
#'
#' # Headline criminal-incident series.
#' ci <- morie_data_load("vic_criminal_incidents")
#' str(ci)
#'
#' # Incidents by offence division for the most recent year.
#' latest <- ci[ci$Year == max(ci$Year), ]
#' tapply(latest$`Incidents Recorded`, latest$`Offence Division`, sum)
#' @name rmoriedata-victoria
#' @docType data
#' @keywords datasets
NULL
