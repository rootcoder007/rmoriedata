# Write a data frame to Parquet

Native Parquet writer: single row group, PLAIN encoding, all columns
OPTIONAL. Output is read back unchanged by pyarrow and nanoparquet.

## Usage

``` r
morie_write_parquet(df, path, compression = "snappy")
```

## Arguments

- df:

  A `data.frame`. Factor columns are written as character; every string
  must be valid UTF-8 (marked, or unmarked in UTF-8 bytes), and column
  names must be unique.

- path:

  Destination path.

- compression:

  `"snappy"` (default) or `NULL` for uncompressed.

## Value

`path`, invisibly.
