# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("morie_dp_laplace_count mean converges to true count", {
  set.seed(20260526)
  n_draws <- 5000L
  draws <- replicate(n_draws, morie_dp_laplace_count(100L, epsilon = 1.0))
  expect_equal(mean(draws), 100, tolerance = 0.05)
})

test_that("variance scales as 2 / epsilon^2 for the Laplace mechanism", {
  set.seed(20260526)
  n_draws <- 5000L
  draws_high <- replicate(n_draws, morie_dp_laplace_count(50L, epsilon = 2.0))
  draws_low  <- replicate(n_draws, morie_dp_laplace_count(50L, epsilon = 0.5))
  var_high <- stats::var(draws_high)
  var_low  <- stats::var(draws_low)
  # Smaller epsilon -> larger variance.
  expect_gt(var_low, var_high)
  # Theoretical: var = 2 / epsilon^2; ratio should be ~16x for eps 2.0 vs 0.5.
  expect_equal(var_low / var_high, 16, tolerance = 0.25)
})

test_that("morie_dp_laplace_count edge-case input validation", {
  expect_error(morie_dp_laplace_count(NA, epsilon = 1.0),
               "non-negative integer")
  expect_error(morie_dp_laplace_count(-1, epsilon = 1.0),
               "non-negative integer")
  expect_error(morie_dp_laplace_count(3.5, epsilon = 1.0),
               "non-negative integer")
  expect_error(morie_dp_laplace_count(10, epsilon = 0),
               "positive number")
  expect_error(morie_dp_laplace_count(10, epsilon = -1),
               "positive number")
  expect_error(morie_dp_laplace_count(10, epsilon = NA),
               "positive number")
})

test_that("morie_dp_gaussian_mean converges to the true mean", {
  set.seed(20260526)
  x <- stats::runif(500, 0, 1)
  truth <- mean(x)
  draws <- replicate(
    2000L,
    morie_dp_gaussian_mean(x, lower = 0, upper = 1,
                           epsilon = 1.0, delta = 1e-5)
  )
  expect_equal(mean(draws), truth, tolerance = 0.02)
})

test_that("morie_dp_gaussian_mean clips out-of-bounds inputs and warns", {
  set.seed(1)
  x <- c(0.5, 2, -0.5)
  expect_warning(
    morie_dp_gaussian_mean(x, lower = 0, upper = 1,
                           epsilon = 1.0, delta = 1e-5),
    "outside"
  )
})

test_that("morie_dp_gaussian_mean validates inputs", {
  expect_error(
    morie_dp_gaussian_mean(numeric(0), 0, 1, 1, 1e-6),
    "non-empty"
  )
  expect_error(
    morie_dp_gaussian_mean(c(1, NA), 0, 1, 1, 1e-6),
    "NA"
  )
  expect_error(
    morie_dp_gaussian_mean(c(0.5), 1, 0, 1, 1e-6),
    "lower < upper"
  )
  expect_error(
    morie_dp_gaussian_mean(c(0.5), 0, 1, -1, 1e-6),
    "positive number"
  )
  expect_error(
    morie_dp_gaussian_mean(c(0.5), 0, 1, 1, 1.5),
    "in \\(0, 1\\)"
  )
})

test_that("morie_dp_laplace_histogram approximately preserves total", {
  set.seed(20260526)
  counts <- c(120, 45, 8, 230, 17, 50, 90, 12)
  total <- sum(counts)
  draws <- replicate(2000L, sum(morie_dp_laplace_histogram(counts, epsilon = 1.0)))
  expect_equal(mean(draws), total, tolerance = 0.02 * total)
})

test_that("morie_dp_laplace_histogram validates inputs", {
  expect_error(
    morie_dp_laplace_histogram(integer(0), 1),
    "non-empty"
  )
  expect_error(
    morie_dp_laplace_histogram(c(1, -2, 3), 1),
    "non-negative integers"
  )
  expect_error(
    morie_dp_laplace_histogram(c(1, 1.5, 3), 1),
    "non-negative integers"
  )
  expect_error(
    morie_dp_laplace_histogram(c(1, 2, 3), -1),
    "positive number"
  )
})
