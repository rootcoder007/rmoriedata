# Differentially-private mean via the analytic Gaussian mechanism

Releases an \\(\epsilon, \delta)\\-DP mean of a bounded numeric vector,
as a noised sum over a noised count, each with half the budget. Under
the add-or-remove-one relation every mechanism here uses, one record
moves the clipped sum by at most `max(abs(lower), abs(upper))` and the
count by 1, so neither the sum nor `length(x)` is treated as public.

## Usage

``` r
morie_dp_gaussian_mean(x, lower, upper, epsilon, delta = 1e-06, budget = NULL)
```

## Arguments

- x:

  Numeric vector (no NAs).

- lower, upper:

  Hard bounds on `x`. Values outside are clipped (with a warning); the
  bounds must be chosen without looking at the data.

- epsilon, delta:

  Privacy parameters for the whole release. `delta` should be well below
  `1 / length(x)`.

- budget:

  Optional
  [`morie_dp_budget()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_budget.md)
  to charge against.

## Value

A noised mean (single numeric).

## Details

Each half is calibrated with the analytic Gaussian mechanism (Balle and
Wang 2018), which holds for every \\\epsilon \> 0\\; the classical bound
\\\sigma = \Delta \sqrt{2 \ln(1.25/\delta)}/\epsilon\\ holds only for
\\\epsilon \le 1\\ and is not used. Noise comes from the operating
system's CSPRNG; [`set.seed()`](https://rdrr.io/r/base/Random.html) has
no effect.

## References

Balle and Wang (2018), Improving the Gaussian Mechanism for Differential
Privacy: Analytical Calibration and Optimal Denoising, ICML.

## Examples

``` r
x <- runif(1000, 0, 1)
morie_dp_gaussian_mean(x, lower = 0, upper = 1, epsilon = 1.0)
#> [1] 0.495105
mean(x) # the true mean, for comparison
#> [1] 0.5060361

# Wider bounds raise sensitivity, so the same epsilon adds more noise.
morie_dp_gaussian_mean(x, lower = -5, upper = 5, epsilon = 1.0)
#> [1] 0.5278112
```
