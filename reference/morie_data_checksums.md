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
#> 'data.frame':    211 obs. of  4 variables:
#>  $ path  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ file  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ bytes : num  23210 13782 23929 10180 131404 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "292c93ddd946fa8a0352b8d511c5efa8ea8d8a73b6d3856184c5b12097ed560e" "1a240f8205675abc1b987ee9b10431a8ca2abb29482a6f47dcc08f7701569a16" "a048a2d7a6796a8a7a8803f6a86b4b8b05d32a73bb23968aeaf4f6b055e170b4" ...
head(ck)
#>                      path                    file  bytes
#> 1 OTIS_DATA_DICTIONARY.md OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv            _catalog.csv  13782
#> 3          _checksums.csv          _checksums.csv  23929
#> 4          _checksums.sig          _checksums.sig  10180
#> 5             _schema.csv             _schema.csv 131404
#> 6       _signing_key.json       _signing_key.json    197
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 292c93ddd946fa8a0352b8d511c5efa8ea8d8a73b6d3856184c5b12097ed560e
#> 3 1a240f8205675abc1b987ee9b10431a8ca2abb29482a6f47dcc08f7701569a16
#> 4 a048a2d7a6796a8a7a8803f6a86b4b8b05d32a73bb23968aeaf4f6b055e170b4
#> 5 e13b153a96f8b518b92d71974a455b8ec0ebb6b4502364e47b2ede672ef5f9f4
#> 6 f97d3e9ae0c1ed10264961b396b5fabd019a179fa3123e9267b12ec6b2797a9a

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 30056545
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                                     file   bytes
#> 154 siu_directors_reports_corpus.parquet 8097910
#> 153        siu_directors_reports.parquet 7445077
#> 34                   describe_corpus.Rds 1712072

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
}
```
