# Data dictionary (JSON) for a dataset, if one is bundled

Data dictionary (JSON) for a dataset, if one is bundled

## Usage

``` r
morie_data_dictionary(slug)
```

## Arguments

- slug:

  Dictionary slug; see \[morie_data_catalog()\] rows where \`kind ==
  "dictionary"\`.

## Value

A character scalar of JSON, or \`NULL\` if no dictionary exists.

## See also

\[morie_data_catalog()\]

## Examples

``` r
# Which dictionaries are bundled?
cat  <- morie_data_catalog()
dict_slugs <- cat$slug[cat$kind == "dictionary"]
dict_slugs
#> [1] "arsau_2020_2022_dictionary" "arsau_2023_dictionary"     
#> [3] "arsau_2024_dictionary"      "corrections_uof_dictionary"
#> [5] "otis_dictionary"            "tps_dictionary"            
#> [7] "uof_dictionary"            

# Fetch one dictionary's JSON (returns a character scalar of JSON).
if (length(dict_slugs)) {
  js <- morie_data_dictionary(dict_slugs[1])
  substr(js, 1, 200)
  # Parse it if you have jsonlite:
  if (requireNamespace("jsonlite", quietly = TRUE))
    str(jsonlite::fromJSON(js), max.level = 1)
}
#> List of 2
#>  $ UseOfForce_DetailedDataset_2020-2022.csv       :'data.frame': 168 obs. of  5 variables:
#>  $ UseofForce_AgrregateSummaryByYear_2020-2022.csv:'data.frame': 7 obs. of  5 variables:

# Unknown / non-dictionary slug: informative message, returns NULL.
morie_data_dictionary("no_such_dictionary")
#> No dictionary bundled for 'no_such_dictionary'. Rows with kind == "dictionary" in morie_data_catalog() list the ones available.
```
