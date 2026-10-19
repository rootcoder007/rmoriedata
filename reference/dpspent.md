# What a privacy budget has spent

What a privacy budget has spent

## Usage

``` r
dpspent(budget)
```

## Arguments

- budget:

  A budget from
  [`dpbudget()`](https://rootcoder007.github.io/rmoriedata/reference/dpbudget.md).

## Value

A list: `epsilon`, `delta` (the totals), `spent_epsilon`, `spent_delta`,
`remaining_epsilon`, `remaining_delta`, `releases`.

## Examples

``` r
b <- dpbudget(1)
invisible(dplaphist(c(10, 20), epsilon = 0.25, budget = b))
dpspent(b)$remaining_epsilon
#> [1] 0.75
```
