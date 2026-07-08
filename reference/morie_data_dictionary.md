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
dicts <- morie_data_catalog()
subset(dicts, kind == "dictionary", "slug")
#>                          slug
#> 56 arsau_2020_2022_dictionary
#> 57      arsau_2023_dictionary
#> 58      arsau_2024_dictionary
#> 59 corrections_uof_dictionary
#> 60            otis_dictionary
#> 61             tps_dictionary
#> 62             uof_dictionary
```
