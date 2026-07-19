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
dim(complaint_sample)
#> [1] 25000    16
str(complaint_sample)
#> 'data.frame':    25000 obs. of  16 variables:
#>  $ case_number   : chr  "JA495186" "JD100164" "JD100108" "JD100028" ...
#>  $ date_iso      : chr  "2021-05-21T00:01:00-0500" "2020-01-01T02:40:00-0600" "2020-01-01T01:17:00-0600" "2020-01-01T00:24:00-0600" ...
#>  $ date          : POSIXct, format: "2021-05-21 00:01:00" "2020-01-01 02:40:00" ...
#>  $ iucr          : chr  "1752" "031A" "0470" "0486" ...
#>  $ primary_type  : chr  "OFFENSE INVOLVING CHILDREN" "ROBBERY" "PUBLIC PEACE VIOLATION" "BATTERY" ...
#>  $ description   : chr  "AGGRAVATED CRIMINAL SEXUAL ABUSE BY FAMILY MEMBER" "ARMED: HANDGUN" "RECKLESS CONDUCT" "DOMESTIC BATTERY SIMPLE" ...
#>  $ arrest        : logi  FALSE FALSE TRUE TRUE TRUE FALSE ...
#>  $ domestic      : logi  TRUE FALSE FALSE TRUE FALSE FALSE ...
#>  $ beat          : int  2534 715 431 1723 533 413 1235 631 2211 1812 ...
#>  $ district      : int  25 7 4 17 5 4 12 6 22 18 ...
#>  $ ward          : int  35 16 7 33 9 8 11 6 19 43 ...
#>  $ community_area: int  20 67 51 14 54 47 31 44 74 7 ...
#>  $ fbi_code      : chr  "17" "03" "24" "08B" ...
#>  $ year          : int  2021 2020 2020 2020 2020 2020 2020 2020 2020 2020 ...
#>  $ latitude      : num  41.9 41.8 41.7 42 41.7 ...
#>  $ longitude     : num  -87.7 -87.7 -87.6 -87.7 -87.6 ...

# Most common offense types.
head(sort(table(complaint_sample$primary_type), decreasing = TRUE), 5)
#> 
#>           THEFT         BATTERY CRIMINAL DAMAGE         ASSAULT   OTHER OFFENSE 
#>            5825            4800            2362            1975            1760 

# Arrest rate among reported incidents.
mean(complaint_sample$arrest)
#> [1] 0.23576

# Incidents per year (the sample spans 2020+).
table(complaint_sample$year)
#> 
#>  2020  2021 
#> 24999     1 

# Domestic-violence-flagged incidents by type.
head(sort(table(complaint_sample$primary_type[complaint_sample$domestic]),
          decreasing = TRUE), 3)
#> 
#>       BATTERY OTHER OFFENSE       ASSAULT 
#>          2785           608           590 
```
