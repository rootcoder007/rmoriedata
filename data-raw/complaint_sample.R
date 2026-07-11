# data-raw/complaint_sample.R
# Build `complaint_sample`: a CRAN-safe slice of Chicago "Crimes" (reported
# incidents = complaints). Full data (~8M rows) is fetched on demand by
# load_chicago_data("complaints", full = TRUE); here we bundle only a sample.
#
# Source: City of Chicago Open Data, "Crimes - 2001 to present"
#   https://data.cityofchicago.org/resource/ijzp-q8t2.csv  (SODA2 / SoQL)

SOCRATA <- "https://data.cityofchicago.org/resource/ijzp-q8t2.csv"
N_SAMPLE <- 25000L   # ~25k rows -> < 1 MB xz; keeps the package under CRAN's 5 MB

# The $where value contains spaces and operators; URL-encode it (reserved =
# TRUE) so read.csv() accepts the URL.
where <- utils::URLencode("year>=2020 AND latitude IS NOT NULL", reserved = TRUE)
url <- paste0(SOCRATA, "?$limit=", N_SAMPLE, "&$where=", where, "&$order=:id")

raw <- utils::read.csv(url, stringsAsFactors = FALSE, check.names = TRUE)

as_int <- function(x) suppressWarnings(as.integer(x))
posix  <- function(x) as.POSIXct(x, tz = "America/Chicago",
                                 format = "%Y-%m-%dT%H:%M:%S")

complaint_sample <- data.frame(
  case_number    = as.character(raw$case_number),
  date_iso       = format(posix(raw$date), "%Y-%m-%dT%H:%M:%S%z"),
  date           = posix(raw$date),
  iucr           = as.character(raw$iucr),
  primary_type   = as.character(raw$primary_type),
  description    = as.character(raw$description),
  arrest         = as.logical(raw$arrest),
  domestic       = as.logical(raw$domestic),
  beat           = as_int(raw$beat),
  district       = as_int(raw$district),
  ward           = as_int(raw$ward),
  community_area = as_int(raw$community_area),
  fbi_code       = as.character(raw$fbi_code),
  year           = as_int(raw$year),
  latitude       = as.numeric(raw$latitude),
  longitude      = as.numeric(raw$longitude),
  stringsAsFactors = FALSE
)

# version = 2 (portable, R>=3.5 default); xz beats bzip2 by ~15% on this frame
# and R reads it natively -- we prioritise the CRAN 5 MB cap over build speed.
usethis::use_data(complaint_sample, version = 2, compress = "xz",
                  overwrite = TRUE)
