# Catalog of the bundled datasets

One row per bundled table or dictionary: `slug`, `source_path` (relative
to the package's `extdata` directory), `kind`, and for tables `n_rows`,
`n_cols` and `parquet_path` (the same table as a Parquet file, see
[`morie_data_path()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_path.md)).

## Usage

``` r
morie_data_catalog()
```

## Value

A data frame: `slug`, `source_path`, `kind` (table, dictionary, ...),
`n_rows`, `n_cols`, `parquet_path`, and `synthetic`, TRUE for the tables
that are generated stand-ins with the published schema rather than
published data (the ARSAU use-of-force tables and the `*_synthetic`
ones).

## Examples

``` r
cat <- morie_data_catalog()
cat$slug[cat$synthetic]
#>  [1] "arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022"
#>  [2] "arsau_2020_2022_useofforce_detaileddataset_2020_2022"       
#>  [3] "arsau_2023_uof_individual_records"                          
#>  [4] "arsau_2023_uof_main_records"                                
#>  [5] "arsau_2023_uof_probe_cycle_records"                         
#>  [6] "arsau_2023_uof_weapon_records_invaliddata"                  
#>  [7] "arsau_2024_uof_individual_records"                          
#>  [8] "arsau_2024_uof_main_records"                                
#>  [9] "arsau_2024_uof_probe_cycle_records"                         
#> [10] "arsau_2024_uof_weapon_records"                              
#> [11] "arsau_uof_detailed_dataset_2020_2022_sample"                
#> [12] "arsau_uof_individual_records_sample"                        
#> [13] "cpads_pumf_synthetic"                                       
#> [14] "nibrs_synthetic"                                            
#> [15] "nist_rds_synthetic"                                         
tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
head(tbls[order(-tbls$n_rows), ])
#>                               slug n_rows n_cols
#> 79               siu_drid_manifest   4749      9
#> 78           siu_directors_reports   4623     65
#> 37       nyc_opendata_bulk_catalog   2851      7
#> 28  edmonton_opendata_bulk_catalog   2027      7
#> 23   chicago_opendata_bulk_catalog   1856      7
#> 105          vic_recorded_offences   1129      7
```
