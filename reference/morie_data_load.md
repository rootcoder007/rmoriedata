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
# Load a bundled lookup table by its slug.
iucr <- morie_data_load("chicago_iucr_codes")
str(iucr)
#> 'data.frame':    410 obs. of  5 variables:
#>  $ iucr                 : chr  "031A" "031B" "033A" "033B" ...
#>  $ primary_description  : chr  "ROBBERY" "ROBBERY" "ROBBERY" "ROBBERY" ...
#>  $ secondary_description: chr  "ARMED - HANDGUN" "ARMED - OTHER FIREARM" "ATTEMPT ARMED - HANDGUN" "ATTEMPT ARMED - OTHER FIREARM" ...
#>  $ index_code           : chr  "I" "I" "I" "I" ...
#>  $ active               : chr  "True" "True" "True" "True" ...
head(iucr)
#>   iucr primary_description         secondary_description index_code active
#> 1 031A             ROBBERY               ARMED - HANDGUN          I   True
#> 2 031B             ROBBERY         ARMED - OTHER FIREARM          I   True
#> 3 033A             ROBBERY       ATTEMPT ARMED - HANDGUN          I   True
#> 4 033B             ROBBERY ATTEMPT ARMED - OTHER FIREARM          I   True
#> 5 041A             BATTERY          AGGRAVATED - HANDGUN          I   True
#> 6 041B             BATTERY    AGGRAVATED - OTHER FIREARM          I   True

# Any slug from the catalogue works the same way.
hoods   <- morie_data_load("chicago_neighborhoods")
offense <- morie_data_load("nyc_nypd_offense_codes")
nrow(hoods); nrow(offense)
#> [1] 98
#> [1] 246

# Slugs are validated: an unknown one errors with guidance.
try(morie_data_load("no_such_dataset"))
#> Error : No dataset 'no_such_dataset'. See morie_data_catalog() for valid slugs.

# Pattern: pick a slug programmatically from the catalogue, then load it.
cat  <- morie_data_catalog()
slug <- cat$slug[cat$kind == "table"][1]
head(morie_data_load(slug))
#>     SECTION         CATEGORY UNITS.OF.MEASURE YEAR_2020 YEAR_2021 YEAR_2022
#> 1 SYNTHETIC synth_category_1            count       100       110       120
#> 2 SYNTHETIC synth_category_2            count       200       220       240
#> 3 SYNTHETIC synth_category_3            count       300       330       360
#> 4 SYNTHETIC synth_category_4            count       400       440       480
#> 5 SYNTHETIC synth_category_5            count       500       550       600
```
