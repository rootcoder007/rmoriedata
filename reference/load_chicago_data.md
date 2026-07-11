# Load Chicago crime or arrest data

Returns the bundled sample by default, or fetches the full dataset from
the City of Chicago SODA API (cached under
[`R_user_dir`](https://rdrr.io/r/tools/userdir.html)) when
`full = TRUE`. The result can be returned as a base data frame, a
tibble, or written to a Parquet file whose path is returned – the last
being the recommended bridge for Python (`pandas.read_parquet`).

## Usage

``` r
load_chicago_data(
  type = c("arrests", "complaints"),
  as = c("data.frame", "tibble", "parquet_path"),
  full = FALSE,
  mirror = getOption("rmoriedata.mirror", NULL)
)
```

## Arguments

- type:

  One of `"arrests"` or `"complaints"`.

- as:

  Return format: `"data.frame"` (default), `"tibble"`, or
  `"parquet_path"` (writes a Parquet file to the session cache and
  returns its path).

- full:

  If `TRUE`, fetch the complete dataset from Socrata (network, large)
  instead of the bundled sample; cached across sessions as Parquet.

- mirror:

  Optional base URL of an r-universe/drat mirror to try before Socrata
  (offline-friendly fallback). Defaults to
  `getOption("rmoriedata.mirror")`.

## Value

A `data.frame`/`tibble`, or a length-1 character Parquet path when
`as = "parquet_path"`.

## Details

Parquet I/O uses nanoparquet (already a hard dependency of this
package), so no arrow install is required.

## Examples

``` r
df <- load_chicago_data("complaints")             # bundled sample
# \donttest{
pq <- load_chicago_data("arrests", as = "parquet_path")
# Python: pandas.read_parquet(pq)
# }
```
