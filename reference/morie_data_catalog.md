# Catalog of the bundled datasets

One row per bundled table or dictionary: `slug`, `source_path` (relative
to the package's `extdata` directory), `kind`, and for tables `n_rows`
and `n_cols`.

## Usage

``` r
morie_data_catalog()
```

## Value

A data frame.

## Examples

``` r
cat <- morie_data_catalog()
tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
head(tbls[order(-tbls$n_rows), ])
#>                               slug n_rows n_cols
#> 78           siu_directors_reports   5157     65
#> 79               siu_drid_manifest   4749      9
#> 37       nyc_opendata_bulk_catalog   2851      7
#> 28  edmonton_opendata_bulk_catalog   2027      7
#> 23   chicago_opendata_bulk_catalog   1856      7
#> 105          vic_recorded_offences   1129      7
```
