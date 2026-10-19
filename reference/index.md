# Package index

## Bundled datasets

Discover, load, and inspect the packaged Canadian public-data tables
(OTIS carceral data, CIHI health tables, Chicago crime) that the rmorie
analysis functions consume.

- [`mdcat()`](https://rootcoder007.github.io/rmoriedata/reference/mdcat.md)
  : Catalog of the bundled datasets
- [`mdload()`](https://rootcoder007.github.io/rmoriedata/reference/mdload.md)
  : Load a bundled dataset by slug
- [`hostcat()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
  [`hostlogin()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
  [`hostload()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
  : Curated datasets at data.rmorie.com
- [`mdpath()`](https://rootcoder007.github.io/rmoriedata/reference/mdpath.md)
  : Path of a bundled table's shipped file
- [`mddict()`](https://rootcoder007.github.io/rmoriedata/reference/mddict.md)
  : Data dictionary for a bundled dataset
- [`mdsums()`](https://rootcoder007.github.io/rmoriedata/reference/mdsums.md)
  : SHA256 checksums of bundled rmoriedata files
- [`mdverify()`](https://rootcoder007.github.io/rmoriedata/reference/mdverify.md)
  : Verify the bundled data store against its signed manifest
- [`chiload()`](https://rootcoder007.github.io/rmoriedata/reference/chiload.md)
  : Load Chicago crime or arrest data
- [`chiclr()`](https://rootcoder007.github.io/rmoriedata/reference/chiclr.md)
  : Clear the cache of full Chicago datasets
- [`cihitbls()`](https://rootcoder007.github.io/rmoriedata/reference/cihitbls.md)
  : Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)
- [`cihiget()`](https://rootcoder007.github.io/rmoriedata/reference/cihiget.md)
  : Download a CIHI data table (live, with Wayback fallback)
- [`siuload()`](https://rootcoder007.github.io/rmoriedata/reference/siuload.md)
  : Load the Ontario SIU director's-report corpus

## Differential privacy

Calibrated-noise mechanisms (Laplace, Gaussian) for releasing
privacy-preserving counts, histograms, and means at a stated epsilon.

- [`dplapcnt()`](https://rootcoder007.github.io/rmoriedata/reference/dplapcnt.md)
  : Differentially-private count via the discrete Laplace mechanism
- [`dplaphist()`](https://rootcoder007.github.io/rmoriedata/reference/dplaphist.md)
  : Differentially-private histogram via the discrete Laplace mechanism
- [`dpgmean()`](https://rootcoder007.github.io/rmoriedata/reference/dpgmean.md)
  : Differentially-private mean via the analytic Gaussian mechanism
- [`dpbudget()`](https://rootcoder007.github.io/rmoriedata/reference/dpbudget.md)
  : A privacy budget that DP releases are charged against
- [`dpspent()`](https://rootcoder007.github.io/rmoriedata/reference/dpspent.md)
  : What a privacy budget has spent

## Statistical disclosure control

Re-identification safeguards for microdata releases: k-anonymity and
l-diversity checks plus small-cell suppression.

- [`kanonvrf()`](https://rootcoder007.github.io/rmoriedata/reference/kanonvrf.md)
  : k-anonymity verification
- [`ldivvrf()`](https://rootcoder007.github.io/rmoriedata/reference/ldivvrf.md)
  : l-diversity verification
- [`cellsupp()`](https://rootcoder007.github.io/rmoriedata/reference/cellsupp.md)
  : Cell suppression with complementary suppression and a recoverability
  audit

## Core utilities

Shared primitives used across the package.

- [`mdsha()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  [`mdmean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  : Shared C-core helpers (rmorie ecosystem backend)
- [`mdask()`](https://rootcoder007.github.io/rmoriedata/reference/mdask.md)
  : Ask a language model about the bundled datasets
- [`mdllmconf()`](https://rootcoder007.github.io/rmoriedata/reference/mdllmconf.md)
  : Show or save the language-model settings

## Sample data objects

Small documented data frames bundled for examples and tests (lazy-loaded
via data()).

- [`arrest_sample`](https://rootcoder007.github.io/rmoriedata/reference/arrest_sample.md)
  : Chicago arrests sample
- [`complaint_sample`](https://rootcoder007.github.io/rmoriedata/reference/complaint_sample.md)
  : Chicago reported-crime sample ("complaints")

## International datasets

Non-Canadian tables in the bundled store, reached by slug through
mdload().

- [`rmoriedata-victoria`](https://rootcoder007.github.io/rmoriedata/reference/rmoriedata-victoria.md)
  : Victorian crime statistics (Crime Statistics Agency Victoria)
