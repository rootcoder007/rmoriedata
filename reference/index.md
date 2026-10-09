# Package index

## Bundled datasets

Discover, load, and inspect the packaged Canadian public-data tables
(OTIS carceral data, CIHI health tables, Chicago crime) that the rmorie
analysis functions consume.

- [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md)
  : Catalog of the bundled datasets
- [`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md)
  : Load a bundled dataset by slug
- [`morie_data_hosted_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_hosted_catalog.md)
  [`morie_data_hosted_login()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_hosted_catalog.md)
  [`morie_data_hosted_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_hosted_catalog.md)
  : Curated datasets at data.rmorie.com
- [`morie_data_path()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_path.md)
  : Path of a bundled table's shipped file
- [`morie_data_dictionary()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_dictionary.md)
  : Data dictionary for a bundled dataset
- [`morie_data_checksums()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_checksums.md)
  : SHA256 checksums of bundled rmoriedata files
- [`morie_data_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_verify.md)
  : Verify the bundled data store against its signed manifest
- [`load_chicago_data()`](https://rootcoder007.github.io/rmoriedata/reference/load_chicago_data.md)
  : Load Chicago crime or arrest data
- [`clear_chicago_cache()`](https://rootcoder007.github.io/rmoriedata/reference/clear_chicago_cache.md)
  : Clear the cache of full Chicago datasets
- [`load_cihi_data_tables()`](https://rootcoder007.github.io/rmoriedata/reference/load_cihi_data_tables.md)
  : Catalogue of CIHI open data-table workbooks (with Wayback fallbacks)
- [`fetch_cihi_table()`](https://rootcoder007.github.io/rmoriedata/reference/fetch_cihi_table.md)
  : Download a CIHI data table (live, with Wayback fallback)
- [`load_siu_reports()`](https://rootcoder007.github.io/rmoriedata/reference/load_siu_reports.md)
  : Load the Ontario SIU director's-report corpus

## Differential privacy

Calibrated-noise mechanisms (Laplace, Gaussian) for releasing
privacy-preserving counts, histograms, and means at a stated epsilon.

- [`morie_dp_laplace_count()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_count.md)
  : Differentially-private count via the discrete Laplace mechanism
- [`morie_dp_laplace_histogram()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_histogram.md)
  : Differentially-private histogram via the discrete Laplace mechanism
- [`morie_dp_gaussian_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_gaussian_mean.md)
  : Differentially-private mean via the analytic Gaussian mechanism
- [`morie_dp_budget()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_budget.md)
  : A privacy budget that DP releases are charged against
- [`morie_dp_spent()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_spent.md)
  : What a privacy budget has spent

## Statistical disclosure control

Re-identification safeguards for microdata releases: k-anonymity and
l-diversity checks plus small-cell suppression.

- [`morie_k_anonymity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_k_anonymity_verify.md)
  : k-anonymity verification
- [`morie_l_diversity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_l_diversity_verify.md)
  : l-diversity verification
- [`morie_cell_suppress()`](https://rootcoder007.github.io/rmoriedata/reference/morie_cell_suppress.md)
  : Cell suppression with complementary suppression and a recoverability
  audit

## Core utilities

Shared primitives used across the package.

- [`morie_core_sha256()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  [`morie_core_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  : Shared C-core helpers (rmorie ecosystem backend)
- [`ask()`](https://rootcoder007.github.io/rmoriedata/reference/ask.md)
  : Ask a language model about the bundled datasets
- [`morie_data_llm_config()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_llm_config.md)
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
morie_data_load().

- [`rmoriedata-victoria`](https://rootcoder007.github.io/rmoriedata/reference/rmoriedata-victoria.md)
  : Victorian crime statistics (Crime Statistics Agency Victoria)
