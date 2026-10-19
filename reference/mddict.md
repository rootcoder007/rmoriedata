# Data dictionary for a bundled dataset

Data dictionary for a bundled dataset

## Usage

``` r
mddict(slug)
```

## Arguments

- slug:

  Dictionary slug; rows with `kind == "dictionary"` in
  [`mdcat()`](https://rootcoder007.github.io/rmoriedata/reference/mdcat.md)
  list them.

## Value

The dictionary as JSON text (a length-one character vector), or `NULL`
invisibly with a message when none is bundled.

## Examples

``` r
d <- mddict("arsau_2023_dictionary")
substr(d, 1, 60)
#> [1] "{\n  \"UoF_Main_Records\": [\n    {\n      \"var\": \"Id_\",\n      \"l"
```
