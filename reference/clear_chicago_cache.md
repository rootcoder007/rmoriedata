# Clear the cache of full Chicago datasets

Deletes the Parquet files that `load_chicago_data(full = TRUE)` wrote to
the cache directory: [`tempdir()`](https://rdrr.io/r/base/tempfile.html)
by default, or the directory named in
`options(rmoriedata.cache_dir = )`.

## Usage

``` r
clear_chicago_cache()
```

## Value

The cache directory, invisibly.

## Examples

``` r
clear_chicago_cache()
```
