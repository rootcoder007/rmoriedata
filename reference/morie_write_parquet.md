# Write a data frame to Parquet

Native Parquet writer: single row group, PLAIN encoding, all columns
OPTIONAL. Output is read back unchanged by pyarrow and nanoparquet.

## Usage

``` r
morie_write_parquet(df, path, compression = "gzip")
```

## Arguments

- df:

  A `data.frame` with at least one column. Factor columns are written as
  character; list, complex, raw, `difftime`, `integer64`, matrix and
  data frame columns are refused with an error naming the column. `NaN`
  in a numeric column is kept as `NaN`. Every string must be valid UTF-8
  (marked, or unmarked in UTF-8 bytes), and column names must be unique.

- path:

  Destination path.

- compression:

  `"gzip"` (default; zlib level 9), `"snappy"`, or `NULL` for
  uncompressed pages.

## Value

`path`, invisibly.

## Details

A `Date` column is written as a Parquet DATE (whole days) and a
`POSIXct` column as a Parquet TIMESTAMP (whole milliseconds since
1970-01-01 UTC), each taken down to the whole day or millisecond as R
prints them, before 1970 too: a fractional `Date` of -0.5 (printed
1969-12-31) is written as 1969-12-31. The format stores the instant but
not a time zone, so it reads back as the same instant in UTC: a column
in `America/Chicago` comes back with `tz = "UTC"`. Set the zone again
with `attr(x, "tzone") <- "America/Chicago"`, or keep an ISO 8601 text
column beside it, as
[`chiload()`](https://rootcoder007.github.io/rmoriedata/reference/chiload.md)'s
`date_iso` does.
