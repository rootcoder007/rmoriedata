# Download a CIHI data table (live, with Wayback fallback)

Resolves a CIHI table from the bundled catalogue and downloads it to
`dest`, falling back to the Internet Archive snapshot if the live CIHI
URL has rotated or been removed. The download + fallback runs through
rmoriebricklayer's shared C++/libcurl foundation (`bricklayer_fetch()`),
the same engine rmorie and morie use – one implementation across the
ecosystem.

## Usage

``` r
fetch_cihi_table(which, dest = NULL, timeout = 120L)
```

## Arguments

- which:

  A row index into
  [`load_cihi_data_tables()`](https://rootcoder007.github.io/rmoriedata/reference/load_cihi_data_tables.md),
  or a string matched (case-insensitively, as a substring) against table
  titles. Must resolve to exactly one table.

- dest:

  Destination file path. Default: a tempfile with the table's own
  extension.

- timeout:

  Per-request timeout, seconds.

## Value

The `dest` path, invisibly. Errors if both the live URL and its Wayback
fallback fail.

## Examples

``` r
# Offline: inspect the catalogue to choose a `which` argument.
cat <- load_cihi_data_tables()
head(cat$title, 3)
#> [1] "Injury and Trauma Emergency Department and Hospitalization Statistics, 2024–2025"
#> [2] "Wait Times for Priority Procedures in Canada, 2008 to 2025 — Data Tables"        
#> [3] "Health Workforce in Canada, 2024 — Quick Stats"                                  

# \donttest{
# Downloads a table from the live CIHI web service; try() keeps the
# example graceful when the service is unreachable.
# `which` by title substring (case-insensitive; must match exactly one).
f1 <- try(fetch_cihi_table("Hospital Beds"))      # -> tempfile path
#> Error : 'Hospital Beds' matches 7 tables; be more specific:
#>   Hospital Beds, 2024–2025
#>   Hospital Beds Staffed and In Operation, 2023–2024
#>   Hospital Beds Staffed and In Operation, 2022–2023
#>   Hospital Beds Staffed and In Operation, 2021–2022
#>   Hospital Beds Staffed and In Operation, 2020–2021
#>   Hospital Beds Staffed and In Operation, 2019–2020

# `which` by row index into load_cihi_data_tables(); `dest` chooses the
# output path and `timeout` bounds each request (seconds).
f3 <- try(fetch_cihi_table(1, dest = tempfile(fileext = ".xlsx"),
                           timeout = 60))
#> Error : 'bricklayer_fetch' is not an exported object from 'namespace:rmoriebricklayer'

# An ambiguous substring errors and lists the candidates:
try(fetch_cihi_table("data"))
#> Error : 'data' matches 134 tables; be more specific:
#>   Wait Times for Priority Procedures in Canada, 2008 to 2025 — Data Tables
#>   Formulary Coverage in the Pharmaceutical Data Tool
#>   How Canada Compares: Results From the Commonwealth Fund’s 2025 International Health Policy Survey of Primary Care Physicians in 10 Countries — Data Tables
#>   NACRS Emergency Department Visits and Lengths of Stay by Province/Territory, 2025–2026 (Q1 to Q2) — Provisional Data
#>   Deceased Donation, Living Donation and Transplantation in Canada: Summary Volumes — Data Tables
#>   Adult Organ Donation and Transplantation, 2015 to 2024 — Supplementary Data Tables
# }
```
