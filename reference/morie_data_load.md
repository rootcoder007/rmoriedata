# Load a bundled dataset by slug

Load a bundled dataset by slug

## Usage

``` r
morie_data_load(slug)
```

## Arguments

- slug:

  Dataset slug; see the \`slug\` column of \[morie_data_catalog()\].

## Value

A \`data.frame\`.

## See also

\[morie_data_catalog()\]

## Examples

``` r
if (requireNamespace("RSQLite", quietly = TRUE)) {
  df <- morie_data_load("chicago_iucr_codes")
  str(df)
}
#> 'data.frame':    410 obs. of  5 variables:
#>  $ iucr                 : chr  "031A" "031B" "033A" "033B" ...
#>  $ primary_description  : chr  "ROBBERY" "ROBBERY" "ROBBERY" "ROBBERY" ...
#>  $ secondary_description: chr  "ARMED - HANDGUN" "ARMED - OTHER FIREARM" "ATTEMPT ARMED - HANDGUN" "ATTEMPT ARMED - OTHER FIREARM" ...
#>  $ index_code           : chr  "I" "I" "I" "I" ...
#>  $ active               : chr  "True" "True" "True" "True" ...
```
