\name{morie_k_anonymity_verify}
\alias{morie_k_anonymity_verify}
\title{k-anonymity verification}
\usage{
morie_k_anonymity_verify(data, quasi_identifiers, k = 5)
}
\arguments{
\item{data}{data.frame.}

\item{quasi_identifiers}{Character vector of column names.}

\item{k}{Minimum equivalence-class size. Default 5 (a common
public-health / open-data threshold).}
}
\value{
A list with class \code{"morie_k_anon"} containing:
\describe{
  \item{\code{satisfies}}{logical, whether the dataset is k-anonymous.}
  \item{\code{k}}{the threshold used.}
  \item{\code{min_class_size}}{integer, size of the smallest class.}
  \item{\code{n_classes}}{integer, total number of equivalence classes.}
  \item{\code{n_violations}}{integer, number of classes below the threshold.}
  \item{\code{violating_classes}}{data.frame of class keys plus their
    \code{.n} sizes (empty data.frame when none).}
  \item{\code{summary}}{human-readable one-line summary.}
}
}
\description{
Checks whether a data.frame satisfies k-anonymity over the supplied
quasi-identifier columns. A dataset is k-anonymous if every combination
of quasi-identifier values appears in at least \code{k} rows.
}
\examples{
df <- data.frame(
  age = c(25, 25, 25, 32, 32, 40),
  sex = c("F", "F", "F", "M", "M", "M")
)
morie_k_anonymity_verify(df, c("age", "sex"), k = 2)
}
