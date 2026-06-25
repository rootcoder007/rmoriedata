# SHA256 checksums of bundled rmoriedata files

Computes the SHA256 digest of every file rmoriedata bundles in
`inst/extdata`, using the shared provenance layer
([`sha256_file`](https://rdrr.io/pkg/rmoriebricklayer/man/sha256_file.html)).
This lets an analysis verify it used the exact data slice rmoriedata
shipped, and is rmoriedata's integration with the bricklayer provenance
layer.

## Usage

``` r
morie_data_checksums()
```

## Value

A data frame with one row per bundled file and columns `file`, `bytes`,
and `sha256`.

## Examples

``` r
head(morie_data_checksums())
#>                                              file bytes
#> 1                         OTIS_DATA_DICTIONARY.md 22607
#> 2 useofforce_agrregatesummarybyyear_2020-2022.csv   289
#> 3        useofforce_detaileddataset_2020-2022.csv  6830
#> 4                      uof_individual_records.csv  5221
#> 5                            uof_main_records.csv  1446
#> 6                     uof_probe_cycle_records.csv   220
#>                                                             sha256
#> 1 5764a7d3696dbd88f7c18cd2863a482f597e0692afca503bfc93c608202548e9
#> 2 f3051269a22394b6930ba1961e7b6ed5e4454d483db1ea7cd930f1541330dfce
#> 3 4fa3b0ada472f2386ffc4cb81e438e68a57818e476b12524370cfab25ae1084a
#> 4 6d3a5986e39f4751901a1a2adb9e25be836266e1900bd41c8611fec7218187f4
#> 5 610bc3f8217b75d486b749ffe4ace23987862fafccffaae3b31137b46b2a7a79
#> 6 1564ebdec4ea20334e2a2a8a906a774290ac0d37bf97444dcb17898e4d71d617
```
