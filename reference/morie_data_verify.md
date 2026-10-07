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

A data frame with one row per manifest entry, then one per unlisted
file: `path`, `bytes`, `sha256` (the manifest digest, or the file's own
for an unlisted file), `listed`, `ok` (the file on disk is listed and
matches). The attribute `"signature"` is `TRUE` when the manifest's
signature verified, and the function errors if it did not.

## Details

A file present in the installed store but absent from the manifest is
reported too, as a row with `listed = FALSE` and `ok = FALSE`: a file
added to the store is as much a change as a file altered in it.

## Examples

``` r
v <- morie_data_verify()
all(v$ok)
#> [1] TRUE
attr(v, "signature")
#> [1] TRUE
```
