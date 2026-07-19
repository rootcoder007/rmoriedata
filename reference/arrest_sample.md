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
dim(arrest_sample)
#> [1] 25000     8
str(arrest_sample)
#> 'data.frame':    25000 obs. of  8 variables:
#>  $ case_number   : chr  "HX100013" "HW590668" "HW580083" "HX100033" ...
#>  $ date_iso      : chr  "2014-01-01T00:02:00-0600" "2014-01-01T00:40:00-0600" "2014-01-01T00:20:00-0600" "2014-01-01T00:35:00-0600" ...
#>  $ date          : POSIXct, format: "2014-01-01 00:02:00" "2014-01-01 00:40:00" ...
#>  $ race          : chr  "BLACK" "BLACK" "BLACK" "BLACK" ...
#>  $ charge_type   : chr  "F" "M" "M" "F" ...
#>  $ charge_class  : chr  "3" "A" "A" "4" ...
#>  $ charge_desc   : chr  "UUW - WEAPON - FELON, POSSESS/USE FIREARM" "AGG ASSAULT HANDICAPPED/60+" "DOMESTIC BATTERY - PHYSICAL CONTACT" "RECKLESS DISCH FIREARM - ENDANGER" ...
#>  $ charge_statute: chr  "720 ILCS 5.0/24-1.1-A" "720 ILCS 5.0/12-2-B-1" "720 ILCS 5.0/12-3.2-A-2" "720 ILCS 5.0/24-1.5-A" ...

# Recorded race distribution.
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

# Charge severity (F = felony, M = misdemeanour, ...).
sort(table(arrest_sample$charge_type), decreasing = TRUE)
#> 
#>     M           F 
#> 12342  6464  6194 

# Most frequent primary charges.
head(sort(table(arrest_sample$charge_desc), decreasing = TRUE), 5)
#> 
#>                               ISSUANCE OF WARRANT 
#>                                              3403 
#> PCS - POSSESSION - POSS AMT CON SUB EXCEPT (A)(D) 
#>                                              2401 
#>                      DRIVING ON SUSPENDED LICENSE 
#>                                              1151 
#>                         CRIMINAL TRESPASS TO LAND 
#>                                               987 
#>                    DOMESTIC BATTERY - BODILY HARM 
#>                                               770 

# Cross-tab race x charge type.
with(arrest_sample, table(race, charge_type))
#>                               charge_type
#> race                                   F    M
#>   AMER INDIAN / ALASKAN NATIVE    6    3    7
#>   ASIAN / PACIFIC ISLANDER       26   22   87
#>   BLACK                        4938 4600 8445
#>   BLACK HISPANIC                 21   28   71
#>   UNKNOWN / REFUSED               9    7   22
#>   WHITE                         579  584 1268
#>   WHITE HISPANIC                885  950 2442
```
