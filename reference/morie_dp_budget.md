# A privacy budget that DP releases are charged against

Creates a budget of `epsilon` (and `delta`) that the mechanisms in this
package draw down when passed as `budget =`. Releases compose by basic
composition: the epsilons and deltas of the releases charged to one
budget add up, and a release that would exceed the budget is refused
before any noise is drawn. A hundred releases at `epsilon = 1` spend
`epsilon = 100`; a budget makes that visible and enforceable.

## Usage

``` r
morie_dp_budget(epsilon, delta = 0)
```

## Arguments

- epsilon:

  Total epsilon available (positive).

- delta:

  Total delta available (0 for pure DP only).

## Value

An object of class `"morie_dp_budget"` (an environment, so charges
persist across calls).

## See also

[`morie_dp_spent()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_spent.md)

## Examples

``` r
b <- morie_dp_budget(epsilon = 2)
morie_dp_laplace_count(42, epsilon = 1, budget = b)
#> [1] 38
morie_dp_spent(b)
#> $epsilon
#> [1] 2
#> 
#> $delta
#> [1] 0
#> 
#> $spent_epsilon
#> [1] 1
#> 
#> $spent_delta
#> [1] 0
#> 
#> $remaining_epsilon
#> [1] 1
#> 
#> $remaining_delta
#> [1] 0
#> 
#> $releases
#> [1] 1
#> 
# a second release at epsilon = 1.5 would exceed the remaining 1
try(morie_dp_laplace_count(42, epsilon = 1.5, budget = b))
#> Error : this release (epsilon 1.5, delta 0) exceeds the remaining budget (epsilon 1, delta 0); nothing was released.
```
