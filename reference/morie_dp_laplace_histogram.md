# Differentially-private histogram via the Laplace mechanism

Adds independent Laplace(`1/epsilon`) noise to each bin count. Under the
add-or-remove-one neighbouring-databases definition a single record
participates in exactly one bin, so the per-bin sensitivity is 1 and the
overall mechanism is (\\\epsilon\\, 0)-DP.

## Usage

``` r
morie_dp_laplace_histogram(counts, epsilon)
```

## Arguments

- counts:

  Integer vector of non-negative bin counts.

- epsilon:

  Privacy budget (positive scalar).

## Value

A numeric vector of the same length as `counts`. May contain fractional
or negative values. Caller is responsible for any post-hoc
non-negativity / rounding before display.

## Examples

``` r
set.seed(1)
morie_dp_laplace_histogram(c(120, 45, 8, 230, 17), epsilon = 0.5)
#> [1] 118.734079  44.409238   8.314961 233.390161  15.184168
```
