% Generated manually (roxygenise blocked by a pre-existing unrelated
% load-time error); keep in sync with R/load_cihi.R.
\name{fetch_cihi_table}
\alias{fetch_cihi_table}
\title{Download a CIHI data table (live, with Wayback fallback)}
\usage{
fetch_cihi_table(which, dest = NULL, timeout = 120L)
}
\arguments{
\item{which}{A row index into \code{load_cihi_data_tables()}, or a
string matched (case-insensitively, as a substring) against table
titles. Must resolve to exactly one table.}

\item{dest}{Destination file path. Default: a tempfile with the table's
own extension.}

\item{timeout}{Per-request timeout, seconds.}
}
\value{
The \code{dest} path, invisibly. Errors if both the live URL and its
Wayback fallback fail.
}
\description{
Resolves a CIHI table from the bundled catalogue and downloads it to
\code{dest}, falling back to the Internet Archive snapshot if the live
CIHI URL has rotated or been removed. The download + fallback runs
through \pkg{rmoriebricklayer}'s shared C++/libcurl foundation
(\code{\link[rmoriebricklayer]{bricklayer_fetch}}), the same engine
\pkg{rmorie} and \pkg{morie} use.
}
\examples{
\dontrun{
cat <- load_cihi_data_tables()
f <- fetch_cihi_table("Hospital Beds, 2024")   # live -> archive fallback
}
}
\seealso{
\code{\link{load_cihi_data_tables}}
}
