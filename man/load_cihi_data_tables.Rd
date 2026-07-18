% Generated manually (roxygenise blocked by a pre-existing unrelated
% load-time error); keep in sync with R/load_cihi.R.
\name{load_cihi_data_tables}
\alias{load_cihi_data_tables}
\title{Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)}
\usage{
load_cihi_data_tables(archived_only = FALSE)
}
\arguments{
\item{archived_only}{If \code{TRUE}, drop rows with no Wayback snapshot.
Default \code{FALSE} (return the full catalogue).}
}
\value{
A \code{data.frame} with columns \code{title}, \code{url},
\code{format}, \code{wayback_url}, \code{retrieved},
\code{source_page_url}, \code{license}.
}
\source{
Canadian Institute for Health Information, Data tables
(\url{https://www.cihi.ca/en/access-data-and-reports/data-tables}).
Snapshotted to the Internet Archive (\url{https://web.archive.org}).
Catalogue built by the C++ data-prep tool
\code{data-raw/cihi_catalog.cpp} in \pkg{rmoriebricklayer}; current as
of 2026-07.
}
\description{
Returns the bundled catalogue of the 232 public data-table workbooks
(\code{.xlsx}/\code{.xls}/\code{.zip}) published on the Canadian
Institute for Health Information (CIHI) \dQuote{Access data and reports
> Data tables} page. Each row carries the table title, its direct
\code{url}, format, and a \code{wayback_url} snapshot on the Internet
Archive so the table stays retrievable even if CIHI rotates or removes
the live file, plus retrieval date, source page, and licence.
}
\details{
Pair with \code{\link{fetch_cihi_table}} (or
\code{rmorie::morie_ingest_cihi_xlsx()}) to download + parse any row;
those helpers try \code{url} first and fall back to \code{wayback_url}
through the shared C++ fetch engine in \pkg{rmoriebricklayer}.
}
\examples{
cat <- load_cihi_data_tables()
nrow(cat)
head(cat$title, 3)
}
