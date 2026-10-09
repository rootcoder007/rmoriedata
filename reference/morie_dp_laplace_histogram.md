# Differentially-private histogram via the discrete Laplace mechanism

Adds independent discrete Laplace noise, \\P(y) \propto e^{-\epsilon
\|y\|}\\, to each bin count. Adding or removing one record changes
exactly one bin by 1, so the whole histogram is pure \\\epsilon\\-DP
under the add-or-remove-one relation. Noise and sampler as in
[`morie_dp_laplace_count()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_count.md).

## Usage

``` r
morie_dp_laplace_histogram(counts, epsilon, budget = NULL)
```

## Arguments

- counts:

  Vector of non-negative whole-number bin counts.

- epsilon:

  Privacy loss for the whole histogram (positive scalar).

- budget:

  Optional
  [`morie_dp_budget()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_budget.md)
  to charge `epsilon` against.

## Value

A numeric vector of whole numbers, the same length as `counts` (values
may be negative; clip for display).

## Examples

``` r
true <- c(120, 45, 8, 230, 17)
morie_dp_laplace_histogram(true, epsilon = 0.5)
#> [1] 120  46   6 232  17

# Post-process for display: clip negatives (costs no privacy).
pmax(0, morie_dp_laplace_histogram(true, epsilon = 1.0))
#> [1] 121  48  11 230  17

# Release a private histogram straight from tabulated data.
counts <- as.integer(table(complaint_sample$year))
morie_dp_laplace_histogram(counts, epsilon = 1.0)
#> [1] 24999     1
```
