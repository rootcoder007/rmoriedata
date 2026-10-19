# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("dplapcnt mean converges to true count", {
  set.seed(20260526)
  n_draws <- 5000L
  draws <- replicate(n_draws, dplapcnt(100L, epsilon = 1.0))
  expect_equal(mean(draws), 100, tolerance = 0.05)
})

test_that("the variance is the discrete Laplace one, 2p / (1 - p)^2 with p = exp(-eps)", {
  n_draws <- 5000L
  draws_high <- replicate(n_draws, dplapcnt(50L, epsilon = 2.0))
  draws_low <- replicate(n_draws, dplapcnt(50L, epsilon = 0.5))
  dvar <- function(eps) {
    p <- exp(-eps)
    2 * p / (1 - p)^2
  }
  expect_gt(stats::var(draws_low), stats::var(draws_high))
  expect_equal(stats::var(draws_low), dvar(0.5), tolerance = 0.15)
  expect_equal(stats::var(draws_high), dvar(2.0), tolerance = 0.15)
  # releases are whole numbers: no floating-point residue to tell neighbours apart
  expect_true(all(draws_low == round(draws_low)))
})

test_that("the noise does not follow set.seed (OS CSPRNG)", {
  same <- vapply(1:20, function(i) {
    set.seed(1)
    a <- dplapcnt(1000, epsilon = 0.1)
    set.seed(1)
    b <- dplapcnt(1000, epsilon = 0.1)
    a == b
  }, logical(1))
  # at epsilon 0.1 two independent draws agree with probability about 0.05
  expect_lt(sum(same), 8)
})

test_that("the Gaussian mean uses the analytic calibration, valid above epsilon 1", {
  # Balle and Wang (2018): sigma for epsilon 1, delta 1e-5, sensitivity 1 is 3.7306
  s <- rmoriedata:::.morie_dp_agm_sigma(1, 1, 1e-5)
  expect_equal(s, 3.7306, tolerance = 1e-4)
  # the defining condition holds with equality at the returned sigma
  a <- 1 / (2 * s)
  at_sigma <- stats::pnorm(a - s) - exp(1) * stats::pnorm(-a - s)
  expect_equal(at_sigma, 1e-5, tolerance = 1e-6)
  # above epsilon 1 the classical bound is invalid; the analytic one still satisfies delta
  s5 <- rmoriedata:::.morie_dp_agm_sigma(1, 5, 1e-5)
  a5 <- 1 / (2 * s5)
  b5 <- 5 * s5
  expect_lte(stats::pnorm(a5 - b5) - exp(5) * stats::pnorm(-a5 - b5), 1e-5 * (1 + 1e-6))
  expect_true(is.finite(dpgmean(runif(100), 0, 1, epsilon = 5)))
})

test_that("a privacy budget is charged and enforced", {
  b <- dpbudget(epsilon = 2, delta = 1e-5)
  dplapcnt(10, epsilon = 1, budget = b)
  dplaphist(c(1, 2, 3), epsilon = 0.5, budget = b)
  s <- dpspent(b)
  expect_equal(s$spent_epsilon, 1.5)
  expect_equal(s$releases, 2L)
  over <- "exceeds the remaining budget"
  expect_error(dplapcnt(10, epsilon = 1, budget = b), over)
  expect_equal(dpspent(b)$spent_epsilon, 1.5)
  expect_error(
    dpgmean(runif(10), 0, 1, epsilon = 0.5, delta = 1e-4, budget = b),
    over
  )
  expect_output(print(b), "epsilon 1.5 of 2 spent")
  expect_error(dpbudget(0), "positive")
  expect_error(dpspent(list()), "dpbudget")
})

