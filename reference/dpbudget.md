# A privacy budget that DP releases are charged against

Creates a budget of `epsilon` (and `delta`) that the mechanisms in this
package draw down when passed as `budget =`. Releases compose by basic
composition: the epsilons and deltas of the releases charged to one
budget add up, and a release that would exceed the budget is refused
before any noise is drawn. A hundred releases at `epsilon = 1` spend
`epsilon = 100`; a budget makes that visible and enforceable.

## Usage

``` r
dpbudget(epsilon, delta = 0)
```

## Arguments

- epsilon:

  Total epsilon available (positive).

- delta:

  Total delta available (0 for pure DP only).

## Value

An object of class `"dpbudget"` (an environment, so charges persist
across calls).

## Details

A budget is an in-memory ledger held by the R process that created it. A
forked worker (for example under
[`parallel::mclapply()`](https://rdrr.io/r/parallel/mclapply.html) or
[`parallel::mcparallel()`](https://rdrr.io/r/parallel/mcparallel.html))
gets its own copy, so its spending would never reach the parent and
every worker could spend the whole budget again. A release charged to a
budget from any process other than the one that created it is therefore
refused with an error. Spend a budget in the process that created it; to
release from workers, give each worker its own budget and account for
the total yourself by composition (the epsilons and deltas of all
workers add up). A budget saved and read back in another R session is
refused in the same way, even one whose process has the same PID (in a
container whose entrypoint is `Rscript` every session is PID 1): each
budget carries a random token drawn from the operating system's CSPRNG
when the package is loaded, and a release is charged only in the
process, and the load of the package, that made the budget.

A budget of `delta = 0` pays only for pure-DP releases: a release with
any `delta > 0` is refused. The totals are compared with a slack for
floating-point rounding only, so that ten releases at `epsilon = 0.1`
fit a budget of 1: the slack is `(n + 2)` units in the last place of the
larger of the budget and the total, `n` being the number of releases
(below a millionth of a millionth of the budget for 4,000 releases), and
a release more than twice what remains is refused whatever the slack.

A release is charged before its noise is drawn. If it is interrupted or
fails after that, the budget stays charged though nothing was released:
the safe side, since a release that went out uncharged would spend
privacy the ledger does not show.

## See also

[`dpspent()`](https://rootcoder007.github.io/rmoriedata/reference/dpspent.md)

## Examples

``` r
b <- dpbudget(epsilon = 2)
dplapcnt(42, epsilon = 1, budget = b)
#> [1] 41
dpspent(b)
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
try(dplapcnt(42, epsilon = 1.5, budget = b))
#> Error : this release (epsilon 1.5, delta 0) exceeds the remaining budget (epsilon 1, delta 0); nothing was released.
```
