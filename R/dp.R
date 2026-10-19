# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Differential privacy.
#
# One neighbouring relation for every mechanism here: two datasets are neighbours
# when one is the other with a single record added or removed (unbounded DP). The
# guarantees compose under that one relation, and dpbudget() adds them up
# (basic composition).
#
# Randomness comes from the operating system's CSPRNG
# (rmoriebricklayer::rndbytes()), never from R's seeded generator: a release
# drawn from set.seed()-able noise is a deterministic function of the true value and
# the seed. The counting mechanisms use the exact discrete Laplace sampler of
# Canonne, Kamath and Steinke (2020), integer arithmetic throughout, so the
# floating-point attack Mironov (2012) showed on the textbook continuous Laplace
# sampler has nothing to act on. The mean uses the analytic Gaussian mechanism of
# Balle and Wang (2018), which is valid for every epsilon (the classical calibration
# holds only for epsilon <= 1).

# ---- CSPRNG primitives -------------------------------------------------------

.morie_dp_rng <- new.env(parent = emptyenv())

.morie_dp_bytes <- function(n) {
  buf <- .morie_dp_rng$buf
  pos <- .morie_dp_rng$pos %||% 1L
  if (is.null(buf) || pos + n - 1L > length(buf)) {
    buf <- rmoriebricklayer::rndbytes(max(4096L, n))
    pos <- 1L
  }
  .morie_dp_rng$buf <- buf
  .morie_dp_rng$pos <- pos + n
  as.integer(buf[pos:(pos + n - 1L)])
}

# A uniform integer in [0, d), d a whole number below 2^47, by rejection (no modulo bias).
.morie_dp_unif_int <- function(d) {
  repeat {
    b <- .morie_dp_bytes(6L)
    x <- sum(b * 256^(5:0))
    lim <- floor(2^48 / d) * d
    if (x < lim) return(x %% d)
  }
}

# Bernoulli(num / den), exactly.
.morie_dp_bern <- function(num, den) .morie_dp_unif_int(den) < num

# Bernoulli(exp(-num / den)), exactly (Canonne, Kamath and Steinke 2020, Algorithm 1).
.morie_dp_bern_exp <- function(num, den) {
  if (num > den) {
    for (i in seq_len(num %/% den)) if (!.morie_dp_bern_exp(1, 1)) return(FALSE)
    return(.morie_dp_bern_exp(num %% den, den))
  }
  k <- 1
  while (.morie_dp_bern(num, den * k)) k <- k + 1
  k %% 2 == 1
}

# One draw from the discrete Laplace distribution P(y) proportional to exp(-|y| * s / t),
# s and t positive whole numbers (CKS 2020, Algorithm 2).
.morie_dp_dlaplace1 <- function(s, t) {
  repeat {
    u <- .morie_dp_unif_int(t)
    if (!.morie_dp_bern_exp(u, t)) next
    v <- 0
    while (.morie_dp_bern_exp(1, 1)) v <- v + 1
    y <- (u + t * v) %/% s
    b <- .morie_dp_bern(1, 2)
    if (b && y == 0) next
    return(if (b) -y else y)
  }
}

# epsilon as the rational s / t, rounded DOWN (never more budget than asked for).
.morie_dp_rational <- function(epsilon) {
  t <- 2^20
  s <- floor(epsilon * t)
  if (s < 1) {
    stop("`epsilon` is below 2^-20, the smallest this sampler represents.",
         call. = FALSE)
  }
  g <- .morie_gcd(s, t)
  c(s = s / g, t = t / g)
}
.morie_gcd <- function(a, b) {
  while (b > 0) {
    r <- a %% b
    a <- b
    b <- r
  }
  a
}

# A standard normal from 53-bit CSPRNG uniforms (Box-Muller).
.morie_dp_rnorm1 <- function() {
  u <- function() (.morie_dp_unif_int(2^47) + 0.5) / 2^47
  sqrt(-2 * log(u())) * cos(2 * pi * u())
}

