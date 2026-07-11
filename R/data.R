# R/data.R -- roxygen documentation for the bundled Chicago sample datasets.
# SPDX-License-Identifier: AGPL-3.0-or-later

#' Chicago reported-crime sample ("complaints")
#'
#' A CRAN-safe slice of the City of Chicago "Crimes -- 2001 to present" dataset
#' (reported incidents), filtered to geocoded rows from 2020 onward. For the
#' full dataset use \code{load_chicago_data("complaints", full = TRUE)}.
#'
#' @format A base \code{data.frame} with up to 25,000 rows and 16 columns:
#' \describe{
#'   \item{case_number}{Chicago PD records-division number (character).}
#'   \item{date_iso}{Incident timestamp as an ISO-8601 string with offset
#'     (lossless across R/Python).}
#'   \item{date}{Incident timestamp as \code{POSIXct} (America/Chicago).}
#'   \item{iucr}{Illinois Uniform Crime Reporting code (character).}
#'   \item{primary_type}{Primary FBI crime classification.}
#'   \item{description}{Secondary description of the offense.}
#'   \item{arrest}{Whether an arrest was made (logical).}
#'   \item{domestic}{Whether domestic-violence related (logical).}
#'   \item{beat,district,ward,community_area}{Geographic area codes (integer).}
#'   \item{fbi_code}{FBI crime code (character).}
#'   \item{year}{Year of the incident (integer).}
#'   \item{latitude,longitude}{WGS84 coordinates (numeric).}
#' }
#' @source City of Chicago Open Data Portal, "Crimes - 2001 to present"
#'   (dataset \code{ijzp-q8t2}). \url{https://data.cityofchicago.org/}
#' @seealso \code{\link{load_chicago_data}}
#' @examples
#' data(complaint_sample)
#' nrow(complaint_sample)
#' head(sort(table(complaint_sample$primary_type), decreasing = TRUE), 5)
"complaint_sample"

#' Chicago arrests sample
#'
#' A CRAN-safe slice of the City of Chicago "Arrests" dataset. For the full
#' ~1.5M-row dataset use \code{load_chicago_data("arrests", full = TRUE)}.
#'
#' @format A base \code{data.frame} with up to 25,000 rows and 8 columns:
#' \describe{
#'   \item{case_number}{Chicago PD records-division number (character).}
#'   \item{date_iso}{Arrest timestamp as an ISO-8601 string with offset.}
#'   \item{date}{Arrest timestamp as \code{POSIXct} (America/Chicago).}
#'   \item{race}{Recorded race of the arrestee (character).}
#'   \item{charge_type}{Charge type of the primary charge (F/M/etc.).}
#'   \item{charge_class}{Charge class of the primary charge.}
#'   \item{charge_desc}{Description of the primary charge.}
#'   \item{charge_statute}{Statute of the primary charge.}
#' }
#' @source City of Chicago Open Data Portal, "Arrests"
#'   (dataset \code{dpt3-jri9}). \url{https://data.cityofchicago.org/}
#' @seealso \code{\link{load_chicago_data}}
#' @examples
#' data(arrest_sample)
#' nrow(arrest_sample)
#' sort(table(arrest_sample$race), decreasing = TRUE)
"arrest_sample"
