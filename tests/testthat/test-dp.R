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
  # 2^53 + 1 rounds back to 2^53, so 2^53 itself cannot carry a unit of noise
  expect_error(dplapcnt(2^53, epsilon = 1.0), "must not exceed 2\\^53")
  expect_error(dplaphist(c(1, 2^53), epsilon = 1.0), "must not exceed 2\\^53")
  expect_type(dplapcnt(2^53 - 1, epsilon = 1.0), "double")
  expect_type(dplaphist(c(1, 2^53 - 1), epsilon = 1.0), "double")
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

test_that("an infinite epsilon is refused in words before any draw (RD-L1)", {
  # Inf passed the old check and stopped inside the gcd loop with R's own
  # error about a missing value in a condition
  msg <- "`epsilon` must be a single positive number."
  expect_error(dplapcnt(5, Inf), msg, fixed = TRUE)
  expect_error(dplaphist(c(1, 2), Inf), msg, fixed = TRUE)
  expect_error(dpgmean(1:5, 0, 5, epsilon = Inf, delta = 1e-5), msg, fixed = TRUE)
  expect_error(dpbudget(Inf), msg, fixed = TRUE)
  expect_error(dplapcnt(5, -Inf), msg, fixed = TRUE)
  expect_error(dplapcnt(5, NaN), msg, fixed = TRUE)
})

test_that("a forked worker draws its own random bytes, not the parent's buffer", {
  rng <- rmoriedata:::.morie_dp_rng
  rmoriedata:::.morie_dp_bytes(8L)
  # what a fork leaves behind: the parent's buffer and position, under another process id
  rng$pid <- rng$pid + 1L
  buf <- rng$buf
  pos <- rng$pos
  got <- rmoriedata:::.morie_dp_bytes(64L)
  expect_identical(rng$pid, Sys.getpid())
  expect_false(identical(got, as.integer(buf[pos:(pos + 63L)])))
  skip_on_os("windows")
  skip_if_not_installed("parallel")
  dplapcnt(10, epsilon = 0.1)
  out <- parallel::mclapply(1:4, function(i) rmoriedata:::.morie_dp_bytes(16L),
                            mc.cores = 2L)
  expect_identical(anyDuplicated(out), 0L)
})

test_that("dplaphist keeps names, dims and a table's labels", {
  v <- dplaphist(c(a = 3, b = 4), epsilon = 1)
  expect_identical(names(v), c("a", "b"))
  tb <- table(c("x", "y", "y"), c("p", "q", "q"))
  out <- dplaphist(tb, epsilon = 1)
  expect_identical(dim(out), dim(tb))
  expect_identical(dimnames(out), dimnames(tb))
  expect_s3_class(out, "table")
  expect_identical(names(dplaphist(table(c("u", "v")), 1)), c("u", "v"))
})

test_that("a budget cannot be spent from a forked worker", {
  skip_on_os("windows")
  msg <- "a privacy budget cannot be spent from a forked worker"
  b <- dpbudget(1, delta = 1e-3)
  got <- parallel::mclapply(1:4, function(i) {
    tryCatch(dplapcnt(10, 0.9, budget = b), error = conditionMessage)
  }, mc.cores = 2)
  expect_true(all(startsWith(unlist(got), msg)))
  for (f in list(function() dplaphist(c(1, 2), 0.5, budget = b),
                 function() dpgmean(c(0.2, 0.4), 0, 1, 0.5, 1e-4, budget = b))) {
    job <- parallel::mcparallel(tryCatch(f(), error = conditionMessage))
    expect_true(startsWith(parallel::mccollect(job)[[1L]], msg))
  }
  # nothing was spent, and the parent still spends its budget
  expect_identical(dpspent(b)$releases, 0L)
  expect_identical(dpspent(b)$spent_epsilon, 0)
  expect_type(dplapcnt(10, 0.9, budget = b), "double")
  expect_equal(dpspent(b)$spent_epsilon, 0.9)
  # a worker's own budget is its own to spend
  own <- parallel::mclapply(1:2, function(i) {
    w <- dpbudget(1)
    dplapcnt(10, 0.5, budget = w)
    dpspent(w)$spent_epsilon
  }, mc.cores = 2)
  expect_identical(unlist(own), c(0.5, 0.5))
  # a budget read back in another process is refused the same way
  f <- tempfile(fileext = ".rds")
  saveRDS(b, f)
  job <- parallel::mcparallel(tryCatch(dplapcnt(1, 0.05, budget = readRDS(f)),
                                       error = conditionMessage))
  expect_true(startsWith(parallel::mccollect(job)[[1L]], msg))
})
