# data-raw/arrest_sample.R
# Build `arrest_sample`: a CRAN-safe slice of Chicago "Arrests". Full data
# (~1.5M rows) is fetched on demand by load_chicago_data("arrests", full = TRUE).
#
# Source: City of Chicago Open Data, "Arrests"
#   https://data.cityofchicago.org/resource/dpt3-jri9.csv

SOCRATA <- "https://data.cityofchicago.org/resource/dpt3-jri9.csv"
N_SAMPLE <- 25000L

where <- utils::URLencode("arrest_date IS NOT NULL", reserved = TRUE)
url <- paste0(SOCRATA, "?$limit=", N_SAMPLE, "&$where=", where, "&$order=:id")

raw <- utils::read.csv(url, stringsAsFactors = FALSE, check.names = TRUE)

posix <- function(x) as.POSIXct(x, tz = "America/Chicago",
                                format = "%Y-%m-%dT%H:%M:%S")

# Upstream column names vary (charge_1_type vs charge1type); resolve defensively.
pick <- function(df, ...) {
  for (nm in c(...)) if (nm %in% names(df)) return(df[[nm]])
  rep(NA_character_, nrow(df))
}

arrest_sample <- data.frame(
  case_number    = as.character(pick(raw, "case_number", "case_no", "cb_no")),
  date_iso       = format(posix(pick(raw, "arrest_date", "date")),
                          "%Y-%m-%dT%H:%M:%S%z"),
  date           = posix(pick(raw, "arrest_date", "date")),
  race           = as.character(pick(raw, "race")),
  charge_type    = as.character(pick(raw, "charge_1_type", "charge1type")),
  charge_class   = as.character(pick(raw, "charge_1_class", "charge1class")),
  charge_desc    = as.character(pick(raw, "charge_1_description",
                                     "charge1description")),
  charge_statute = as.character(pick(raw, "charge_1_statute", "charge1statute")),
  stringsAsFactors = FALSE
)

usethis::use_data(arrest_sample, version = 2, compress = "xz", overwrite = TRUE)
