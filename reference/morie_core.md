# Shared C-core helpers (rmorie ecosystem backend)

Thin access to the compiled core that ships in rmoriebricklayer.
rmoriedata links that core via \`LinkingTo: rmoriebricklayer\`, so these
functions call the exact same kernels used across the rmorie family – no
duplicated C code. They back fast data-integrity hashing and summaries
for the bundled datasets without requiring rmorie.

## Usage

``` r
morie_core_sha256(x)

morie_core_mean(x)
```

## Arguments

- x:

  For \`morie_core_sha256()\`, a length-1 character vector or a raw
  vector. For \`morie_core_mean()\`, a numeric vector (coerced with
  \[as.numeric()\]); NA/NaN propagate.

## Value

\`morie_core_sha256()\` returns a 64-character lowercase hex digest.
\`morie_core_mean()\` returns a length-1 numeric.

## Examples

``` r
morie_core_sha256("abc")
#> Error in morie_core_sha256("abc"): function 'rmbl_sha256_hex' not provided by package 'rmoriebricklayer'
morie_core_mean(1:10)
#> Error in morie_core_mean(1:10): function 'rmbl_mean' not provided by package 'rmoriebricklayer'
```
