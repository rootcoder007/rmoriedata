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
#>  $ bytes : num  23210 14421 23768 10181 131454 ...
#>  $ sha256: chr  "bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00" "7dea162bf542aab8f646ad54900e18332c4de1424787afc4cd93a05405d4caf2" "b274f02d651b773d5789fed42b8c81c1ca77380a7d3e50eea3bb370a5a2d6dbc" "e3df32a1b071d917a26ed16d34eaf257339a4c51f30a1d069d330b9b8134156f" ...
head(ck)
#>                      path                    file  bytes
#> 1 OTIS_DATA_DICTIONARY.md OTIS_DATA_DICTIONARY.md  23210
#> 2            _catalog.csv            _catalog.csv  14421
#> 3          _checksums.csv          _checksums.csv  23768
#> 4          _checksums.sig          _checksums.sig  10181
#> 5             _schema.csv             _schema.csv 131454
#> 6       _signing_key.json       _signing_key.json    197
#>                                                             sha256
#> 1 bc143646019d8edb68a23f8c2fa74616dfe04b83c66483f4ac4a6a7ae886dc00
#> 2 7dea162bf542aab8f646ad54900e18332c4de1424787afc4cd93a05405d4caf2
#> 3 b274f02d651b773d5789fed42b8c81c1ca77380a7d3e50eea3bb370a5a2d6dbc
#> 4 e3df32a1b071d917a26ed16d34eaf257339a4c51f30a1d069d330b9b8134156f
#> 5 24c14b6b500947d424f98a8a1479cf250ca1a694e440cc17788d20755d7dae0b
#> 6 f97d3e9ae0c1ed10264961b396b5fabd019a179fa3123e9267b12ec6b2797a9a

# Total bundled payload and the largest few files.
sum(ck$bytes)
#> [1] 13360923
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                              file   bytes
#> 181  siu_directors_reports.csv.gz 2378925
#> 153 siu_directors_reports.parquet 2053237
#> 34            describe_corpus.Rds 1712072

# Provenance workflow: pin the digest of a file you depend on, then
# assert it hasn't changed under you in a later session / reinstall.
if (nrow(ck)) {
  pinned <- ck$sha256[1]
  again <- morie_data_checksums()
  stopifnot(again$sha256[again$path == ck$path[1]] == pinned)
}
```
