# SPDX-License-Identifier: AGPL-3.0-or-later

#' Draw from the Laplace distribution
#'
#' Internal helper. Inverse-CDF method on a Uniform(-0.5, 0.5) draw so
#' we don't pull in `extraDistr` or `VGAM`.
#'
#' @param n Number of draws.
#' @param scale Laplace scale parameter (`b`). Must be positive.
#' @return Numeric vector of length `n`.
#' @keywords internal
#' @noRd
.morie_rlaplace <- function(n, scale) {
  if (!is.numeric(scale) || length(scale) != 1L || is.na(scale) || scale <= 0) {
    stop("`scale` must be a single positive number.", call. = FALSE)
  }
  u <- stats::runif(n, min = -0.5, max = 0.5)
  -scale * sign(u) * log1p(-2 * abs(u))
}

#' Differentially-private count via the Laplace mechanism
#'
#' Adds Laplace noise calibrated to sensitivity / epsilon. Use when releasing
#' counts of records matching some predicate (e.g. number of UoF incidents
#' in a division-year). Sensitivity is hardcoded to 1: one record entering
#' or leaving the dataset changes the count by at most 1.
#'
#' Pure (\eqn{\epsilon}, 0)-differentially-private under the standard
#' add-or-remove-one neighbouring-databases definition.
#'
#' @param true_count Non-negative integer; the true count.
#' @param epsilon Privacy budget (smaller = more noise = stronger privacy).
#'   Typical range: 0.1 to 5.0.
#' @return A noised count (numeric, may be fractional or negative). Caller
#'   should usually clip to a non-negative integer for display:
#'   \code{round(pmax(0, x))}.
#' @export
#' @examples
#' set.seed(1)
#' # A single noised release of a true count of 42.
#' morie_dp_laplace_count(true_count = 42, epsilon = 1.0)
#'
#' # Smaller epsilon = stronger privacy = more noise.
#' morie_dp_laplace_count(42, epsilon = 0.1)   # noisier
#' morie_dp_laplace_count(42, epsilon = 5.0)   # closer to 42
#'
#' # The mechanism is unbiased: averaging many releases returns ~the truth.
#' mean(replicate(2000, morie_dp_laplace_count(42, epsilon = 1.0)))
#'
#' # For display, clip to a non-negative integer.
#' round(pmax(0, morie_dp_laplace_count(3, epsilon = 0.5)))
morie_dp_laplace_count <- function(true_count, epsilon) {
  if (length(true_count) != 1L || is.na(true_count) ||
        !is.numeric(true_count) || true_count < 0 ||
        true_count != as.integer(true_count)) {
    stop("`true_count` must be a single non-negative integer.", call. = FALSE)
  }
  if (length(epsilon) != 1L || is.na(epsilon) ||
        !is.numeric(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  sensitivity <- 1
  scale <- sensitivity / epsilon
  as.numeric(true_count) + .morie_rlaplace(1L, scale)
}

#' Differentially-private mean via the Gaussian mechanism with bounded inputs
#'
#' Releases an approximately (\eqn{\epsilon}, \eqn{\delta})-DP mean of a
#' bounded numeric vector. Sensitivity is derived from the user-asserted
#' bounds: changing one record can shift the sum by at most
#' \code{upper - lower}, so the mean's sensitivity is
#' \code{(upper - lower) / length(x)}.
#'
#' The noise standard deviation follows the classical analytic-Gaussian
#' calibration:
#' \deqn{\sigma = \frac{\Delta \cdot \sqrt{2 \ln(1.25/\delta)}}{\epsilon}.}
#'
#' @param x Numeric vector (no NAs).
#' @param lower,upper Hard bounds on `x`. Caller must guarantee
#'   \code{all(x >= lower & x <= upper)}; the function clips defensively
#'   but emits a warning if clipping was necessary.
#' @param epsilon,delta Privacy parameters. Standard recommendation:
#'   \code{delta < 1/length(x)}, \code{epsilon} in 0.1 to 5.0.
#' @return A noised mean (single numeric).
#' @export
#' @examples
#' set.seed(1)
#' x <- runif(1000, 0, 1)
#'
#' # A private mean of bounded data (bounds asserted by the caller).
#' morie_dp_gaussian_mean(x, lower = 0, upper = 1, epsilon = 1.0)
#' mean(x)                                  # the true mean, for comparison
#'
#' # `delta` controls the (epsilon, delta) guarantee; smaller = stronger.
#' morie_dp_gaussian_mean(x, 0, 1, epsilon = 1.0, delta = 1e-9)
#'
#' # Wider bounds raise sensitivity, so the same epsilon adds more noise.
#' morie_dp_gaussian_mean(x, lower = -5, upper = 5, epsilon = 1.0)
#'
#' # Out-of-range values are clipped to [lower, upper] (with a warning).
#' y <- c(x, 2, -1)
#' suppressWarnings(morie_dp_gaussian_mean(y, lower = 0, upper = 1, epsilon = 1))
morie_dp_gaussian_mean <- function(x, lower, upper, epsilon, delta = 1e-6) {
  if (!is.numeric(x) || length(x) == 0L) {
    stop("`x` must be a non-empty numeric vector.", call. = FALSE)
  }
  if (anyNA(x)) {
    stop("`x` must not contain NA.", call. = FALSE)
  }
  if (length(lower) != 1L || length(upper) != 1L ||
        !is.numeric(lower) || !is.numeric(upper) ||
        is.na(lower) || is.na(upper) || lower >= upper) {
    stop("`lower` and `upper` must be finite scalars with lower < upper.",
         call. = FALSE)
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

  n <- length(x)
  sensitivity <- (upper - lower) / n
  sigma <- sensitivity * sqrt(2 * log(1.25 / delta)) / epsilon
  mean(x) + stats::rnorm(1L, mean = 0, sd = sigma)
}

#' Differentially-private histogram via the Laplace mechanism
#'
#' Adds independent Laplace(\code{1/epsilon}) noise to each bin count.
#' Under the add-or-remove-one neighbouring-databases definition a single
#' record participates in exactly one bin, so the per-bin sensitivity is
#' 1 and the overall mechanism is (\eqn{\epsilon}, 0)-DP.
#'
#' @param counts Integer vector of non-negative bin counts.
#' @param epsilon Privacy budget (positive scalar).
#' @return A numeric vector of the same length as `counts`. May contain
#'   fractional or negative values. Caller is responsible for any post-hoc
#'   non-negativity / rounding before display.
#' @export
#' @examples
#' set.seed(1)
#' true <- c(120, 45, 8, 230, 17)
#'
#' # Independent Laplace noise added to every bin.
#' morie_dp_laplace_histogram(true, epsilon = 0.5)
#'
#' # Smaller epsilon = more noise per bin.
#' morie_dp_laplace_histogram(true, epsilon = 0.1)
#'
#' # Post-process for display: clip negatives, round to integers.
#' noisy <- morie_dp_laplace_histogram(true, epsilon = 1.0)
#' round(pmax(0, noisy))
#'
#' # Release a private histogram straight from tabulated data.
#' counts <- as.integer(table(complaint_sample$year))
#' morie_dp_laplace_histogram(counts, epsilon = 1.0)
morie_dp_laplace_histogram <- function(counts, epsilon) {
  if (!is.numeric(counts) || length(counts) == 0L || anyNA(counts) ||
        any(counts < 0) || any(counts != as.integer(counts))) {
    stop("`counts` must be a non-empty vector of non-negative integers.",
         call. = FALSE)
  }
  if (length(epsilon) != 1L || !is.numeric(epsilon) ||
        is.na(epsilon) || epsilon <= 0) {
    stop("`epsilon` must be a single positive number.", call. = FALSE)
  }
  scale <- 1 / epsilon
  as.numeric(counts) + .morie_rlaplace(length(counts), scale)
}
