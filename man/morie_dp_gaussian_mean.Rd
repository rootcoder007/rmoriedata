\name{morie_dp_gaussian_mean}
\alias{morie_dp_gaussian_mean}
\title{Differentially-private mean via the Gaussian mechanism with bounded inputs}
\usage{
morie_dp_gaussian_mean(x, lower, upper, epsilon, delta = 1e-6)
}
\arguments{
\item{x}{Numeric vector (no NAs).}

\item{lower, upper}{Hard bounds on \code{x}. Caller must guarantee
\code{all(x >= lower & x <= upper)}; the function clips defensively
but emits a warning if clipping was necessary.}

\item{epsilon, delta}{Privacy parameters. Standard recommendation:
\code{delta < 1/length(x)}, \code{epsilon} in 0.1 to 5.0.}
}
\value{
A noised mean (single numeric).
}
\description{
Releases an approximately (\eqn{\epsilon}, \eqn{\delta})-DP mean of a
bounded numeric vector. Sensitivity is derived from the user-asserted
bounds: changing one record can shift the sum by at most
\code{upper - lower}, so the mean's sensitivity is
\code{(upper - lower) / length(x)}.
}
\details{
The noise standard deviation follows the classical analytic-Gaussian
calibration:
\deqn{\sigma = \frac{\Delta \cdot \sqrt{2 \ln(1.25/\delta)}}{\epsilon}.}
}
\examples{
set.seed(1)
x <- runif(1000, 0, 1)
morie_dp_gaussian_mean(x, lower = 0, upper = 1, epsilon = 1.0)
}
