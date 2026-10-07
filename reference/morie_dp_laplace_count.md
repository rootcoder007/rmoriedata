# Differentially-private count via the discrete Laplace mechanism

Releases a count with discrete Laplace noise, \\P(y) \propto
e^{-\epsilon \|y\|}\\, so the release is a whole number. Use it for the
number of records matching a predicate (for example incidents in a
division-year). Adding or removing one record changes the count by at
most 1, and the release is pure \\\epsilon\\-DP under that
add-or-remove-one relation, the one every mechanism in this package
uses.

## Usage

``` r
morie_dp_laplace_count(true_count, epsilon, budget = NULL)
```

## Arguments

- true_count:

  Non-negative integer; the true count.

- epsilon:

  Privacy loss (smaller means more noise, stronger privacy).

- budget:

  Optional
  [`morie_dp_budget()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_budget.md)
  to charge `epsilon` against.

## Value

The noised count, a whole number (it can be negative; clip with
`pmax(0, x)` for display, which is post-processing and costs no
privacy).

## Details

The noise is drawn from the operating system's CSPRNG with the exact
sampler of Canonne, Kamath and Steinke (2020), in integer arithmetic, so
no floating-point artefact separates neighbouring datasets and
[`set.seed()`](https://rdrr.io/r/base/Random.html) has no effect.
`epsilon` is used as a rational with denominator \\2^{20}\\, rounded
down.

## References

Canonne, Kamath and Steinke (2020), The Discrete Gaussian for
Differential Privacy, NeurIPS. Mironov (2012), On Significance of the
Least Significant Bits for Differential Privacy, CCS.

## Examples

``` r
# A single noised release of a true count of 42 (different every call).
morie_dp_laplace_count(true_count = 42, epsilon = 1.0)
#> [1] 42

# Smaller epsilon = stronger privacy = more noise.
morie_dp_laplace_count(42, epsilon = 0.1)
#> [1] 128
morie_dp_laplace_count(42, epsilon = 5.0)
#> [1] 42

# The mechanism is unbiased: averaging many releases returns about the truth
# (for illustration; releasing many answers spends many epsilons).
mean(replicate(500, morie_dp_laplace_count(42, epsilon = 1.0)))
#> [1] 41.99
```
