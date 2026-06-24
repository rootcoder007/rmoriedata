# Catalogue of bundled datasets

Lists every dataset in the bundled SQLite store, including row/column
counts and the original source path each table was built from.

## Usage

``` r
morie_data_catalog()
```

## Value

A \`data.frame\` with columns \`slug\`, \`source_path\`, \`kind\`,
\`n_rows\`, \`n_cols\`.

## See also

\[morie_data_load()\], \[morie_data_dictionary()\]

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  cat <- morie_data_catalog()
  head(cat[cat$kind == "table", c("slug", "n_rows", "n_cols")])
}
#>                                                          slug n_rows n_cols
#> 1                 arsau_uof_detailed_dataset_2020_2022_sample      5    167
#> 2                         arsau_uof_individual_records_sample      5    112
#> 3 arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022      5      6
#> 4        arsau_2020_2022_useofforce_detaileddataset_2020_2022      5    167
#> 5                           arsau_2023_uof_individual_records      5    112
#> 6                                 arsau_2023_uof_main_records      5     23
```
