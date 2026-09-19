# Path of a bundled table's shipped file

The absolute path of the CSV or Parquet copy of a table, verified
against the signed manifest first. The Parquet path is the bridge to
Python: `pandas.read_parquet(path)` gives the same typed table
[`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md)
returns.

## Usage

``` r
morie_data_path(slug, format = c("parquet", "csv"))
```

## Arguments

- slug:

  Dataset slug; see the `slug` column of
  [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md).

- format:

  `"parquet"` (default) or `"csv"`.

## Value

A length-1 character path.

## Examples

``` r
p <- morie_data_path("arsau_2023_uof_main_records")
file.exists(p)
#> [1] TRUE
basename(morie_data_path("arsau_2023_uof_main_records", "csv"))
#> [1] "uof_main_records.csv"
```
