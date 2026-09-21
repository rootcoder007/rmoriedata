# Load Chicago crime or arrest data

Returns the bundled sample by default, or fetches the full dataset from
the City of Chicago SODA API when `full = TRUE`. A complete fetch is
cached as Parquet under
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) for the session; to
keep it across sessions name a directory first, for example
`options(rmoriedata.cache_dir = tools::R_user_dir("rmoriedata", "cache"))`,
and drop it with
[`clear_chicago_cache()`](https://rootcoder007.github.io/rmoriedata/reference/clear_chicago_cache.md).
Nothing is written outside
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) unless you set that
option. The result can be returned as a base data frame, a tibble, or
written to a Parquet file whose path is returned – the last being the
recommended bridge for Python (`pandas.read_parquet`).

## Usage

``` r
load_chicago_data(
  type = c("arrests", "complaints"),
  as = c("data.frame", "tibble", "parquet_path"),
  full = FALSE,
  mirror = getOption("rmoriedata.mirror", NULL),
  limit = NULL,
  fraction = NULL,
  refresh = FALSE
)
```

## Arguments

- type:

  One of `"arrests"` or `"complaints"`.

- as:

  Return format: `"data.frame"` (default), `"tibble"`, or
  `"parquet_path"` (writes a Parquet file under
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html) and returns its
  path; nothing is written to the user's home).

- full:

  If `TRUE`, fetch the complete dataset from Socrata (network, large)
  instead of the bundled sample; a complete fetch is cached as Parquet
  (see Description).

- mirror:

  Optional base URL of an r-universe/drat mirror to try before Socrata
  (offline-friendly fallback). Defaults to
  `getOption("rmoriedata.mirror")`. The mirror's `<type>_full.parquet`
  must use snappy or no compression and data pages v1: the package's own
  reader supports nothing else.

- limit:

  Optional row cap for a `full = TRUE` fetch (passed to the Socrata
  `$limit` parameter). A bounded fetch skips the mirror and is never
  written to the full-dataset cache. Default `NULL` fetches everything.

- fraction:

  Optional share of the dataset, in `(0, 1]`, for a `full = TRUE` fetch:
  the live row count is looked up and `limit` is set to
  `ceiling(total * fraction)`. Give either `fraction` or `limit`, not
  both.

- refresh:

  If `TRUE`, ignore the cache of the complete dataset and fetch it again
  (the cache is rewritten). A cache file that cannot be read is
  discarded and refetched regardless.

## Value

A `data.frame`/`tibble`, or a length-1 character Parquet path when
`as = "parquet_path"`.

## Details

Parquet I/O uses this package's own native codec (R/aaa_parquet.R); no
package), so no arrow install is required.

## Examples

``` r
# `type` selects the dataset; the bundled sample is returned by default.
comp <- load_chicago_data("complaints") # reported incidents
arr <- load_chicago_data("arrests") # arrests
nrow(comp)
#> [1] 25000
nrow(arr)
#> [1] 25000
head(sort(table(comp$primary_type), decreasing = TRUE), 5)
#> 
#>           THEFT         BATTERY CRIMINAL DAMAGE         ASSAULT   OTHER OFFENSE 
#>            5825            4800            2362            1975            1760 

# `as = "tibble"` returns a tibble when the package is installed.
if (requireNamespace("tibble", quietly = TRUE)) {
  tb <- load_chicago_data("complaints", as = "tibble")
  class(tb)
}
#> [1] "tbl_df"     "tbl"        "data.frame"

# \donttest{
# `as = "parquet_path"` writes a Parquet file and returns its path --
# the recommended bridge to Python (pandas.read_parquet). Offline: the
# bundled sample is written, no network.
pq <- load_chicago_data("arrests", as = "parquet_path")
file.exists(pq)
#> [1] TRUE
# }

# \donttest{
# `full = TRUE` fetches from the live Chicago SODA API; `limit` bounds
# the request (seconds, not minutes) and try() keeps the example
# graceful when the service is unreachable. Omit `limit` for the
# complete multi-million-row dataset (cached, see Description); `mirror`
# tries an offline-friendly Parquet mirror first when set.
# `fraction = 0.001` takes a share of the dataset (0.1% of all rows)
# instead of a row count; the live total is looked up first.
big <- try(load_chicago_data("complaints", full = TRUE, limit = 200))
if (!inherits(big, "try-error")) nrow(big)
#> [1] 200
# }
```
