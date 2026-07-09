# cran-comments.md — rmoriedata 0.2.3

## Submission

First CRAN submission of rmoriedata: integrated open-data fixtures
(Canadian carceral, police, and oversight datasets, plus municipal
open-data catalogues) for the `rmorie` package, with light
differential-privacy helpers. All integrated data are real slices of
open datasets (OGL-Ontario / OGL-Canada / municipal open licenses),
each with a documented upstream URL, license, and refresh script
under `data-raw/`.

This package Imports `rmoriebricklayer`, submitted to CRAN
immediately before this package (`Additional_repositories:
https://rootcoder007.r-universe.dev` covers the interim). Please
process `rmoriebricklayer` first.

## Test environments

* Local: Debian (aarch64), R 4.5.x — R CMD check --as-cran
* GitHub Actions: ubuntu (release/devel/oldrel-1), windows, macos
* win-builder (R-devel)

## R CMD check results

0 errors | 0 warnings | 1 note

* "New submission".
* The installed size (~10 MB, extdata) reflects the package's purpose:
  it is the data companion of `rmorie` and ships curated open-data
  fixtures in CSV plus a Parquet store read by `nanoparquet`. The
  source tarball is 4.3 MB, within the 5 MB limit.

## CRAN policy notes

* No writes anywhere at runtime: the package only reads its integrated
  files via `system.file()`.
* No network access in code, examples, tests, or vignettes.
