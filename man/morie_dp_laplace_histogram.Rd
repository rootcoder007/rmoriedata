\name{morie_dp_laplace_histogram}
\alias{morie_dp_laplace_histogram}
\title{Differentially-private histogram via the Laplace mechanism}
\usage{
morie_dp_laplace_histogram(counts, epsilon)
}
\arguments{
\item{counts}{Integer vector of non-negative bin counts.}

\item{epsilon}{Privacy budget (positive scalar).}
}
\value{
A numeric vector of the same length as \code{counts}. May contain
fractional or negative values. Caller is responsible for any post-hoc
non-negativity / rounding before display.
}
\description{
Adds independent Laplace(\code{1/epsilon}) noise to each bin count.
Under the add-or-remove-one neighbouring-databases definition a single
record participates in exactly one bin, so the per-bin sensitivity is
1 and the overall mechanism is (\eqn{\epsilon}, 0)-DP.
}
\examples{
set.seed(1)
morie_dp_laplace_histogram(c(120, 45, 8, 230, 17), epsilon = 0.5)
}
