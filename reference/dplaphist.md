# Differentially-private histogram via the discrete Laplace mechanism

Adds independent discrete Laplace noise, \\P(y) \propto e^{-\epsilon
\|y\|}\\, to each bin count. Adding or removing one record changes
exactly one bin by 1, so the whole histogram is pure \\\epsilon\\-DP
under the add-or-remove-one relation. Noise and sampler as in
[`dplapcnt()`](https://rootcoder007.github.io/rmoriedata/reference/dplapcnt.md).

## Usage

``` r
dplaphist(counts, epsilon, budget = NULL)
```

## Arguments

- counts:

  Vector of non-negative whole-number bin counts.

- epsilon:

  Privacy loss for the whole histogram (positive scalar).

- budget:

  Optional
  [`dpbudget()`](https://rootcoder007.github.io/rmoriedata/reference/dpbudget.md)
  to charge `epsilon` against.

## Value

A numeric vector of whole numbers, the same length as `counts` (values
may be negative; clip for display).

## Examples

``` r
true <- c(120, 45, 8, 230, 17)
dplaphist(true, epsilon = 0.5)
#> [1] 120  47  10 229  18

# Post-process for display: clip negatives (costs no privacy).
pmax(0, dplaphist(true, epsilon = 1.0))
#> [1] 120  45   8 228  21

# Release a private histogram straight from tabulated data.
counts <- as.integer(table(complaint_sample$year))
dplaphist(counts, epsilon = 1.0)
#> [1] 24999     1
```
