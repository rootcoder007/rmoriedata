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

A data frame with one row per bundled file and columns `path` (relative
to the extdata root, forward slashes, unique), `file` (the bare
basename), `bytes`, and `sha256`. Use `path` to locate a file; several
basenames recur in more than one directory.

## Examples

``` r
# One row per bundled file: name, size in bytes, SHA256 digest.
ck <- morie_data_checksums()
str(ck)
#> 'data.frame':    210 obs. of  4 variables:
#>  $ path  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ file  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ bytes : num  23210 14421 23807 10180 131404 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "c64da89ac8a4811bfcdf3adeb50f6933211696fbf54282e4b3a9105b4ffac2b3" "80660009f0311a8830da9ae3a1a31d8c42558e20317040cf25fdb70da41868bf" "c72fe9930729dac1def8861fd68bdff6d061b73f97ae7bee31dd50cff012d832" ...
head(ck)
#>                      path                    file  bytes
#> 1 OTIS_DATA_DICTIONARY.md OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv            _catalog.csv  14421
#> 3          _checksums.csv          _checksums.csv  23807
#> 4          _checksums.sig          _checksums.sig  10180
#> 5             _schema.csv             _schema.csv 131404
#> 6       _signing_key.json       _signing_key.json    197
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 c64da89ac8a4811bfcdf3adeb50f6933211696fbf54282e4b3a9105b4ffac2b3
#> 3 80660009f0311a8830da9ae3a1a31d8c42558e20317040cf25fdb70da41868bf
#> 4 c72fe9930729dac1def8861fd68bdff6d061b73f97ae7bee31dd50cff012d832
#> 5 5939e9531af213f77251d20fdaf9d13debf7d26d556505d266c99f48bba980d2
#> 6 f97d3e9ae0c1ed10264961b396b5fabd019a179fa3123e9267b12ec6b2797a9a

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 21039798
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                              file   bytes
#> 153 siu_directors_reports.parquet 6525285
#> 34            describe_corpus.Rds 1712072
#> 33       cpads_pumf_synthetic.csv  893252

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
}
```
