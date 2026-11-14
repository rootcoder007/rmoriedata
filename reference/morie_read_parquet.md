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
  skipped entirely.

## Value

A `data.frame`. Every error the reader raises, a missing or damaged file
included, starts with `parquet:`; no base-R warning escapes it (a value
a damaged file makes R warn about is an error instead).
