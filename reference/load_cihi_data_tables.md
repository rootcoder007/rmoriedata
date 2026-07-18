# Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)

Returns the bundled catalogue of the 232 public data-table workbooks
(`.xlsx`/`.xls`/`.zip`) published on the Canadian Institute for Health
Information (CIHI) “Access data and reports \> Data tables” page. Each
row carries the table title, its direct `url`, format, and a
`wayback_url` snapshot on the Internet Archive so the table stays
retrievable even if CIHI rotates or removes the live file, plus
retrieval date, source page, and licence.

## Usage

``` r
load_cihi_data_tables(archived_only = FALSE)
```

## Arguments

- archived_only:

  If `TRUE`, drop rows with no Wayback snapshot. Default `FALSE` (return
  the full catalogue).

## Value

A `data.frame` with columns `title`, `url`, `format`, `wayback_url`,
`retrieved`, `source_page_url`, `license`.

## Source

Canadian Institute for Health Information, Data tables
(<https://www.cihi.ca/en/access-data-and-reports/data-tables>).
Snapshotted to the Internet Archive (<https://web.archive.org>).
Catalogue built by the C++ data-prep tool `data-raw/cihi_catalog.cpp` in
rmoriebricklayer; current as of 2026-07.

## Details

Pair with
[`fetch_cihi_table`](https://rootcoder007.github.io/rmoriedata/reference/fetch_cihi_table.md)
(or `rmorie::morie_ingest_cihi_xlsx()`) to download + parse any row;
those helpers try `url` first and fall back to `wayback_url` through the
shared C++ fetch engine in rmoriebricklayer.

## Examples

``` r
cat <- load_cihi_data_tables()
nrow(cat)
#> [1] 232
head(cat$title, 3)
#> [1] "Injury and Trauma Emergency Department and Hospitalization Statistics, 2024–2025"
#> [2] "Wait Times for Priority Procedures in Canada, 2008 to 2025 — Data Tables"        
#> [3] "Health Workforce in Canada, 2024 — Quick Stats"                                  
```
