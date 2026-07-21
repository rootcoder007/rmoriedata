# Catalogue of bundled datasets

Lists every dataset in the bundled Parquet store, including row/column
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
cat <- morie_data_catalog()
str(cat)
#> 'data.frame':    96 obs. of  5 variables:
#>  $ slug       : chr  "arsau_uof_detailed_dataset_2020_2022_sample" "arsau_uof_individual_records_sample" "arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022" "arsau_2020_2022_useofforce_detaileddataset_2020_2022" ...
#>  $ source_path: chr  "arsau_uof_detailed_dataset_2020_2022_sample.csv" "arsau_uof_individual_records_sample.csv" "arsau/2020-2022/useofforce_agrregatesummarybyyear_2020-2022.csv" "arsau/2020-2022/useofforce_detaileddataset_2020-2022.csv" ...
#>  $ kind       : chr  "table" "table" "table" "table" ...
#>  $ n_rows     : int  5 5 5 5 5 5 5 5 5 5 ...
#>  $ n_cols     : int  167 112 6 167 112 23 3 5 112 23 ...

# How many datasets of each kind are bundled?
table(cat$kind)
#> 
#> dictionary      table 
#>          8         88 

# The tables, largest first.
tbls <- cat[cat$kind == "table", c("slug", "n_rows", "n_cols")]
head(tbls[order(-tbls$n_rows), ])
#>                              slug n_rows n_cols
#> 71          siu_directors_reports   5157     65
#> 72              siu_drid_manifest   4749      9
#> 31      nyc_opendata_bulk_catalog   2851      7
#> 23 edmonton_opendata_bulk_catalog   2027      7
#> 20  chicago_opendata_bulk_catalog   1856      7
#> 34                otis_b01_sample   1000     18

# Every slug you can pass to morie_data_load().
head(cat$slug, 10)
#>  [1] "arsau_uof_detailed_dataset_2020_2022_sample"                
#>  [2] "arsau_uof_individual_records_sample"                        
#>  [3] "arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022"
#>  [4] "arsau_2020_2022_useofforce_detaileddataset_2020_2022"       
#>  [5] "arsau_2023_uof_individual_records"                          
#>  [6] "arsau_2023_uof_main_records"                                
#>  [7] "arsau_2023_uof_probe_cycle_records"                         
#>  [8] "arsau_2023_uof_weapon_records_invaliddata"                  
#>  [9] "arsau_2024_uof_individual_records"                          
#> [10] "arsau_2024_uof_main_records"                                

# Where each table was originally built from.
head(cat[, c("slug", "source_path")])
#>                                                          slug
#> 1                 arsau_uof_detailed_dataset_2020_2022_sample
#> 2                         arsau_uof_individual_records_sample
#> 3 arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022
#> 4        arsau_2020_2022_useofforce_detaileddataset_2020_2022
#> 5                           arsau_2023_uof_individual_records
#> 6                                 arsau_2023_uof_main_records
#>                                                       source_path
#> 1                 arsau_uof_detailed_dataset_2020_2022_sample.csv
#> 2                         arsau_uof_individual_records_sample.csv
#> 3 arsau/2020-2022/useofforce_agrregatesummarybyyear_2020-2022.csv
#> 4        arsau/2020-2022/useofforce_detaileddataset_2020-2022.csv
#> 5                           arsau/2023/uof_individual_records.csv
#> 6                                 arsau/2023/uof_main_records.csv
```
