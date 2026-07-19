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
#>   REPORTING_YEAR      RECORD_ID  POLICE_SERVICE REPORT_TYPE TEAM_TYPE
#> 1           2020 SYNTH-DET-1001 Sample Regional      Person        NA
#> 2           2021 SYNTH-DET-1002             OPP      Person        NA
#> 3           2022 SYNTH-DET-1003 Sample Regional      Animal        NA
#> 4           2021 SYNTH-DET-1004             OPP      Person        NA
#> 5           2022 SYNTH-DET-1005 Sample Regional      Weapon        NA
#>   NUMBER_POLICE_OFFICERS_INVOLVED ASSIGNMENT_TYPE TYPE_INCIDENT_ALARM
#> 1                              NA              NA                  NA
#> 2                              NA              NA                  NA
#> 3                              NA              NA                  NA
#> 4                              NA              NA                  NA
#> 5                              NA              NA                  NA
#>   TYPE_INCIDENT_BREAK_ENTER TYPE_INCIDENT_DOMESTIC_DISTURBANCE
#> 1                        NA                                 NA
#> 2                        NA                                 NA
#> 3                        NA                                 NA
#> 4                        NA                                 NA
#> 5                        NA                                 NA
#>   TYPE_INCIDENT_HOMICIDE TYPE_INCIDENT_OTHER_DISTURBANCE TYPE_INCIDENT_ROBBERY
#> 1                     NA                              NA                    NA
#> 2                     NA                              NA                    NA
#> 3                     NA                              NA                    NA
#> 4                     NA                              NA                    NA
#> 5                     NA                              NA                    NA
#>   TYPE_INCIDENT_SERIOUS_INJURY TYPE_INCIDENT_SUSPICIOUS_PERSON
#> 1                           NA                              NA
#> 2                           NA                              NA
#> 3                           NA                              NA
#> 4                           NA                              NA
#> 5                           NA                              NA
#>   TYPE_INCIDENT_TRAFFIC TYPE_INCIDENT_WEAPONS_CALL TYPE_INCIDENT_OTHER
#> 1                    NA                         NA                  NA
#> 2                    NA                         NA                  NA
#> 3                    NA                         NA                  NA
#> 4                    NA                         NA                  NA
#> 5                    NA                         NA                  NA
#>   POLICE_PRESENCE NUMBER_OF_POLICE_PRESENT ATTIRE NUMBER_OF_SUBJECTS
#> 1              NA                       NA     NA                 NA
#> 2              NA                       NA     NA                 NA
#> 3              NA                       NA     NA                 NA
#> 4              NA                       NA     NA                 NA
#> 5              NA                       NA     NA                 NA
#>   RACE_SUB_ONE RACE_SUB_TWO RACE_SUB_THREE RACE TYPE_FORCE_FIREARM_DISCHARGED
#> 1           NA           NA             NA   NA                            NA
#> 2           NA           NA             NA   NA                            NA
#> 3           NA           NA             NA   NA                            NA
#> 4           NA           NA             NA   NA                            NA
#> 5           NA           NA             NA   NA                            NA
#>   TYPE_FORCE_FIREARM_DISCHARGED_RANK
#> 1                                 NA
#> 2                                 NA
#> 3                                 NA
#> 4                                 NA
#> 5                                 NA
#>   TYPE_FORCE_FIREARM_DISCHARGED_FORCE_EFFECTIVE
#> 1                                            NA
#> 2                                            NA
#> 3                                            NA
#> 4                                            NA
#> 5                                            NA
#>   TYPE_FORCE_FIREARM_POINTED_UNKNOWN TYPE_FORCE_FIREARM_POINTED_AT_PERSON_RANK
#> 1                                 NA                                        NA
#> 2                                 NA                                        NA
#> 3                                 NA                                        NA
#> 4                                 NA                                        NA
#> 5                                 NA                                        NA
#>   TYPE_FORCE_FIREARM_POINTED_AT_PERSON_FORCE_EFFECTIVE TYPE_FORCE_HANDGUN_DRAWN
#> 1                                                   NA                       NA
#> 2                                                   NA                       NA
#> 3                                                   NA                       NA
#> 4                                                   NA                       NA
#> 5                                                   NA                       NA
#>   TYPE_FORCE_HANDGUN_DRAWN_RANK TYPE_FORCE_HANDGUN_DRAWN_FORCE_EFFECTIVE
#> 1                            NA                                       NA
#> 2                            NA                                       NA
#> 3                            NA                                       NA
#> 4                            NA                                       NA
#> 5                            NA                                       NA
#>   TYPE_FORCE_LLF_DISCHARGED TYPE_FORCE_LLF_POINTED_UNKNOWN TYPE_FORCE_CEW
#> 1                        NA                             NA             NA
#> 2                        NA                             NA             NA
#> 3                        NA                             NA             NA
#> 4                        NA                             NA             NA
#> 5                        NA                             NA             NA
#>   TYPE_FORCE_IMPACT_WEAPON_HARD TYPE_FORCE_IMPACT_WEAPON_HARD_RANK
#> 1                            NA                                 NA
#> 2                            NA                                 NA
#> 3                            NA                                 NA
#> 4                            NA                                 NA
#> 5                            NA                                 NA
#>   TYPE_FORCE_IMPACT_WEAPON_HARD_FORCE_EFFECTIVE TYPE_FORCE_IMPACT_WEAPON_SOFT
#> 1                                            NA                            NA
#> 2                                            NA                            NA
#> 3                                            NA                            NA
#> 4                                            NA                            NA
#> 5                                            NA                            NA
#>   TYPE_FORCE_IMPACT_WEAPON_SOFT_RANK
#> 1                                 NA
#> 2                                 NA
#> 3                                 NA
#> 4                                 NA
#> 5                                 NA
#>   TYPE_FORCE_IMPACT_WEAPON_SOFT_FORCE_EFFECTIVE TYPE_FORCE_AEROSOL
#> 1                                            NA                 NA
#> 2                                            NA                 NA
#> 3                                            NA                 NA
#> 4                                            NA                 NA
#> 5                                            NA                 NA
#>   TYPE_FORCE_AEROSOL_WEAPON_RANK TYPE_FORCE_AEROSOL_WEAPON_FORCE_EFFECTIVE
#> 1                             NA                                        NA
#> 2                             NA                                        NA
#> 3                             NA                                        NA
#> 4                             NA                                        NA
#> 5                             NA                                        NA
#>   TYPE_FORCE_EMPTY_HAND_HARD TYPE_FORCE_EMPTY_HAND_TECHNIQUES_HARD_RANK
#> 1                         NA                                         NA
#> 2                         NA                                         NA
#> 3                         NA                                         NA
#> 4                         NA                                         NA
#> 5                         NA                                         NA
#>   TYPE_FORCE_EMPTY_HAND_TECHNIQUES_HARD_FORCE_EFFECTIVE
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   TYPE_FORCE_EMPTY_HAND_SOFT TYPE_FORCE_EMPTY_HAND_TECHNIQUES_SOFT_RANK
#> 1                         NA                                         NA
#> 2                         NA                                         NA
#> 3                         NA                                         NA
#> 4                         NA                                         NA
#> 5                         NA                                         NA
#>   TYPE_FORCE_EMPTY_HAND_TECHNIQUES_SOFT_FORCE_EFFECTIVE
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   TYPE_FORCE_PHYSICAL_FORCE TYPE_FORCE_OTHER TYPE_FORCE_OTHER_RANK
#> 1                        NA               NA                    NA
#> 2                        NA               NA                    NA
#> 3                        NA               NA                    NA
#> 4                        NA               NA                    NA
#> 5                        NA               NA                    NA
#>   TYPE_FORCE_OTHER_FORCE_EFFECTIVE REASON_FORCE_EFFECT_ARREST
#> 1                               NA                         NA
#> 2                               NA                         NA
#> 3                               NA                         NA
#> 4                               NA                         NA
#> 5                               NA                         NA
#>   REASON_FORCE_PROTECT_SELF REASON_FORCE_PROTECT_PUBLIC
#> 1                        NA                          NA
#> 2                        NA                          NA
#> 3                        NA                          NA
#> 4                        NA                          NA
#> 5                        NA                          NA
#>   REASON_FORCE_PREVENT_ESCAPE REASON_FORCE_ACCIDENTAL
#> 1                          NA                      NA
#> 2                          NA                      NA
#> 3                          NA                      NA
#> 4                          NA                      NA
#> 5                          NA                      NA
#>   REASON_FORCE_PREVENT_COMMISSION_OF_OFFENCE REASON_FORCE_PROTECT_OTHER_OFFICER
#> 1                                         NA                                 NA
#> 2                                         NA                                 NA
#> 3                                         NA                                 NA
#> 4                                         NA                                 NA
#> 5                                         NA                                 NA
#>   REASON_FORCE_PROTECT_SUBJECT REASON_FORCE_OTHER TYPE_FIREARM_REVOLVER_CHECK
#> 1                           NA                 NA                          NA
#> 2                           NA                 NA                          NA
#> 3                           NA                 NA                          NA
#> 4                           NA                 NA                          NA
#> 5                           NA                 NA                          NA
#>   TYPE_FIREARM_REVOLVER_NUMBER_ROUNDS TYPE_FIREARM_RIFLE_CHECK
#> 1                                  NA                       NA
#> 2                                  NA                       NA
#> 3                                  NA                       NA
#> 4                                  NA                       NA
#> 5                                  NA                       NA
#>   TYPE_FIREARM_RIFLE_NUMBER_ROUNDS TYPE_FIREARM_SEMI_AUTOMATIC_CHECK
#> 1                               NA                                NA
#> 2                               NA                                NA
#> 3                               NA                                NA
#> 4                               NA                                NA
#> 5                               NA                                NA
#>   TYPE_FIREARM_SEMI_AUTOMATIC_NUMBER_ROUNDS TYPE_FIREARM_SHOTGUN_CHECK
#> 1                                        NA                         NA
#> 2                                        NA                         NA
#> 3                                        NA                         NA
#> 4                                        NA                         NA
#> 5                                        NA                         NA
#>   TYPE_FIREARM_SHOTGUN_NUMBER_ROUNDS TYPE_FIREARM_OTHER_CHECK
#> 1                                 NA                       NA
#> 2                                 NA                       NA
#> 3                                 NA                       NA
#> 4                                 NA                       NA
#> 5                                 NA                       NA
#>   TYPE_FIREARM_OTHER_NUMBER_ROUNDS DIST_SUB_ONE DIST_SUB_TWO DIST_SUB_THREE
#> 1                               NA           NA           NA             NA
#> 2                               NA           NA           NA             NA
#> 3                               NA           NA           NA             NA
#> 4                               NA           NA           NA             NA
#> 5                               NA           NA           NA             NA
#>   ALTERNATIVE_STRATEGIES_CONCEALMENT ALTERNATIVE_STRATEGIES_COVER
#> 1                                 NA                           NA
#> 2                                 NA                           NA
#> 3                                 NA                           NA
#> 4                                 NA                           NA
#> 5                                 NA                           NA
#>   ALTERNATIVE_STRATEGIES_VERBAL_INTERACTION ALTERNATIVE_STRATEGIES_OTHER
#> 1                                        NA                           NA
#> 2                                        NA                           NA
#> 3                                        NA                           NA
#> 4                                        NA                           NA
#> 5                                        NA                           NA
#>   WEAPONS_CARRIED_SUBJECT_BASEBALL_BAT_CLUB_SUBJECT_ONE
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   WEAPONS_CARRIED_SUBJECT_BASEBALL_BAT_CLUB_SUBJECT_TWO
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   WEAPONS_CARRIED_SUBJECT_BASEBALL_BAT_CLUB_SUBJECT_THREE
#> 1                                                      NA
#> 2                                                      NA
#> 3                                                      NA
#> 4                                                      NA
#> 5                                                      NA
#>   WEAPONS_CARRIED_SUBJECT_KNIFE_EDGED_WEAPON_SUBJECT_ONE
#> 1                                                     NA
#> 2                                                     NA
#> 3                                                     NA
#> 4                                                     NA
#> 5                                                     NA
#>   WEAPONS_CARRIED_SUBJECT_KNIFE_EDGED_WEAPON_SUBJECT_TWO
#> 1                                                     NA
#> 2                                                     NA
#> 3                                                     NA
#> 4                                                     NA
#> 5                                                     NA
#>   WEAPONS_CARRIED_SUBJECT_KNIFE_EDGED_WEAPON_SUBJECT_THREE
#> 1                                                       NA
#> 2                                                       NA
#> 3                                                       NA
#> 4                                                       NA
#> 5                                                       NA
#>   WEAPONS_CARRIED_SUBJECT_REVOLVER_SUBJECT_ONE
#> 1                                           NA
#> 2                                           NA
#> 3                                           NA
#> 4                                           NA
#> 5                                           NA
#>   WEAPONS_CARRIED_SUBJECT_REVOLVER_SUBJECT_TWO
#> 1                                           NA
#> 2                                           NA
#> 3                                           NA
#> 4                                           NA
#> 5                                           NA
#>   WEAPONS_CARRIED_SUBJECT_REVOLVER_SUBJECT_THREE
#> 1                                             NA
#> 2                                             NA
#> 3                                             NA
#> 4                                             NA
#> 5                                             NA
#>   WEAPONS_CARRIED_SUBJECT_RIFLE_SUBJECT_ONE
#> 1                                        NA
#> 2                                        NA
#> 3                                        NA
#> 4                                        NA
#> 5                                        NA
#>   WEAPONS_CARRIED_SUBJECT_RIFLE_SUBJECT_TWO
#> 1                                        NA
#> 2                                        NA
#> 3                                        NA
#> 4                                        NA
#> 5                                        NA
#>   WEAPONS_CARRIED_SUBJECT_RIFLE_SUBJECT_THREE
#> 1                                          NA
#> 2                                          NA
#> 3                                          NA
#> 4                                          NA
#> 5                                          NA
#>   WEAPONS_CARRIED_SUBJECT_SEMI_AUTOMATIC_SUBJECT_ONE
#> 1                                                 NA
#> 2                                                 NA
#> 3                                                 NA
#> 4                                                 NA
#> 5                                                 NA
#>   WEAPONS_CARRIED_SUBJECT_SEMI_AUTOMATIC_SUBJECT_TWO
#> 1                                                 NA
#> 2                                                 NA
#> 3                                                 NA
#> 4                                                 NA
#> 5                                                 NA
#>   WEAPONS_CARRIED_SUBJECT_SEMI_AUTOMATIC_SUBJECT_THREE
#> 1                                                   NA
#> 2                                                   NA
#> 3                                                   NA
#> 4                                                   NA
#> 5                                                   NA
#>   WEAPONS_CARRIED_SUBJECT_SHOTGUN_SUBJECT_ONE
#> 1                                          NA
#> 2                                          NA
#> 3                                          NA
#> 4                                          NA
#> 5                                          NA
#>   WEAPONS_CARRIED_SUBJECT_SHOTGUN_SUBJECT_TWO
#> 1                                          NA
#> 2                                          NA
#> 3                                          NA
#> 4                                          NA
#> 5                                          NA
#>   WEAPONS_CARRIED_SUBJECT_SHOTGUN_SUBJECT_THREE
#> 1                                            NA
#> 2                                            NA
#> 3                                            NA
#> 4                                            NA
#> 5                                            NA
#>   WEAPONS_CARRIED_SUBJECT_NONE_SUBJECT_ONE
#> 1                                       NA
#> 2                                       NA
#> 3                                       NA
#> 4                                       NA
#> 5                                       NA
#>   WEAPONS_CARRIED_SUBJECT_NONE_SUBJECT_TWO
#> 1                                       NA
#> 2                                       NA
#> 3                                       NA
#> 4                                       NA
#> 5                                       NA
#>   WEAPONS_CARRIED_SUBJECT_NONE_SUBJECT_THREE
#> 1                                         NA
#> 2                                         NA
#> 3                                         NA
#> 4                                         NA
#> 5                                         NA
#>   WEAPONS_CARRIED_SUBJECT_UNKNOWN_SUBJECT_ONE
#> 1                                          NA
#> 2                                          NA
#> 3                                          NA
#> 4                                          NA
#> 5                                          NA
#>   WEAPONS_CARRIED_SUBJECT_UNKNOWN_SUBJECT_TWO
#> 1                                          NA
#> 2                                          NA
#> 3                                          NA
#> 4                                          NA
#> 5                                          NA
#>   WEAPONS_CARRIED_SUBJECT_UNKNOWN_SUBJECT_THREE
#> 1                                            NA
#> 2                                            NA
#> 3                                            NA
#> 4                                            NA
#> 5                                            NA
#>   WEAPONS_CARRIED_SUBJECT_OTHER_SUBJECT_ONE
#> 1                                        NA
#> 2                                        NA
#> 3                                        NA
#> 4                                        NA
#> 5                                        NA
#>   WEAPONS_CARRIED_SUBJECT_OTHER_SUBJECT_TWO
#> 1                                        NA
#> 2                                        NA
#> 3                                        NA
#> 4                                        NA
#> 5                                        NA
#>   WEAPONS_CARRIED_SUBJECT_OTHER_SUBJECT_THREE WEAPONS_CARRIED_FIREARM
#> 1                                          NA                      NA
#> 2                                          NA                      NA
#> 3                                          NA                      NA
#> 4                                          NA                      NA
#> 5                                          NA                      NA
#>   WEAPONS_CARRIED_KNIFE_EDGED_WEAPON WEAPONS_CARRIED_IMPACT_WEAPON
#> 1                                 NA                            NA
#> 2                                 NA                            NA
#> 3                                 NA                            NA
#> 4                                 NA                            NA
#> 5                                 NA                            NA
#>   WEAPONS_CARRIED_UNARMED WEAPONS_CARRIED_UNKNOWN_WEAPON
#> 1                      NA                             NA
#> 2                      NA                             NA
#> 3                      NA                             NA
#> 4                      NA                             NA
#> 5                      NA                             NA
#>   WEAPONS_CARRIED_OTHER_WEAPON LOCATION_SUBJECT_WEAPONS_AT_HAND_SUBJECT_ONE
#> 1                           NA                                           NA
#> 2                           NA                                           NA
#> 3                           NA                                           NA
#> 4                           NA                                           NA
#> 5                           NA                                           NA
#>   LOCATION_SUBJECT_WEAPONS_AT_HAND_SUBJECT_TWO
#> 1                                           NA
#> 2                                           NA
#> 3                                           NA
#> 4                                           NA
#> 5                                           NA
#>   LOCATION_SUBJECT_WEAPONS_AT_HAND_SUBJECT_THREE
#> 1                                             NA
#> 2                                             NA
#> 3                                             NA
#> 4                                             NA
#> 5                                             NA
#>   LOCATION_SUBJECT_WEAPONS_CONCEALED_PERSON_SUBJECT_ONE
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   LOCATION_SUBJECT_WEAPONS_CONCEALED_PERSON_SUBJECT_TWO
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   LOCATION_SUBJECT_WEAPONS_CONCEALED_PERSON_SUBJECT_THREE
#> 1                                                      NA
#> 2                                                      NA
#> 3                                                      NA
#> 4                                                      NA
#> 5                                                      NA
#>   LOCATION_SUBJECT_WEAPONS_IN_HAND_SUBJECT_ONE
#> 1                                           NA
#> 2                                           NA
#> 3                                           NA
#> 4                                           NA
#> 5                                           NA
#>   LOCATION_SUBJECT_WEAPONS_IN_HAND_SUBJECT_TWO
#> 1                                           NA
#> 2                                           NA
#> 3                                           NA
#> 4                                           NA
#> 5                                           NA
#>   LOCATION_SUBJECT_WEAPONS_IN_HAND_SUBJECT_THREE
#> 1                                             NA
#> 2                                             NA
#> 3                                             NA
#> 4                                             NA
#> 5                                             NA
#>   TOTAL_ROUNDS_FIRED_ALL_SUBJECTS LOCATION_INCIDENT_OUTDOOR_LANEWAY
#> 1                              NA                                NA
#> 2                              NA                                NA
#> 3                              NA                                NA
#> 4                              NA                                NA
#> 5                              NA                                NA
#>   LOCATION_INCIDENT_OUTDOOR_MOTOR_VEHICLE LOCATION_INCIDENT_OUTDOOR_PARK
#> 1                                      NA                             NA
#> 2                                      NA                             NA
#> 3                                      NA                             NA
#> 4                                      NA                             NA
#> 5                                      NA                             NA
#>   LOCATION_INCIDENT_OUTDOOR_ROADWAY LOCATION_INCIDENT_OUTDOOR_RURAL
#> 1                                NA                              NA
#> 2                                NA                              NA
#> 3                                NA                              NA
#> 4                                NA                              NA
#> 5                                NA                              NA
#>   LOCATION_INCIDENT_OUTDOOR_YARD LOCATION_INCIDENT_OUTDOOR_OTHER
#> 1                             NA                              NA
#> 2                             NA                              NA
#> 3                             NA                              NA
#> 4                             NA                              NA
#> 5                             NA                              NA
#>   LOCATION_INCIDENT_INDOOR_PRIVATE_PROPERTY_APARTMENT
#> 1                                                  NA
#> 2                                                  NA
#> 3                                                  NA
#> 4                                                  NA
#> 5                                                  NA
#>   LOCATION_INCIDENT_INDOOR_PRIVATE_PROPERTY_HALLWAY
#> 1                                                NA
#> 2                                                NA
#> 3                                                NA
#> 4                                                NA
#> 5                                                NA
#>   LOCATION_INCIDENT_INDOOR_PRIVATE_PROPERTY_HOUSE
#> 1                                              NA
#> 2                                              NA
#> 3                                              NA
#> 4                                              NA
#> 5                                              NA
#>   LOCATION_INCIDENT_INDOOR_PUBLIC_PROPERTY_COMMERCIAL_SITE
#> 1                                                       NA
#> 2                                                       NA
#> 3                                                       NA
#> 4                                                       NA
#> 5                                                       NA
#>   LOCATION_INCIDENT_INDOOR_PUBLIC_PROPERTY_FINANCIAL_INSTITUTION
#> 1                                                             NA
#> 2                                                             NA
#> 3                                                             NA
#> 4                                                             NA
#> 5                                                             NA
#>   LOCATION_INCIDENT_INDOOR_PUBLIC_PROPERTY_PUBLIC_INSTITUTION
#> 1                                                          NA
#> 2                                                          NA
#> 3                                                          NA
#> 4                                                          NA
#> 5                                                          NA
#>   LOCATION_INCIDENT_INDOOR_OTHER WEATHER_CONDITIONS_CLEAR
#> 1                             NA                       NA
#> 2                             NA                       NA
#> 3                             NA                       NA
#> 4                             NA                       NA
#> 5                             NA                       NA
#>   WEATHER_CONDITIONS_CLOUDY WEATHER_CONDITIONS_FOG WEATHER_CONDITIONS_RAIN
#> 1                        NA                     NA                      NA
#> 2                        NA                     NA                      NA
#> 3                        NA                     NA                      NA
#> 4                        NA                     NA                      NA
#> 5                        NA                     NA                      NA
#>   WEATHER_CONDITIONS_SNOW_SLEET WEATHER_CONDITIONS_SUNNY
#> 1                            NA                       NA
#> 2                            NA                       NA
#> 3                            NA                       NA
#> 4                            NA                       NA
#> 5                            NA                       NA
#>   WEATHER_CONDITIONS_OTHER LIGHTING_CONDITIONS_DARK
#> 1                       NA                       NA
#> 2                       NA                       NA
#> 3                       NA                       NA
#> 4                       NA                       NA
#> 5                       NA                       NA
#>   LIGHTING_CONDITIONS_DAYLIGHT LIGHTING_CONDITIONS_DUSK
#> 1                           NA                       NA
#> 2                           NA                       NA
#> 3                           NA                       NA
#> 4                           NA                       NA
#> 5                           NA                       NA
#>   LIGHTING_CONDITIONS_GOOD_ARTIFICIAL_LIGHT
#> 1                                        NA
#> 2                                        NA
#> 3                                        NA
#> 4                                        NA
#> 5                                        NA
#>   LIGHTING_CONDITIONS_POOR_ARTIFICIAL_LIGHT LIGHTING_CONDITIONS_OTHER
#> 1                                        NA                        NA
#> 2                                        NA                        NA
#> 3                                        NA                        NA
#> 4                                        NA                        NA
#> 5                                        NA                        NA
#>   PERSON_INJURED_SELF_MEDICAL_ATTENTION_REQUIRED
#> 1                                             NA
#> 2                                             NA
#> 3                                             NA
#> 4                                             NA
#> 5                                             NA
#>   PERSON_INJURED_SELF_NATURE_INJURIES
#> 1                                  NA
#> 2                                  NA
#> 3                                  NA
#> 4                                  NA
#> 5                                  NA
#>   PERSON_INJURED_OTHER_POLICE_OFFICER_MEDICAL_ATTENTION_REQUIRED
#> 1                                                             NA
#> 2                                                             NA
#> 3                                                             NA
#> 4                                                             NA
#> 5                                                             NA
#>   PERSON_INJURED_OTHER_POLICE_OFFICER_NATURE_INJURIES
#> 1                                                  NA
#> 2                                                  NA
#> 3                                                  NA
#> 4                                                  NA
#> 5                                                  NA
#>   PERSON_INJURED_THIRD_PARTY_MEDICAL_ATTENTION_REQUIRED
#> 1                                                    NA
#> 2                                                    NA
#> 3                                                    NA
#> 4                                                    NA
#> 5                                                    NA
#>   PERSON_INJURED_THIRD_PARTY_NATURE_INJURIES
#> 1                                         NA
#> 2                                         NA
#> 3                                         NA
#> 4                                         NA
#> 5                                         NA
#>   PERSON_INJURED_SUBJECT1_MEDICAL_ATTENTION_REQUIRED
#> 1                                                 NA
#> 2                                                 NA
#> 3                                                 NA
#> 4                                                 NA
#> 5                                                 NA
#>   PERSON_INJURED_SUBJECT1_NATURE_INJURIES
#> 1                                      NA
#> 2                                      NA
#> 3                                      NA
#> 4                                      NA
#> 5                                      NA
#>   PERSON_INJURED_SUBJECT2_MEDICAL_ATTENTION_REQUIRED
#> 1                                                 NA
#> 2                                                 NA
#> 3                                                 NA
#> 4                                                 NA
#> 5                                                 NA
#>   PERSON_INJURED_SUBJECT2_NATURE_INJURIES
#> 1                                      NA
#> 2                                      NA
#> 3                                      NA
#> 4                                      NA
#> 5                                      NA
#>   PERSON_INJURED_SUBJECT3_MEDICAL_ATTENTION_REQUIRED
#> 1                                                 NA
#> 2                                                 NA
#> 3                                                 NA
#> 4                                                 NA
#> 5                                                 NA
#>   PERSON_INJURED_SUBJECT3_NATURE_INJURIES REVIEWED_SUPERVISOR
#> 1                                      NA                  NA
#> 2                                      NA                  NA
#> 3                                      NA                  NA
#> 4                                      NA                  NA
#> 5                                      NA                  NA
#>   REVIEWED_TRAINING_ANALYST
#> 1                        NA
#> 2                        NA
#> 3                        NA
#> 4                        NA
#> 5                        NA
```
