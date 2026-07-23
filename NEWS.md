# rmoriedata 0.2.5

* `load_chicago_data(full = TRUE)` gains `limit` (exact row cap) and
  `fraction` (share of the live dataset, total looked up first); bounded
  fetches never touch the full-dataset cache. Network examples are now
  `\donttest{}` with `try()` so they degrade gracefully offline.

* SIU corpus also bundled as Parquet; `load_siu_reports(format = "parquet")` reads it via nanoparquet (columnar / SQL-friendly). CSV remains the default (no extra dependency).

# rmoriedata 0.2.4

* SIU corpus: bundle the multi-agent panel-REVIEWED director's reports (subject-official count now 100% for all 2182 English reports; witness-officer-only cases resolved to 0). Adds a `panel_reviewed` flag column (65 cols).

# rmoriedata 0.2.3

* CRAN size compliance: removed the legacy `inst/extdata/rmoriedata.sqlite`
  (retired by the sqlite-to-parquet migration; no shipped code read it —
  the loader API is Parquet-only via `nanoparquet`, and the file remains
  backed up outside the package). Tarball drops from 5.5 MB to 4.25 MB.
* License field is now plain `AGPL (>= 3)` (the LICENSE file was a
  verbatim copy of the standard license, which CRAN flags).
* `CITATION.cff`, `NOTICE`, and `LICENSE` are excluded from the built
  package (`.Rbuildignore`), clearing the top-level-files NOTE.

# rmoriedata 0.2.0

### Connected to the shared rmorie C core

* rmoriedata now declares `LinkingTo: rmoriebricklayer (>= 0.2.0)` and links
  the ecosystem's shared compiled core instead of duplicating any C code.
* New exports `morie_core_sha256()` and `morie_core_mean()` call the shared
  kernels directly (fast data-integrity hashing + summaries for the integrated
  fixtures, with no dependency on rmorie). Tests assert they are
  byte-identical to `rmoriebricklayer`'s own `core_sha256()` / `core_mean()`.

# rmoriedata 0.1.1

### New exported helpers — differential privacy + re-identification risk

Six small, base-R-only helpers for analysts releasing aggregate statistics
from the integrated fixtures (or any other dataset) without re-identification
risk:

* `morie_dp_laplace_count()` — (epsilon, 0)-DP count via the Laplace
  mechanism (sensitivity 1).
* `morie_dp_gaussian_mean()` — approximate (epsilon, delta)-DP mean of a
  bounded numeric vector via the analytic Gaussian mechanism.
* `morie_dp_laplace_histogram()` — per-bin Laplace noise on a histogram.
* `morie_k_anonymity_verify()` — checks k-anonymity over a set of
  quasi-identifiers and returns the offending equivalence classes.
* `morie_l_diversity_verify()` — per-class distinct-count check on a
  sensitive attribute.
* `morie_cell_suppress()` — small-cell suppression with optional
  complementary suppression so primary-suppressed cells can't be
  reconstructed from row/column marginals (StatCan-style).

All helpers use only base R + the existing `stats` import; no new
runtime dependencies. Inputs are validated and edge cases (empty
vectors, NAs, out-of-bounds inputs, invalid privacy parameters) throw
informative errors.

### Tests

* `tests/testthat/test-dp.R` — Monte-Carlo convergence + variance-scaling
  sanity tests for the DP mechanisms; input-validation coverage.
* `tests/testthat/test-k-anonymity.R` — hand-built fixtures with known
  equivalence-class structure; complementary-suppression correctness.

# rmoriedata 0.1.0

* Initial public release. Integrated fixtures only; no exported functions.
