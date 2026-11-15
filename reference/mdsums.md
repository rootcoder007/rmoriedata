# SHA256 checksums of bundled rmoriedata files

Computes the SHA256 digest of every file rmoriedata bundles in
`inst/extdata`, using the shared provenance layer
([`rmoriebricklayer::sha256file()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/sha256file.html)),
and compares each with the digest the signed manifest records for it
(`in_manifest`). For the full check, signature included, use
[`mdverify()`](https://rootcoder007.github.io/rmoriedata/reference/mdverify.md);
this function is the per-file record an analysis can pin and compare
later.

## Usage

``` r
mdsums()
```

## Value

A data frame with one row per bundled file and columns `path` (relative
to the extdata root, forward slashes, unique), `file` (the bare
basename), `bytes`, `sha256`, and `in_manifest` (TRUE when the signed
manifest lists the file with this digest; NA for the manifest's own
files). Use `path` to locate a file; several basenames recur in more
than one directory.

## Examples

``` r
# One row per bundled file: name, size in bytes, SHA256 digest.
ck <- mdsums()
str(ck)
#> 'data.frame':    210 obs. of  5 variables:
#>  $ path       : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ file       : chr  "OTIS_DATA_DICTIONARY.md" "_catalog.csv" "_checksums.csv" "_checksums.sig" ...
#>  $ bytes      : num  23210 14421 23768 10181 131454 ...
#>  $ sha256     : chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "7dea162bf542aab8f646ad54900e18332c4de1424787afc4cd93a05405d4caf2" "2b587991862186d249a5c7523f11fd10ea2f59d7e3753d472223d7a01548d7ec" "9ad6877052a79e81926bb7aeb13e29d0ce643bfaf8551b4c622ea6e66798372e" ...
#>  $ in_manifest: logi  TRUE TRUE NA NA TRUE NA ...
head(ck)
#>                      path                    file  bytes
#> 1 OTIS_DATA_DICTIONARY.md OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv            _catalog.csv  14421
#> 3          _checksums.csv          _checksums.csv  23768
#> 4          _checksums.sig          _checksums.sig  10181
#> 5             _schema.csv             _schema.csv 131454
#> 6       _signing_key.json       _signing_key.json    196
#>                                                             sha256 in_manifest
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00        TRUE
#> 2 7dea162bf542aab8f646ad54900e18332c4de1424787afc4cd93a05405d4caf2        TRUE
#> 3 2b587991862186d249a5c7523f11fd10ea2f59d7e3753d472223d7a01548d7ec          NA
#> 4 9ad6877052a79e81926bb7aeb13e29d0ce643bfaf8551b4c622ea6e66798372e          NA
#> 5 24c14b6b500947d424f98a8a1479cf250ca1a694e440cc17788d20755d7dae0b        TRUE
#> 6 f26cb1f7fb7721439586fa54be1a1ce4ee02ea77bf2d28d88b2df9ea400828f1          NA

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 13361273
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                              file   bytes
#> 181  siu_directors_reports.csv.gz 2378925
#> 153 siu_directors_reports.parquet 2053237
#> 34            describe_corpus.Rds 1712072

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- mdsums()
  stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
}
```
