# Data dictionary for a bundled dataset

Data dictionary for a bundled dataset

## Usage

``` r
morie_data_dictionary(slug)
```

## Arguments

- slug:

  Dictionary slug; rows with `kind == "dictionary"` in
  [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md)
  list them.

## Value

The dictionary as JSON text (a length-one character vector), or `NULL`
invisibly with a message when none is bundled.

## Examples

``` r
d <- morie_data_dictionary("arsau_2023_dictionary")
substr(d, 1, 60)
#> [1] "{\n  \"UoF_Main_Records\": [\n    {\n      \"var\": \"Id_\",\n      \"l"
```
