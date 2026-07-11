# Chicago arrests sample

A CRAN-safe slice of the City of Chicago "Arrests" dataset. For the full
~1.5M-row dataset use `load_chicago_data("arrests", full = TRUE)`.

## Usage

``` r
arrest_sample
```

## Format

A base `data.frame` with up to 25,000 rows and 8 columns:

- case_number:

  Chicago PD records-division number (character).

- date_iso:

  Arrest timestamp as an ISO-8601 string with offset.

- date:

  Arrest timestamp as `POSIXct` (America/Chicago).

- race:

  Recorded race of the arrestee (character).

- charge_type:

  Charge type of the primary charge (F/M/etc.).

- charge_class:

  Charge class of the primary charge.

- charge_desc:

  Description of the primary charge.

- charge_statute:

  Statute of the primary charge.

## Source

City of Chicago Open Data Portal, "Arrests" (dataset `dpt3-jri9`).
<https://data.cityofchicago.org/>

## See also

[`load_chicago_data`](https://rootcoder007.github.io/rmoriedata/reference/load_chicago_data.md)

## Examples

``` r
data(arrest_sample)
nrow(arrest_sample)
#> [1] 25000
sort(table(arrest_sample$race), decreasing = TRUE)
#> 
#>                        BLACK               WHITE HISPANIC 
#>                        17983                         4277 
#>                        WHITE     ASIAN / PACIFIC ISLANDER 
#>                         2431                          135 
#>               BLACK HISPANIC            UNKNOWN / REFUSED 
#>                          120                           38 
#> AMER INDIAN / ALASKAN NATIVE 
#>                           16 
```
