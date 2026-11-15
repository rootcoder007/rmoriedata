# Read a Parquet file

Native Parquet reader: no nanoparquet, no arrow. Handles the v1 format
with PLAIN, RLE and dictionary encodings, GZIP, Snappy, Zstandard (ZSTD)
or no compression. ZSTD pages are read by a decoder in the package (RFC
8878, without dictionaries), so no other package is needed for them; the
writer does not write ZSTD. Nested and repeated columns are refused.

## Usage

``` r
morie_read_parquet(path, columns = NULL)
```

## Arguments

- path:

  Path to a `.parquet` file.

- columns:

  Optional character vector of column names to decode; the rest are
  skipped entirely. `character(0)` gives a data frame with the file's
  rows and no columns.

## Value

A `data.frame`. Every error the reader raises, a missing or damaged file
included, starts with `parquet:`; no base-R warning escapes it (a value
a damaged file makes R warn about is an error instead).

## Details

A string column comes back as text marked UTF-8 (ASCII text stays
unmarked, as R keeps it). A Parquet string is UTF-8 by definition, and
[`morie_write_parquet()`](https://rootcoder007.github.io/rmoriedata/reference/morie_write_parquet.md)
refuses to write anything else, so a value that is not valid UTF-8, or
that holds a NUL byte, is refused with a `parquet:` error naming the
column: returned, it would fail later in
[`nchar()`](https://rdrr.io/r/base/nchar.html) or
[`toupper()`](https://rdrr.io/r/base/chartr.html).
