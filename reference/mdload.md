# Load a bundled dataset by slug

Reads the table's CSV and applies the column names and classes from the
bundled schema, so the result is the same typed data frame on every
platform regardless of how
[`read.csv()`](https://rdrr.io/r/utils/read.table.html) would have
guessed. Every table also ships as a Parquet file holding the same typed
frame; `format = "parquet"` reads that copy instead. The first load of a
table is cached for the session; later calls return the cached copy
unless `refresh = TRUE`.

## Usage

``` r
mdload(slug, refresh = FALSE, format = c("csv", "parquet"))
```

## Arguments

- slug:

  Dataset slug; see the `slug` column of
  [`mdcat()`](https://rootcoder007.github.io/rmoriedata/reference/mdcat.md).

- refresh:

  Re-read the file, and check it against the signed manifest again, even
  if a cached copy exists.

- format:

  `"csv"` (default) or `"parquet"`: which shipped copy to read. Both
  give the same columns, with the same names and types, and the same
  values, with one exception: in the double columns of five tables
  (`tps_assault_sample` and its copy `samples_tps_assault_sample`,
  `vic_criminal_incidents`, `vic_lga_criminal_incidents` and
  `vic_recorded_offences`) one or two values of the Parquet copy differ
  from the CSV's in the last binary digit (a relative difference below
  3e-16). The CSV text read back gives the double nearest to it; those
  Parquet copies were written from values computed before the CSV text
  was, and hold the next double.

## Value

A data frame.

## Examples

``` r
d <- mdload("arsau_2023_uof_main_records")
str(d[, 1:4])
#> 'data.frame':    5 obs. of  4 variables:
#>  $ IncidentYear     : int  2024 2024 2024 2024 2024
#>  $ BatchFileName    : chr  "SYNTHETIC-FIXTURE-001" "SYNTHETIC-FIXTURE-002" "SYNTHETIC-FIXTURE-003" "SYNTHETIC-FIXTURE-004" ...
#>  $ PoliceServiceType: chr  "Municipal Police Service" "Municipal Police Service" "Provincial Police Service" "Municipal Police Service" ...
#>  $ PoliceService    : chr  "Sample Regional Police Service" "Sample Regional Police Service" "OPP" "Sample Regional Police Service" ...
```
