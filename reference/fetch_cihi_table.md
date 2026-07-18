# Download a CIHI data table (live, with Wayback fallback)

Resolves a CIHI table from the bundled catalogue and downloads it to
`dest`, falling back to the Internet Archive snapshot if the live CIHI
URL has rotated or been removed. The download + fallback runs through
rmoriebricklayer's shared C++/libcurl foundation (`bricklayer_fetch`),
the same engine rmorie and morie use.

## Usage

``` r
fetch_cihi_table(which, dest = NULL, timeout = 120L)
```

## Arguments

- which:

  A row index into
  [`load_cihi_data_tables()`](https://rootcoder007.github.io/rmoriedata/reference/load_cihi_data_tables.md),
  or a string matched (case-insensitively, as a substring) against table
  titles. Must resolve to exactly one table.

- dest:

  Destination file path. Default: a tempfile with the table's own
  extension.

- timeout:

  Per-request timeout, seconds.

## Value

The `dest` path, invisibly. Errors if both the live URL and its Wayback
fallback fail.

## See also

[`load_cihi_data_tables`](https://rootcoder007.github.io/rmoriedata/reference/load_cihi_data_tables.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cat <- load_cihi_data_tables()
f <- fetch_cihi_table("Hospital Beds, 2024")   # live -> archive fallback
} # }
```
