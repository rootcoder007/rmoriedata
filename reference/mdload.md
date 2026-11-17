# Load a bundled dataset by slug

Reads the table's CSV and applies the column names and classes from the
bundled schema, so the result is the same typed data frame on every
platform regardless of how
[`read.csv()`](https://rdrr.io/r/utils/read.table.html) would have
guessed. Every table also ships as a Parquet file holding the same typed
frame; `format = "parquet"` reads that copy instead. The first load of a
table is cached for the session; later calls return the cached copy
unless `refresh = TRUE`. The cached copy is what the file held when it
was checked; when
[`mdverify()`](https://rootcoder007.github.io/rmoriedata/reference/mdverify.md)
finds the file changed since, the cached copy is dropped, and the next
load reads the file again and refuses it.

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
  give the same data frame, value for value: decimal text in the CSV is
  read as the nearest double, the same on every platform.

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
