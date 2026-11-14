# Package index

## Differential privacy

Exact discrete Laplace noise for counts and histograms, the analytic
Gaussian mechanism for means, and a privacy budget the releases are
charged against.

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

## k-anonymity and l-diversity

Checks of a table’s quasi-identifier classes before release.

- [`kanonvrf()`](https://rootcoder007.github.io/rmoriedata/reference/kanonvrf.md)
  : k-anonymity verification
- [`ldivvrf()`](https://rootcoder007.github.io/rmoriedata/reference/ldivvrf.md)
  : l-diversity verification

## Cell suppression

Primary and complementary suppression of small cells, audited for exact
recovery from the margins.

- [`cellsupp()`](https://rootcoder007.github.io/rmoriedata/reference/cellsupp.md)
  : Cell suppression with complementary suppression and a recoverability
  audit

## Bundled datasets and readers

Discover, load, verify and inspect the bundled open-data tables (Ontario
correctional and use-of-force releases, SIU director’s reports, CIHI
data tables, Chicago crime and others).

- [`mdcat()`](https://rootcoder007.github.io/rmoriedata/reference/mdcat.md)
  : Catalog of the bundled datasets
- [`mdload()`](https://rootcoder007.github.io/rmoriedata/reference/mdload.md)
  : Load a bundled dataset by slug
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

## Hosted tables

Curated tables served at data.rmorie.com, checked against the manifest’s
SHA-256.

- [`hostcat()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
  [`hostload()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
  : Curated datasets at data.rmorie.com

## Core utilities and language model

Shared compiled primitives, and questions about the catalogue.

- [`mdsha()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  [`mdmean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  : Shared C-core helpers
- [`mdask()`](https://rootcoder007.github.io/rmoriedata/reference/mdask.md)
  : Ask a language model about the bundled datasets
- [`mdllmconf()`](https://rootcoder007.github.io/rmoriedata/reference/mdllmconf.md)
  : Show or save the language-model settings
