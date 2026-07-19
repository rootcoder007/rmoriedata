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

if (FALSE) { # \dontrun{
# `which` by title substring (case-insensitive; must match exactly one).
f1 <- fetch_cihi_table("Hospital Beds")           # -> tempfile path

# `which` by row index into load_cihi_data_tables().
f2 <- fetch_cihi_table(1)

# `dest` chooses the output path; `timeout` bounds each request (seconds).
f3 <- fetch_cihi_table(1, dest = tempfile(fileext = ".xlsx"), timeout = 60)

# An ambiguous substring errors and lists the candidates:
fetch_cihi_table("data")
} # }
```
