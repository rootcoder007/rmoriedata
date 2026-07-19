# Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)

Returns the bundled catalogue of the public data-table `.xlsx` workbooks
published on the Canadian Institute for Health Information (CIHI)
“Access data and reports \> Data tables” page
(<https://www.cihi.ca/en/access-data-and-reports/data-tables>). Each row
carries the table title, its direct `url`, and a `wayback_url` snapshot
on the Internet Archive so the table stays retrievable even if CIHI
rotates or removes the live file.

## Usage

``` r
load_cihi_data_tables(archived_only = FALSE)
```

## Source

Canadian Institute for Health Information, Data tables
(<https://www.cihi.ca/en/access-data-and-reports/data-tables>).
Snapshotted to the Internet Archive (<https://web.archive.org>).
Catalogue current as of 2026-07.

## Arguments

- archived_only:

  If `TRUE`, drop rows with no Wayback snapshot. Default `FALSE` (return
  the full catalogue).

## Value

A `data.frame` with columns `title`, `url`, `wayback_url`.

## Details

Pair with `rmorie::morie_ingest_cihi_xlsx()` to download + parse any row
(that helper tries `url` first and falls back to `wayback_url`). The
Wayback snapshots were resolved with
[`rmoriebricklayer::wayback_snapshot_url()`](https://rdrr.io/pkg/rmoriebricklayer/man/wayback_snapshot_url.html).

## Examples

``` r
# Full catalogue: title, live url, Wayback snapshot url.
cat <- load_cihi_data_tables()
nrow(cat)
#> [1] 232
names(cat)
#> [1] "title"           "url"             "format"          "wayback_url"    
#> [5] "retrieved"       "source_page_url" "license"        
head(cat$title, 3)
#> [1] "Injury and Trauma Emergency Department and Hospitalization Statistics, 2024–2025"
#> [2] "Wait Times for Priority Procedures in Canada, 2008 to 2025 — Data Tables"        
#> [3] "Health Workforce in Canada, 2024 — Quick Stats"                                  

# `archived_only = TRUE` keeps only rows that have a Wayback snapshot,
# i.e. tables still retrievable if CIHI rotates the live file.
arch <- load_cihi_data_tables(archived_only = TRUE)
nrow(arch)                       # <= nrow(cat)
#> [1] 218
all(nzchar(arch$wayback_url))    # TRUE
#> [1] TRUE

# Find a table by keyword before fetching it.
cat$title[grepl("hospital", cat$title, ignore.case = TRUE)][1:3]
#> [1] "Injury and Trauma Emergency Department and Hospitalization Statistics, 2024–2025"
#> [2] "Hospital Beds, 2024–2025"                                                        
#> [3] "Inpatient Hospitalization, Surgery and Newborn Statistics, 2024-2025"            
```
