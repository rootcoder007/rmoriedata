# cran-comments.md -- rmoriedata 0.3.3

Local staging copy of the text for the comment box on
<https://cran.r-project.org/submit.html>. `.Rbuildignore`d; never in the tarball.

Tarball: rmoriedata_0.3.3.tar.gz (6,713,588 bytes, built 2026-09-21 on l14 from
commit f8ff3fb = origin/main)
sha256:  b6711315154205a69901773daf0496eeb52a3a9b1822cabe5c4ccba23240d114

## Why a release four days after 0.3.2

0.3.2 reached CRAN on 2026-09-17. Two of its changes were wrong in a way
that only shows in a C locale, which is what `R CMD check` uses on some
CRAN machines and what users get in Docker images:

* the CSV readers used `fileEncoding = "UTF-8-BOM"`, which in a C locale
  truncated 22 of the 99 bundled tables, five of them to zero rows;
* the Parquet writer called `enc2utf8()` on unmarked strings, which turned
  every non-ASCII byte into its `<c3><a9>` display form and wrote that into
  the cross-session Chicago cache.

Both are fixed and covered by tests that run the suite in a C locale. We
would rather correct this now than leave a data package that silently drops
rows on some platforms; the next release will not be for at least two
months.

## Test environments

* local (Fedora, R 4.6.1): `R CMD check --as-cran` on this exact tarball
  (2026-09-21) with `_R_CHECK_FORCE_SUGGESTS_=true` and every Suggests
  installed: 0 errors, 0 warnings, 2 NOTEs. Examples, examples with
  `--run-donttest`, tests (55 s) and vignettes all OK.
* GitHub Actions on the same commit: macOS, Windows, Ubuntu
  release/devel/oldrel-1 and a C-locale Ubuntu cell: all passing.

## R CMD check results

0 errors | 0 warnings | 2 NOTEs

* NOTE, `checking CRAN incoming feasibility`: "Days since last update: 4";
  explained above.
* NOTE local to the checking machine, not the package: `compilation flags
  used` (Fedora's hardening flags reach the compile).

## Package size

The installed size is 30.5 MB, almost all of it `inst/extdata` (29.2 MB):
the 99 curated open-data tables ship as CSV and, new in this release, as
Parquet next to each CSV, so that `pandas.read_parquet()` and the R reader
open the same verified file. The source tarball is 6.7 MB, above the 5 MB
guideline; the Parquet copies are what took it over. If that is not
acceptable we will drop the Parquet copies again (0.3.2 shipped without
them at 4.3 MB) and keep them on the package website instead.

## Dependencies

* rmoriebricklayer (>= 0.4.0): on CRAN; checked against 0.5.1. It provides
  the XMSS signature verification of the data store.
* nanoparquet, curl, jsonlite, tibble: Suggests only, every use guarded.

## CRAN policy notes

* No writes at runtime except the opt-in cross-session Chicago cache, which
  goes under `tools::R_user_dir("rmoriedata", "cache")` and is created only
  when the user asks for `full = TRUE`.
* No network access in examples, tests or vignettes; the Chicago and CIHI
  fetchers are exercised only through recorded fixtures.
* Every bundled table names its upstream source, licence and refresh
  script under `data-raw/`.

## Reverse dependencies

rmorie (>= 1.3.0) imports this package; checked with rmorie 1.3.1: no
change in its results.
