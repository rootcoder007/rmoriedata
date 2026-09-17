# SHA256 checksums of bundled rmoriedata files

Computes the SHA256 digest of every file rmoriedata bundles in
`inst/extdata`, using the shared provenance layer
([`sha256_file`](https://rootcoder007.github.io/rmorie-bricklayer/reference/sha256_file.html)).
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
# One row per bundled file: name, size in bytes, SHA256 digest.
ck <- morie_data_checksums()
str(ck)
#> 'data.frame':    108 obs. of  3 variables:
#>  $ file  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_schema.csv" "useofforce_agrregatesummarybyyear_2020-2022.csv" ...
#>  $ bytes : num  23210 8888 131406 289 6830 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "073f3cc2abb749f7dc7c541ae3aa81e0af49955eeb12e70165ffa95da3f28c0a" "cea0953e0eec6816fd4d383843c0ef5636c2b4534443998e9eceacc4f4d33f14" "f3051269a22394b6930ba1961e7b6ed5e4454d483db1ea7cd930f1541330dfce" ...
head(ck)
#>                                              file  bytes
#> 1                         OTIS_DATA_DICTIONARY.md  23210
#> 2                                    _catalog.csv   8888
#> 3                                     _schema.csv 131406
#> 4 useofforce_agrregatesummarybyyear_2020-2022.csv    289
#> 5        useofforce_detaileddataset_2020-2022.csv   6830
#> 6                      uof_individual_records.csv   5221
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 073f3cc2abb749f7dc7c541ae3aa81e0af49955eeb12e70165ffa95da3f28c0a
#> 3 cea0953e0eec6816fd4d383843c0ef5636c2b4534443998e9eceacc4f4d33f14
#> 4 f3051269a22394b6930ba1961e7b6ed5e4454d483db1ea7cd930f1541330dfce
#> 5 4fa3b0ada472f2386ffc4cb81e438e68a57818e476b12524370cfab25ae1084a
#> 6 6d3a5986e39f4751901a1a2adb9e25be836266e1900bd41c8611fec7218187f4

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 23157730
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                        file    bytes
#> 78        rmoriedata.sqlite 14835712
#> 31      describe_corpus.Rds  1712072
#> 30 cpads_pumf_synthetic.csv   893252

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$file == ck$file[1]] == pinned)
}
```
