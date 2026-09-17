# Read a Parquet file

Native Parquet reader: no nanoparquet, no arrow. Handles the v1 format
with PLAIN, RLE and dictionary encodings, Snappy or no compression.
Nested and repeated columns are refused.

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

A `data.frame`.
