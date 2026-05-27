\name{morie_l_diversity_verify}
\alias{morie_l_diversity_verify}
\title{l-diversity verification}
\usage{
morie_l_diversity_verify(data, quasi_identifiers, sensitive, l = 3)
}
\arguments{
\item{data}{data.frame.}

\item{quasi_identifiers}{Character vector of QI column names.}

\item{sensitive}{Name of the sensitive-attribute column.}

\item{l}{Minimum number of distinct sensitive values per class.
Default 3.}
}
\value{
A list with class \code{"morie_l_div"} containing:
\describe{
  \item{\code{satisfies}}{logical.}
  \item{\code{l}}{the threshold used.}
  \item{\code{min_diversity}}{integer, lowest per-class distinct count.}
  \item{\code{n_classes}}{integer.}
  \item{\code{n_violations}}{integer, classes below the threshold.}
  \item{\code{violating_classes}}{data.frame of class keys plus their
    \code{.diversity} count.}
  \item{\code{summary}}{human-readable.}
}
}
\description{
Checks whether a data.frame satisfies l-diversity: within each
equivalence class defined by the quasi-identifiers, the sensitive
attribute must take at least \code{l} distinct values.
}
\examples{
df <- data.frame(
  age = c(25, 25, 25, 25, 32, 32, 32),
  sex = c("F", "F", "F", "F", "M", "M", "M"),
  dx  = c("A", "B", "C", "A", "X", "Y", "Z")
)
morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 3)
}
