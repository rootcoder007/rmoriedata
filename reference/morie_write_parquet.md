# Write a data frame to Parquet

Native Parquet writer: single row group, PLAIN encoding, all columns
OPTIONAL. Output is read back unchanged by pyarrow and nanoparquet.

## Usage

``` r
morie_write_parquet(df, path, compression = "gzip")
```

## Arguments

- df:

  A `data.frame`. Factor columns are written as character; every string
  must be valid UTF-8 (marked, or unmarked in UTF-8 bytes), and column
  names must be unique.

- path:

  Destination path.

- compression:

  `"gzip"` (default; zlib level 9), `"snappy"`, or `NULL` for
  uncompressed pages.

## Value

`path`, invisibly.

## Details

A `POSIXct` column is written as a Parquet TIMESTAMP (milliseconds since
1970-01-01 UTC). The format stores the instant but not a time zone, so
it reads back as the same instant in UTC: a column in `America/Chicago`
comes back with `tz = "UTC"`. Set the zone again with
`attr(x, "tzone") <- "America/Chicago"`, or keep an ISO 8601 text column
beside it, as
[`chiload()`](https://rootcoder007.github.io/rmoriedata/reference/chiload.md)'s
`date_iso` does.
