# Victorian crime statistics (Crime Statistics Agency Victoria)

Ten tables from the Crime Statistics Agency's "Latest Victorian crime
data" release, bundled in the Parquet store and reached by slug through
[`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md).
Each is Table 01 – the headline series – of the corresponding published
workbook, for the year ending March 2026.

## Details

- `vic_criminal_incidents`:

  Criminal incidents by offence division, subdivision and subgroup, with
  rate per 100,000.

- `vic_recorded_offences`:

  Recorded offences on the same offence hierarchy.

- `vic_victim_reports`:

  Victim reports by offence.

- `vic_alleged_offender_incidents`:

  Alleged offender incidents, including age and sex breakdowns.

- `vic_family_incidents`:

  Family incidents by category and outcome.

- `vic_lga_criminal_incidents`, `vic_lga_victim_reports`,
  `vic_lga_family_incidents`:

  The same measures by police region and Local Government Area.

- `vic_indigenous_victim_reports`, `vic_indigenous_family_incidents`:

  Aboriginal and/or Torres Strait Islander status breakdowns, as
  published.

The workbooks are .xlsx. They were read with rmorie's native reader, so
the bundled data comes through the same code path a user hits – no
readxl or openxlsx dependency, and no second parser that could disagree
with the first. Rebuild with `data-raw/build_vic_tables.R`.

Counts are as published by the CSA and are subject to its own revisions:
figures for a given year change between releases as incidents are
reclassified, so a table bundled here is a snapshot of the March 2026
release, not a permanent record of that year.

## Source

Crime Statistics Agency Victoria, "Latest Victorian crime data".
<https://www.crimestatistics.vic.gov.au/crime-statistics/latest-victorian-crime-data>
Released under CC BY 4.0.

## See also

[`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md),
[`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md)

## Examples

``` r
# Every bundled Victorian table, by slug.
cat <- morie_data_catalog()
cat[grepl("^vic_", cat$slug), c("slug", "n_rows", "n_cols")]
#>                                slug n_rows n_cols
#> 97   vic_alleged_offender_incidents    740      8
#> 98           vic_criminal_incidents   1120      7
#> 99             vic_family_incidents     60      6
#> 100 vic_indigenous_family_incidents    630      6
#> 101   vic_indigenous_victim_reports    405      7
#> 102      vic_lga_criminal_incidents    870      6
#> 103        vic_lga_family_incidents    435      6
#> 104          vic_lga_victim_reports    870      6
#> 105           vic_recorded_offences   1129      7
#> 106              vic_victim_reports    300      7

# Headline criminal-incident series.
ci <- morie_data_load("vic_criminal_incidents")
str(ci)
#> 'data.frame':    1120 obs. of  7 variables:
#>  $ Year                       : int  2026 2026 2026 2026 2026 2026 2026 2026 2026 2026 ...
#>  $ Year ending                : chr  "March" "March" "March" "March" ...
#>  $ Offence Division           : chr  "A Crimes against the person" "A Crimes against the person" "A Crimes against the person" "A Crimes against the person" ...
#>  $ Offence Subdivision        : chr  "A10 Homicide and related offences" "A10 Homicide and related offences" "A10 Homicide and related offences" "A10 Homicide and related offences" ...
#>  $ Offence Subgroup           : chr  "A11 Murder" "A12 Attempted murder" "A14 Manslaughter & A13  Accessory/ conspiracy to murder" "A15 Driving causing death" ...
#>  $ Incidents Recorded         : int  53 29 9 111 10362 8385 2297 13139 13202 3990 ...
#>  $ Rate per 100,000 population: num  0.736 0.403 0.125 1.542 143.988 ...

# Incidents by offence division for the most recent year.
latest <- ci[ci$Year == max(ci$Year), ]
tapply(latest[["Incidents Recorded"]], latest[["Offence Division"]], sum)
#>          A Crimes against the person    B Property and deception offences 
#>                                75713                               296561 
#>                      C Drug offences D Public order and security offences 
#>                                15446                                17037 
#>        E Justice procedures offences                     F Other offences 
#>                                63280                                  674 
```
