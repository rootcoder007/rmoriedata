# Differentially-private mean via the Gaussian mechanism with bounded inputs

Releases an approximately (\\\epsilon\\, \\\delta\\)-DP mean of a
bounded numeric vector. Sensitivity is derived from the user-asserted
bounds: changing one record can shift the sum by at most
`upper - lower`, so the mean's sensitivity is
`(upper - lower) / length(x)`.

## Usage

``` r
morie_dp_gaussian_mean(x, lower, upper, epsilon, delta = 1e-06)
```

## Arguments

- x:

  Numeric vector (no NAs).

- lower, upper:

  Hard bounds on \`x\`. Caller must guarantee
  `all(x >= lower & x <= upper)`; the function clips defensively but
  emits a warning if clipping was necessary.

- epsilon, delta:

  Privacy parameters. Standard recommendation: `delta < 1/length(x)`,
  `epsilon` in 0.1 to 5.0.

## Value

A noised mean (single numeric).

## Details

The noise standard deviation follows the classical analytic-Gaussian
calibration: \$\$\sigma = \frac{\Delta \cdot \sqrt{2
\ln(1.25/\delta)}}{\epsilon}.\$\$

## Examples

``` r
set.seed(1)
x <- runif(1000, 0, 1)

# A private mean of bounded data (bounds asserted by the caller).
morie_dp_gaussian_mean(x, lower = 0, upper = 1, epsilon = 1.0)
#> [1] 0.5001013
mean(x)                                  # the true mean, for comparison
#> [1] 0.4996917

# `delta` controls the (epsilon, delta) guarantee; smaller = stronger.
morie_dp_gaussian_mean(x, 0, 1, epsilon = 1.0, delta = 1e-9)
#> [1] 0.4977702

# Wider bounds raise sensitivity, so the same epsilon adds more noise.
morie_dp_gaussian_mean(x, lower = -5, upper = 5, epsilon = 1.0)
#> [1] 0.436994

# Out-of-range values are clipped to [lower, upper] (with a warning).
y <- c(x, 2, -1)
suppressWarnings(morie_dp_gaussian_mean(y, lower = 0, upper = 1, epsilon = 1))
#> [1] 0.499752
```