test_that("dplapcnt edge-case input validation", {
  expect_error(
    dplapcnt(NA, epsilon = 1.0),
    "non-negative integer"
  )
  expect_error(
    dplapcnt(-1, epsilon = 1.0),
    "non-negative integer"
  )
  expect_error(
    dplapcnt(3.5, epsilon = 1.0),
    "non-negative integer"
  )
  expect_error(
    dplapcnt(10, epsilon = 0),
    "positive number"
  )
  expect_error(
    dplapcnt(10, epsilon = -1),
    "positive number"
  )
  expect_error(
    dplapcnt(10, epsilon = NA),
    "positive number"
  )
  # a count a double cannot hold with room for noise: 1e300 + Laplace(1) is 1e300
  expect_error(
    dplapcnt(1e300, epsilon = 1.0),
    "must not exceed 2\\^53"
  )
  expect_error(
    dplapcnt(2^53 + 2, epsilon = 1.0),
    "must not exceed 2\\^53"
  )
  expect_type(dplapcnt(2^53, epsilon = 1.0), "double")
})

test_that("dpgmean converges to the true mean", {
  set.seed(20260526)
  x <- stats::runif(500, 0, 1)
  truth <- mean(x)
  draws <- replicate(
    2000L,
    dpgmean(x,
      lower = 0, upper = 1,
      epsilon = 1.0, delta = 1e-5
    )
  )
  expect_equal(mean(draws), truth, tolerance = 0.02)
})

test_that("dpgmean clips out-of-bounds inputs and warns", {
  set.seed(1)
  x <- c(0.5, 2, -0.5)
  expect_warning(
    dpgmean(x,
      lower = 0, upper = 1,
      epsilon = 1.0, delta = 1e-5
    ),
    "outside"
  )
})

test_that("dpgmean validates inputs", {
  expect_error(
    dpgmean(numeric(0), 0, 1, 1, 1e-6),
    "non-empty"
  )
  expect_error(
    dpgmean(c(1, NA), 0, 1, 1, 1e-6),
    "NA"
  )
  expect_error(
    dpgmean(c(0.5), 1, 0, 1, 1e-6),
    "lower < upper"
  )
  expect_error(
    dpgmean(c(0.5), 0, 1, -1, 1e-6),
    "positive number"
  )
  expect_error(
    dpgmean(c(0.5), 0, 1, 1, 1.5),
    "in \\(0, 1\\)"
  )
})

test_that("dplaphist approximately preserves total", {
  set.seed(20260526)
  counts <- c(120, 45, 8, 230, 17, 50, 90, 12)
  total <- sum(counts)
  draws <- replicate(2000L, sum(dplaphist(counts, epsilon = 1.0)))
  expect_equal(mean(draws), total, tolerance = 0.02 * total)
})

test_that("dplaphist validates inputs", {
  expect_error(
    dplaphist(integer(0), 1),
    "non-empty"
  )
  expect_error(
    dplaphist(c(1, -2, 3), 1),
    "non-negative integers"
  )
  expect_error(
    dplaphist(c(1, 1.5, 3), 1),
    "non-negative integers"
  )
  expect_error(
    dplaphist(c(1, 2, 3), -1),
    "positive number"
  )
  expect_error(
    dplaphist(c(1, 1e300), 1),
    "must not exceed 2\\^53"
  )
})

test_that("dpgmean rejects infinite bounds", {
  expect_error(dpgmean(1:5, -Inf, Inf, epsilon = 1), "finite")
  expect_error(dpgmean(1:5, 0, Inf, epsilon = 1), "finite")
})

test_that("a non-finite count is refused in words, with no coercion warning", {
  expect_no_warning(expect_error(dplapcnt(Inf, 1),
                                 "single non-negative integer"))
  expect_no_warning(expect_error(dplaphist(c(1, Inf), 1),
                                 "non-negative integers"))
  # a whole count beyond R's integer range is still a count; beyond 2^53 the
  # noise would vanish in the representation, so it is refused
  set.seed(1)
  expect_true(is.finite(dplapcnt(2^40, 1)))
  expect_error(dplapcnt(1e300, 1), "must not exceed 2\\^53")
})
