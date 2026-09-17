# Verify the bundled data store against its signed manifest

Every file rmoriedata ships is listed with its SHA-256 in a manifest,
and the manifest is signed with an XMSS (RFC 8391, SHA-256) key whose
public half ships with the package. Loading a table checks its file
against the manifest; this function checks all of them at once.

## Usage

``` r
morie_data_verify()
```

## Value

A data frame with one row per manifest entry: `path`, `bytes`, `sha256`,
`ok` (the file on disk matches). The attribute `"signature"` is `TRUE`
when the manifest's signature verified, and the function errors if it
did not.

## Examples

``` r
v <- morie_data_verify()
all(v$ok)
#> [1] TRUE
attr(v, "signature")
#> [1] TRUE
```
