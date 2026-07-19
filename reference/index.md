# Package index

## Bundled datasets

Discover, load, and inspect the packaged Canadian public-data tables
(OTIS carceral data, CIHI health tables, Chicago crime) that the rmorie
analysis functions consume.

- [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md)
  : Catalogue of bundled datasets
- [`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md)
  : Load a bundled dataset by slug
- [`morie_data_dictionary()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_dictionary.md)
  : Data dictionary (JSON) for a dataset, if one is bundled
- [`morie_data_checksums()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_checksums.md)
  : SHA256 checksums of bundled rmoriedata files
- [`load_chicago_data()`](https://rootcoder007.github.io/rmoriedata/reference/load_chicago_data.md)
  : Load Chicago crime or arrest data
- [`load_cihi_data_tables()`](https://rootcoder007.github.io/rmoriedata/reference/load_cihi_data_tables.md)
  : Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)
- [`fetch_cihi_table()`](https://rootcoder007.github.io/rmoriedata/reference/fetch_cihi_table.md)
  : Download a CIHI data table (live, with Wayback fallback)

## Differential privacy

Calibrated-noise mechanisms (Laplace, Gaussian) for releasing
privacy-preserving counts, histograms, and means at a stated epsilon.

- [`morie_dp_laplace_count()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_count.md)
  : Differentially-private count via the Laplace mechanism
- [`morie_dp_laplace_histogram()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_histogram.md)
  : Differentially-private histogram via the Laplace mechanism
- [`morie_dp_gaussian_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_gaussian_mean.md)
  : Differentially-private mean via the Gaussian mechanism with bounded
  inputs

## Statistical disclosure control

Re-identification safeguards for microdata releases: k-anonymity and
l-diversity checks plus small-cell suppression.

- [`morie_k_anonymity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_k_anonymity_verify.md)
  : k-anonymity verification
- [`morie_l_diversity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_l_diversity_verify.md)
  : l-diversity verification
- [`morie_cell_suppress()`](https://rootcoder007.github.io/rmoriedata/reference/morie_cell_suppress.md)
  : Cell suppression with optional complementary suppression

## Core utilities

Shared primitives used across the package.

- [`morie_core_sha256()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  [`morie_core_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  : Shared C-core helpers (rmorie ecosystem backend)
- [`ask()`](https://rootcoder007.github.io/rmoriedata/reference/ask.md)
  : Ask the rmorie agent about the bundled datasets

## Sample data objects

Small documented data frames bundled for examples and tests (lazy-loaded
via data()).

- [`arrest_sample`](https://rootcoder007.github.io/rmoriedata/reference/arrest_sample.md)
  : Chicago arrests sample
- [`complaint_sample`](https://rootcoder007.github.io/rmoriedata/reference/complaint_sample.md)
  : Chicago reported-crime sample ("complaints")
