# Write a data frame to Parquet

Native Parquet writer: single row group, PLAIN encoding, all columns
OPTIONAL. Output is read back unchanged by pyarrow and nanoparquet.

## Usage

``` r
morie_write_parquet(df, path, compression = "snappy")
```

## Arguments

- df:

  A `data.frame`.

- path:

  Destination path.

- compression:

  `"snappy"` (default) or `NULL` for uncompressed.

## Value

`path`, invisibly.
