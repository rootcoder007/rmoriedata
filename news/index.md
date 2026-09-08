# Changelog

## rmoriedata 0.3.2 - 2026-09-08

### describe_corpus.Rds ships here again

The narrative corpus behind `morie_describe()` was excluded from the
0.3.1 tarball to get this package under 5 MB, which left rmorie carrying
the only shipped copy. rmorie has no room for it either, so the corpus
is back where it belongs, and both packages sit in the 5-10 MB range
CRAN accepts with a written justification.

## rmoriedata 0.3.1 - 2026-09-08

### Source tarball down to 4.77 MB, under CRAN’s 5 MB guideline

The package shipped 9.2 MB, and most of the excess was duplication:

- `rmoriedata.sqlite` (15 MB uncompressed) was retired by the
  SQLite-to-Parquet migration and no shipped code reads it. Kept in the
  repository, excluded from the tarball.
- The SIU director’s-report corpus was bundled three times – as a
  top-level Parquet file, again inside the Parquet store, and as a
  `.csv.gz`. `load_siu_reports(format = "parquet")` now reads the store
  copy that
  [`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md)
  already serves, so the top-level duplicate is gone. The CSV remains:
  it is the default format and a genuinely different encoding, not a
  third copy of the same one.
- `describe_corpus.Rds` (1.6 MB, and it does not compress) is referenced
  by no R code, Rd page or test. Excluded.

Verified after the change: the Parquet path, the CSV path and the
`siu_directors_reports` store slug all return the same 5,157 x 65
corpus.

## rmoriedata 0.3.0 - 2026-09-08

### Native Parquet codec: one fewer hard dependency

- `nanoparquet` is gone from Imports. The bundled store is now read and
  written by this package’s own codec (`R/aaa_parquet.R`), so a plain
  install no longer pulls a compiled Parquet dependency, and
  `load_siu_reports(format = "parquet")` works on a machine that never
  had one – previously it turned a missing optional package into a hard
  stop, despite the corpus being bundled in exactly that format.

### Victorian crime data

- Ten Victorian (Australia) crime tables added to the bundled Parquet
  store, from the Crime Statistics Agency’s “Latest Victorian crime
  data” release (year ending March 2026, CC BY 4.0): criminal incidents,
  recorded offences, victim reports, alleged offender incidents, family
  incidents, the LGA cuts of each, and the two Indigenous-status
  breakdowns. Reach them as `morie_data_load("vic_<key>")`; they appear
  in
  [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md)
  like any other slug.
- The workbooks are .xlsx and were read with rmorie’s native reader, so
  the bundled data comes through the same code path a user hits – no
  readxl/openxlsx dependency and no second parser to disagree with the
  first. Rebuild with `data-raw/build_vic_tables.R`.
- This closes a real gap rather than adding a convenience: rmorie’s
  `morie_datasets_vic_table()` defaults to `offline = TRUE`, and with
  nothing bundled it returned a 0-row frame on any machine that had not
  already downloaded the workbook.

## rmoriedata 0.2.5

- `load_chicago_data(full = TRUE)` gains `limit` (exact row cap) and
  `fraction` (share of the live dataset, total looked up first); bounded
  fetches never touch the full-dataset cache. Network examples are now
  `\donttest{}` with [`try()`](https://rdrr.io/r/base/try.html) so they
  degrade gracefully offline.

- SIU corpus also bundled as Parquet;
  `load_siu_reports(format = "parquet")` reads it via nanoparquet
  (columnar / SQL-friendly). CSV remains the default (no extra
  dependency).

## rmoriedata 0.2.4

- SIU corpus: bundle the multi-agent panel-REVIEWED director’s reports
  (subject-official count now 100% for all 2182 English reports;
  witness-officer-only cases resolved to 0). Adds a `panel_reviewed`
  flag column (65 cols).

## rmoriedata 0.2.3

- CRAN size compliance: removed the legacy
  `inst/extdata/rmoriedata.sqlite` (retired by the sqlite-to-parquet
  migration; no shipped code read it — the loader API is Parquet-only
  via `nanoparquet`, and the file remains backed up outside the
  package). Tarball drops from 5.5 MB to 4.25 MB.
- License field is now plain `AGPL (>= 3)` (the LICENSE file was a
  verbatim copy of the standard license, which CRAN flags).
- `CITATION.cff`, `NOTICE`, and `LICENSE` are excluded from the built
  package (`.Rbuildignore`), clearing the top-level-files NOTE.

## rmoriedata 0.2.0

#### Connected to the shared rmorie C core

- rmoriedata now declares `LinkingTo: rmoriebricklayer (>= 0.2.0)` and
  links the ecosystem’s shared compiled core instead of duplicating any
  C code.
- New exports
  [`morie_core_sha256()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  and
  [`morie_core_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  call the shared kernels directly (fast data-integrity hashing +
  summaries for the integrated fixtures, with no dependency on rmorie).
  Tests assert they are byte-identical to `rmoriebricklayer`’s own
  `core_sha256()` / `core_mean()`.

## rmoriedata 0.1.1

#### New exported helpers — differential privacy + re-identification risk

Six small, base-R-only helpers for analysts releasing aggregate
statistics from the integrated fixtures (or any other dataset) without
re-identification risk:

- [`morie_dp_laplace_count()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_count.md)
  — (epsilon, 0)-DP count via the Laplace mechanism (sensitivity 1).
- [`morie_dp_gaussian_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_gaussian_mean.md)
  — approximate (epsilon, delta)-DP mean of a bounded numeric vector via
  the analytic Gaussian mechanism.
- [`morie_dp_laplace_histogram()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_histogram.md)
  — per-bin Laplace noise on a histogram.
- [`morie_k_anonymity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_k_anonymity_verify.md)
  — checks k-anonymity over a set of quasi-identifiers and returns the
  offending equivalence classes.
- [`morie_l_diversity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_l_diversity_verify.md)
  — per-class distinct-count check on a sensitive attribute.
- [`morie_cell_suppress()`](https://rootcoder007.github.io/rmoriedata/reference/morie_cell_suppress.md)
  — small-cell suppression with optional complementary suppression so
  primary-suppressed cells can’t be reconstructed from row/column
  marginals (StatCan-style).

All helpers use only base R + the existing `stats` import; no new
runtime dependencies. Inputs are validated and edge cases (empty
vectors, NAs, out-of-bounds inputs, invalid privacy parameters) throw
informative errors.

#### Tests

- `tests/testthat/test-dp.R` — Monte-Carlo convergence +
  variance-scaling sanity tests for the DP mechanisms; input-validation
  coverage.
- `tests/testthat/test-k-anonymity.R` — hand-built fixtures with known
  equivalence-class structure; complementary-suppression correctness.

## rmoriedata 0.1.0

- Initial public release. Integrated fixtures only; no exported
  functions.
