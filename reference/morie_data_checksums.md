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
#> 'data.frame':    110 obs. of  3 variables:
#>  $ file  : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ bytes : num  23210 8888 11668 10180 131406 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "073f3cc2abb749f7dc7c541ae3aa81e0af49955eeb12e70165ffa95da3f28c0a" "41e0326ff96ddd942ce0e1dea0a24ca5463d6703a7cfc722798689babb7b9a7d" "313b99ad96aa624a0744347f5d909f5f23eff4dcb660bc7e5f5efa7f2a9a84e2" ...
head(ck)
#>                      file  bytes
#> 1 OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv   8888
#> 3          _checksums.csv  11668
#> 4          _checksums.sig  10180
#> 5             _schema.csv 131406
#> 6       _signing_key.json    197
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 073f3cc2abb749f7dc7c541ae3aa81e0af49955eeb12e70165ffa95da3f28c0a
#> 3 41e0326ff96ddd942ce0e1dea0a24ca5463d6703a7cfc722798689babb7b9a7d
#> 4 313b99ad96aa624a0744347f5d909f5f23eff4dcb660bc7e5f5efa7f2a9a84e2
#> 5 cea0953e0eec6816fd4d383843c0ef5636c2b4534443998e9eceacc4f4d33f14
#> 6 f97d3e9ae0c1ed10264961b396b5fabd019a179fa3123e9267b12ec6b2797a9a

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 8344063
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                             file   bytes
#> 34           describe_corpus.Rds 1712072
#> 33      cpads_pumf_synthetic.csv  893252
#> 44 nyc_opendata_bulk_catalog.csv  781038

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$file == ck$file[1]] == pinned)
}
```
