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
#>  $ bytes : num  23210 13782 23929 10180 131406 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "292c93ddd946fa8a0352b8d511c5efa8ea8d8a73b6d3856184c5b12097ed560e" "2546b8be5ebab964860775dd36128b4e7b194cdd0f4e5a3ee5685a85f864d16e" "82e90983f23914651095762b63f10eb8edd691785251795bbf2b92bd8eabdecd" ...
head(ck)
#>                      path                    file  bytes
#> 1 OTIS_DATA_DICTIONARY.md OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv            _catalog.csv  13782
#> 3          _checksums.csv          _checksums.csv  23929
#> 4          _checksums.sig          _checksums.sig  10180
#> 5             _schema.csv             _schema.csv 131406
#> 6       _signing_key.json       _signing_key.json    197
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 292c93ddd946fa8a0352b8d511c5efa8ea8d8a73b6d3856184c5b12097ed560e
#> 3 2546b8be5ebab964860775dd36128b4e7b194cdd0f4e5a3ee5685a85f864d16e
#> 4 82e90983f23914651095762b63f10eb8edd691785251795bbf2b92bd8eabdecd
#> 5 cea0953e0eec6816fd4d383843c0ef5636c2b4534443998e9eceacc4f4d33f14
#> 6 f97d3e9ae0c1ed10264961b396b5fabd019a179fa3123e9267b12ec6b2797a9a

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 30056551
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                                     file   bytes
#> 154 siu_directors_reports_corpus.parquet 8097910
#> 153        siu_directors_reports.parquet 7445079
#> 34                   describe_corpus.Rds 1712072

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
}
```
