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
## ---- morie_core_sha256(): 64-char lowercase hex digest --------------
morie_core_sha256("abc")            # hash a character scalar
#> [1] "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
morie_core_sha256("")               # the empty string still hashes
#> [1] "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
morie_core_sha256(charToRaw("abc")) # identical digest from raw bytes
#> [1] "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

# character input and its raw-byte equivalent agree:
identical(morie_core_sha256("abc"), morie_core_sha256(charToRaw("abc")))
#> [1] TRUE

# Data-integrity pin: verify a value is byte-for-byte what you expect.
expected <- morie_core_sha256("record-42")
stopifnot(morie_core_sha256("record-42") == expected)

# Fingerprint a whole object by hashing its serialization.
morie_core_sha256(serialize(list(a = 1, b = "x"), NULL))
#> [1] "abf3149d8418cb5aff681febf06d66e362c42b3b4b1a3e196a1398aa08d60f4f"

## ---- morie_core_mean(): fast length-1 mean --------------------------
morie_core_mean(1:10)               # 5.5
#> [1] 5.5
morie_core_mean(c(2, 4, 6))         # 4
#> [1] 4
morie_core_mean(c(-1, 0, 1))        # 0
#> [1] 0
morie_core_mean(c(1, 2, NA))        # NA propagates (no na.rm)
#> [1] NA
morie_core_mean(complaint_sample$year)  # mean over a bundled column
#> [1] 2020
```
