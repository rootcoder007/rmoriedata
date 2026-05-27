\name{morie_cell_suppress}
\alias{morie_cell_suppress}
\title{Cell suppression with optional complementary suppression}
\usage{
morie_cell_suppress(tbl, threshold = 5, return_complementary = TRUE)
}
\arguments{
\item{tbl}{A numeric matrix or 2-D table of counts. Will be coerced to
matrix; row/column names are preserved.}

\item{threshold}{Minimum count to remain unsuppressed. Default 5.}

\item{return_complementary}{Logical; if \code{TRUE} (default), apply
complementary suppression so primary-suppressed cells can't be
recovered from marginal sums.}
}
\value{
A list with class \code{"morie_cell_suppress"}:
\describe{
  \item{\code{suppressed}}{numeric matrix, suppressed cells set to NA.}
  \item{\code{primary_mask}}{logical matrix, TRUE for primary suppressions.}
  \item{\code{complementary_mask}}{logical matrix, TRUE for complementary
    suppressions (all FALSE when \code{return_complementary = FALSE}).}
  \item{\code{n_primary}}{integer.}
  \item{\code{n_complementary}}{integer.}
  \item{\code{threshold}}{the threshold used.}
}
}
\description{
Standard StatCan / open-data complementary-suppression: identifies
counts below \code{threshold}, suppresses them by setting to \code{NA},
and (if \code{return_complementary = TRUE}) also suppresses the smallest
other count in each affected row and column so the suppressed value
can't be reconstructed from marginal sums.
}
\details{
Only finite numeric cells are eligible for suppression. \code{NA} cells
in the input pass through unchanged.
}
\examples{
tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60), nrow = 3,
              dimnames = list(c("A","B","C"), c("X","Y","Z")))
morie_cell_suppress(tbl, threshold = 5)
}