# The analytic Gaussian mechanism's noise scale (Balle and Wang 2018, Theorem 8): the
# smallest sigma with Phi(D/(2s) - e*s/D) - exp(e) * Phi(-D/(2s) - e*s/D) <= delta.
.morie_dp_agm_sigma <- function(sensitivity, epsilon, delta) {
  f <- function(s) {
    a <- sensitivity / (2 * s)
    b <- epsilon * s / sensitivity
    stats::pnorm(a - b) - exp(epsilon + stats::pnorm(-a - b, log.p = TRUE))
  }
  lo <- sensitivity * 1e-6
  hi <- sensitivity
  while (f(hi) > delta) hi <- hi * 2
  for (i in 1:200) {
    mid <- sqrt(lo * hi)
    if (f(mid) > delta) lo <- mid else hi <- mid
    if (hi / lo < 1 + 1e-12) break
  }
  hi
}

# ---- privacy budget ----------------------------------------------------------

#' A privacy budget that DP releases are charged against
#'
#' Creates a budget of `epsilon` (and `delta`) that the mechanisms in this
#' package draw down when passed as `budget =`. Releases compose by basic
#' composition: the epsilons and deltas of the releases charged to one
#' budget add up, and a release that would exceed the budget is refused
#' before any noise is drawn. A hundred releases at `epsilon = 1` spend
#' `epsilon = 100`; a budget makes that visible and enforceable.
#'
#' @param epsilon Total epsilon available (positive).
#' @param delta Total delta available (0 for pure DP only).
#' @return An object of class `"dpbudget"` (an environment, so
#'   charges persist across calls).
#' @seealso [dpspent()]
#' @export
#' @examples
#' b <- dpbudget(epsilon = 2)
#' dplapcnt(42, epsilon = 1, budget = b)
#' dpspent(b)
#' # a second release at epsilon = 1.5 would exceed the remaining 1
#' try(dplapcnt(42, epsilon = 1.5, budget = b))
dpbudget <- function(epsilon, delta = 0) {
  if (length(epsilon) != 1L || !is.numeric(epsilon) || is.na(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  if (length(delta) != 1L || !is.numeric(delta) || is.na(delta) ||
      delta < 0 || delta >= 1) {
    stop("`delta` must be a single number in [0, 1).", call. = FALSE)
  }
  b <- new.env(parent = emptyenv())
  b$epsilon <- epsilon
  b$delta <- delta
  b$spent_epsilon <- 0
  b$spent_delta <- 0
  b$releases <- 0L
  class(b) <- "dpbudget"
  b
}

#' What a privacy budget has spent
#'
#' @param budget A budget from [dpbudget()].
#' @return A list: `epsilon`, `delta` (the totals), `spent_epsilon`,
#'   `spent_delta`, `remaining_epsilon`, `remaining_delta`, `releases`.
#' @export
#' @examples
#' b <- dpbudget(1)
#' invisible(dplaphist(c(10, 20), epsilon = 0.25, budget = b))
#' dpspent(b)$remaining_epsilon
dpspent <- function(budget) {
  .morie_dp_check_budget(budget)
  list(epsilon = budget$epsilon, delta = budget$delta,
       spent_epsilon = budget$spent_epsilon, spent_delta = budget$spent_delta,
       remaining_epsilon = budget$epsilon - budget$spent_epsilon,
       remaining_delta = budget$delta - budget$spent_delta,
       releases = budget$releases)
}

#' @export
print.dpbudget <- function(x, ...) {
  s <- dpspent(x)
  cat(sprintf(paste0("<dpbudget> epsilon %.4g of %.4g spent, ",
                     "delta %.3g of %.3g, %d release(s)\n"),
              s$spent_epsilon, s$epsilon, s$spent_delta, s$delta, s$releases))
  invisible(x)
}

.morie_dp_charge <- function(budget, epsilon, delta = 0) {
  if (is.null(budget)) return(invisible())
  .morie_dp_check_budget(budget)
  tol <- 1e-12
  if (budget$spent_epsilon + epsilon > budget$epsilon + tol ||
      budget$spent_delta + delta > budget$delta + tol) {
    stop(sprintf(paste0("this release (epsilon %.4g, delta %.3g) exceeds the ",
                        "remaining budget (epsilon %.4g, delta %.3g); nothing was ",
                        "released."),
                 epsilon, delta, budget$epsilon - budget$spent_epsilon,
                 budget$delta - budget$spent_delta), call. = FALSE)
  }
  budget$spent_epsilon <- budget$spent_epsilon + epsilon
  budget$spent_delta <- budget$spent_delta + delta
  budget$releases <- budget$releases + 1L
  invisible()
}

.morie_dp_check_budget <- function(budget) {
  if (!inherits(budget, "dpbudget")) {
    stop("`budget` must come from dpbudget().", call. = FALSE)
  }
  invisible()
}

# ---- mechanisms --------------------------------------------------------------

#' Differentially-private count via the discrete Laplace mechanism
#'
#' Releases a count with discrete Laplace noise, \eqn{P(y) \propto
#' e^{-\epsilon |y|}}, so the release is a whole number. Use it for the
#' number of records matching a predicate (for example incidents in a
#' division-year). Adding or removing one record changes the count by at
#' most 1, and the release is pure \eqn{\epsilon}-DP under that
#' add-or-remove-one relation, the one every mechanism in this package uses.
#'
#' The noise is drawn from the operating system's CSPRNG with the exact
#' sampler of Canonne, Kamath and Steinke (2020), in integer arithmetic, so
#' no floating-point artefact separates neighbouring datasets and
#' `set.seed()` has no effect. `epsilon` is used as a rational with
#' denominator \eqn{2^{20}}, rounded down.
#'
#' @param truecnt Non-negative integer; the true count.
#' @param epsilon Privacy loss (smaller means more noise, stronger privacy).
#' @param budget Optional [dpbudget()] to charge `epsilon` against.
#' @return The noised count, a whole number (it can be negative; clip with
#'   \code{pmax(0, x)} for display, which is post-processing and costs no
#'   privacy).
#' @references Canonne, Kamath and Steinke (2020), The Discrete Gaussian for
#'   Differential Privacy, NeurIPS. Mironov (2012), On Significance of the
#'   Least Significant Bits for Differential Privacy, CCS.
#' @export
#' @examples
#' # A single noised release of a true count of 42 (different every call).
#' dplapcnt(truecnt = 42, epsilon = 1.0)
#'
#' # Smaller epsilon = stronger privacy = more noise.
#' dplapcnt(42, epsilon = 0.1)
#' dplapcnt(42, epsilon = 5.0)
#'
#' # The mechanism is unbiased: averaging many releases returns about the truth
#' # (for illustration; releasing many answers spends many epsilons).
#' mean(replicate(500, dplapcnt(42, epsilon = 1.0)))
dplapcnt <- function(truecnt, epsilon, budget = NULL) {
  if (length(truecnt) != 1L || !is.numeric(truecnt) ||
    !is.finite(truecnt) || truecnt < 0 ||
    truecnt != floor(truecnt)) {
    stop("`truecnt` must be a single non-negative integer.", call. = FALSE)
  }
  # above 2^53 a double cannot carry the count and a unit of noise distinctly
  if (truecnt > 2^53) {
    stop("`truecnt` must not exceed 2^53: the noise would be lost in ",
         "the representation and the release would equal the true count.",
         call. = FALSE)
  }
  if (length(epsilon) != 1L || is.na(epsilon) ||
    !is.numeric(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  q <- .morie_dp_rational(epsilon)
  .morie_dp_charge(budget, epsilon)
  as.numeric(truecnt) + .morie_dp_dlaplace1(q[["s"]], q[["t"]])
}

#' Differentially-private histogram via the discrete Laplace mechanism
#'
#' Adds independent discrete Laplace noise, \eqn{P(y) \propto
#' e^{-\epsilon |y|}}, to each bin count. Adding or removing one record
#' changes exactly one bin by 1, so the whole histogram is pure
#' \eqn{\epsilon}-DP under the add-or-remove-one relation. Noise and sampler
#' as in [dplapcnt()].
#'
#' @param counts Vector of non-negative whole-number bin counts.
#' @param epsilon Privacy loss for the whole histogram (positive scalar).
#' @param budget Optional [dpbudget()] to charge `epsilon` against.
#' @return A numeric vector of whole numbers, the same length as `counts`
#'   (values may be negative; clip for display).
#' @export
#' @examples
#' true <- c(120, 45, 8, 230, 17)
#' dplaphist(true, epsilon = 0.5)
#'
#' # Post-process for display: clip negatives (costs no privacy).
#' pmax(0, dplaphist(true, epsilon = 1.0))
#'
#' # Release a private histogram straight from tabulated data.
#' counts <- as.integer(table(complaint_sample$year))
#' dplaphist(counts, epsilon = 1.0)
dplaphist <- function(counts, epsilon, budget = NULL) {
  if (!is.numeric(counts) || length(counts) == 0L || any(!is.finite(counts)) ||
    any(counts < 0) || any(counts != floor(counts))) {
    stop("`counts` must be a non-empty vector of non-negative integers.",
      call. = FALSE
    )
  }
  if (any(counts > 2^53)) {
    stop("`counts` must not exceed 2^53: the noise would be lost in ",
         "the representation and the release would equal the true counts.",
         call. = FALSE)
  }
  if (length(epsilon) != 1L || !is.numeric(epsilon) ||
    is.na(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  q <- .morie_dp_rational(epsilon)
  .morie_dp_charge(budget, epsilon)
  noise <- vapply(seq_along(counts), function(i) {
    .morie_dp_dlaplace1(q[["s"]], q[["t"]])
  }, numeric(1))
  as.numeric(counts) + noise
}

#' Differentially-private mean via the analytic Gaussian mechanism
#'
#' Releases an \eqn{(\epsilon, \delta)}-DP mean of a bounded numeric vector,
#' as a noised sum over a noised count, each with half the budget. Under the
#' add-or-remove-one relation every mechanism here uses, one record moves
#' the clipped sum by at most \code{max(abs(lower), abs(upper))} and the
#' count by 1, so neither the sum nor `length(x)` is treated as public.
#'
#' Each half is calibrated with the analytic Gaussian mechanism (Balle and
#' Wang 2018), which holds for every \eqn{\epsilon > 0}; the classical
#' bound \eqn{\sigma = \Delta \sqrt{2 \ln(1.25/\delta)}/\epsilon} holds only
#' for \eqn{\epsilon \le 1} and is not used. Noise comes from the operating
#' system's CSPRNG; `set.seed()` has no effect.
#'
#' @param x Numeric vector (no NAs).
#' @param lower,upper Hard bounds on `x`. Values outside are clipped (with a
#'   warning); the bounds must be chosen without looking at the data.
#' @param epsilon,delta Privacy parameters for the whole release.
#'   `delta` should be well below `1 / length(x)`.
#' @param budget Optional [dpbudget()] to charge against.
#' @return A noised mean (single numeric).
#' @references Balle and Wang (2018), Improving the Gaussian Mechanism for
#'   Differential Privacy: Analytical Calibration and Optimal Denoising, ICML.
#' @export
#' @examples
#' x <- runif(1000, 0, 1)
#' dpgmean(x, lower = 0, upper = 1, epsilon = 1.0)
#' mean(x) # the true mean, for comparison
#'
#' # Wider bounds raise sensitivity, so the same epsilon adds more noise.
#' dpgmean(x, lower = -5, upper = 5, epsilon = 1.0)
dpgmean <- function(x, lower, upper, epsilon, delta = 1e-6,
                                   budget = NULL) {
  if (!is.numeric(x) || length(x) == 0L) {
    stop("`x` must be a non-empty numeric vector.", call. = FALSE)
  }
  if (anyNA(x)) {
    stop("`x` must not contain NA.", call. = FALSE)
  }
  if (length(lower) != 1L || length(upper) != 1L ||
    !is.numeric(lower) || !is.numeric(upper) ||
    !is.finite(lower) || !is.finite(upper) || lower >= upper) {
    stop("`lower` and `upper` must be finite scalars with lower < upper.",
      call. = FALSE
    )
  }
  if (length(epsilon) != 1L || !is.numeric(epsilon) ||
    is.na(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  if (length(delta) != 1L || !is.numeric(delta) ||
    is.na(delta) || delta <= 0 || delta >= 1) {
    stop("`delta` must be a single number in (0, 1).", call. = FALSE)
  }
  if (any(x < lower | x > upper)) {
    warning(
      "`x` contains values outside [lower, upper]; clipping to bounds.",
      call. = FALSE
    )
    x <- pmin(pmax(x, lower), upper)
  }
  .morie_dp_charge(budget, epsilon, delta)
  sens_sum <- max(abs(lower), abs(upper))
  sd_sum <- .morie_dp_agm_sigma(sens_sum, epsilon / 2, delta / 2)
  sd_n <- .morie_dp_agm_sigma(1, epsilon / 2, delta / 2)
  noisy_sum <- sum(x) + sd_sum * .morie_dp_rnorm1()
  noisy_n <- length(x) + sd_n * .morie_dp_rnorm1()
  min(max(noisy_sum / max(noisy_n, 1), lower), upper)
}
