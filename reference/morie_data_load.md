# Load a bundled dataset by slug

Reads the table's CSV and applies the column names and classes from the
bundled schema, so the result is the same typed data frame on every
platform regardless of how
[`read.csv()`](https://rdrr.io/r/utils/read.table.html) would have
guessed. The first load of a table is cached for the session; later
calls return the cached copy unless `refresh = TRUE`.

## Usage

``` r
morie_data_load(slug, refresh = FALSE)
```

## Arguments

- slug:

  Dataset slug; see the `slug` column of
  [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md).

- refresh:

  Re-read the file even if a cached copy exists.

## Value

A data frame.

## Examples

``` r
d <- morie_data_load("arsau_2023_uof_main_records")
str(d[, 1:4])
#> 'data.frame':    5 obs. of  4 variables:
#>  $ IncidentYear     : int  2024 2024 2024 2024 2024
#>  $ BatchFileName    : chr  "SYNTHETIC-FIXTURE-001" "SYNTHETIC-FIXTURE-002" "SYNTHETIC-FIXTURE-003" "SYNTHETIC-FIXTURE-004" ...
#>  $ PoliceServiceType: chr  "Municipal Police Service" "Municipal Police Service" "Provincial Police Service" "Municipal Police Service" ...
#>  $ PoliceService    : chr  "Sample Regional Police Service" "Sample Regional Police Service" "OPP" "Sample Regional Police Service" ...
```
