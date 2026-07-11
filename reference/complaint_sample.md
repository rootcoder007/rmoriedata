# Chicago reported-crime sample ("complaints")

A CRAN-safe slice of the City of Chicago "Crimes – 2001 to present"
dataset (reported incidents), filtered to geocoded rows from 2020
onward. For the full dataset use
`load_chicago_data("complaints", full = TRUE)`.

## Usage

``` r
complaint_sample
```

## Format

A base `data.frame` with up to 25,000 rows and 16 columns:

- case_number:

  Chicago PD records-division number (character).

- date_iso:

  Incident timestamp as an ISO-8601 string with offset (lossless across
  R/Python).

- date:

  Incident timestamp as `POSIXct` (America/Chicago).

- iucr:

  Illinois Uniform Crime Reporting code (character).

- primary_type:

  Primary FBI crime classification.

- description:

  Secondary description of the offense.

- arrest:

  Whether an arrest was made (logical).

- domestic:

  Whether domestic-violence related (logical).

- beat,district,ward,community_area:

  Geographic area codes (integer).

- fbi_code:

  FBI crime code (character).

- year:

  Year of the incident (integer).

- latitude,longitude:

  WGS84 coordinates (numeric).

## Source

City of Chicago Open Data Portal, "Crimes - 2001 to present" (dataset
`ijzp-q8t2`). <https://data.cityofchicago.org/>

## See also

[`load_chicago_data`](https://rootcoder007.github.io/rmoriedata/reference/load_chicago_data.md)

## Examples

``` r
data(complaint_sample)
nrow(complaint_sample)
#> [1] 25000
head(sort(table(complaint_sample$primary_type), decreasing = TRUE), 5)
#> 
#>           THEFT         BATTERY CRIMINAL DAMAGE         ASSAULT   OTHER OFFENSE 
#>            5825            4800            2362            1975            1760 
```
