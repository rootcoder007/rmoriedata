# Clear the cache of full Chicago datasets

Deletes the Parquet files that `chiload(full = TRUE)` wrote to the cache
directory ([`tempdir()`](https://rdrr.io/r/base/tempfile.html) by
default, or the directory named in `options(rmoriedata.cache_dir = )`):
the `<type>_full.parquet` files, their checksum files and any unfinished
write. Nothing else in that directory is touched.

## Usage

``` r
chiclr()
```

## Value

The cache directory, invisibly.

## Examples

``` r
chiclr()
```
