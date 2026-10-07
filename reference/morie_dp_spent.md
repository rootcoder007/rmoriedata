# What a privacy budget has spent

What a privacy budget has spent

## Usage

``` r
morie_dp_spent(budget)
```

## Arguments

- budget:

  A budget from
  [`morie_dp_budget()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_budget.md).

## Value

A list: `epsilon`, `delta` (the totals), `spent_epsilon`, `spent_delta`,
`remaining_epsilon`, `remaining_delta`, `releases`.

## Examples

``` r
b <- morie_dp_budget(1)
invisible(morie_dp_laplace_histogram(c(10, 20), epsilon = 0.25, budget = b))
morie_dp_spent(b)$remaining_epsilon
#> [1] 0.75
```
