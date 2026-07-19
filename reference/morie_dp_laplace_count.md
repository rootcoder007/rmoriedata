# Differentially-private count via the Laplace mechanism

Adds Laplace noise calibrated to sensitivity / epsilon. Use when
releasing counts of records matching some predicate (e.g. number of UoF
incidents in a division-year). Sensitivity is hardcoded to 1: one record
entering or leaving the dataset changes the count by at most 1.

## Usage

``` r
morie_dp_laplace_count(true_count, epsilon)
```

## Arguments

- true_count:

  Non-negative integer; the true count.

- epsilon:

  Privacy budget (smaller = more noise = stronger privacy). Typical
  range: 0.1 to 5.0.

## Value

A noised count (numeric, may be fractional or negative). Caller should
usually clip to a non-negative integer for display: `round(pmax(0, x))`.

## Details

Pure (\\\epsilon\\, 0)-differentially-private under the standard
add-or-remove-one neighbouring-databases definition.

## Examples

``` r
set.seed(1)
# A single noised release of a true count of 42.
morie_dp_laplace_count(true_count = 42, epsilon = 1.0)
#> [1] 41.36704

# Smaller epsilon = stronger privacy = more noise.
morie_dp_laplace_count(42, epsilon = 0.1)   # noisier
#> [1] 39.04619
morie_dp_laplace_count(42, epsilon = 5.0)   # closer to 42
#> [1] 42.0315

# The mechanism is unbiased: averaging many releases returns ~the truth.
mean(replicate(2000, morie_dp_laplace_count(42, epsilon = 1.0)))
#> [1] 41.98897

# For display, clip to a non-negative integer.
round(pmax(0, morie_dp_laplace_count(3, epsilon = 0.5)))
#> [1] 3
```
