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

Three options bound what a file can make the reader do, each checked
from the file's footer and page headers before anything is allocated or
inflated: `rmoriedata.parquet_max_rows` (default 5e7 rows),
`rmoriedata.parquet_max_page_bytes` (default 2^30 bytes a page) and
`rmoriedata.parquet_max_text_bytes` (default 2^32 bytes, 4 GiB). The
last is the most text and fixed-length bytes the compressed pages of one
file may inflate to, summed over the columns read; pages stored
uncompressed are not counted. A file past a bound is refused with an
error naming the option to raise.

A DECIMAL is a double: its scaled value, exact when the unscaled whole
number is below 2^53 and the scale at most 22, otherwise the nearest
double to the whole number, divided by the power of ten, with a warning
that it is rounded. One whose whole number is past the range of a
double, or whose precision and scale the format does not allow for its
type, is refused. A UUID is text (`"8-4-4-4-12"` lower-case
hexadecimal), and a FLOAT16 a double. Other fixed-length bytes (an
INTERVAL, or bytes with no logical type) are refused by name.

An INT32 column is an integer column, unless it holds -2147483648
(-2^31), which is R's `NA_integer_` and no R integer: then the whole
column is a double. An unsigned 32-bit column and every 64-bit one are
doubles: exact below 2^53, otherwise the nearest double, with a warning
that they are rounded.
