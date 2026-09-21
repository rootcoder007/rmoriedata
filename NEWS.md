# rmoriedata 0.3.3

* Nothing is written outside `tempdir()` unless the user asks. The
  Chicago full-dataset cache lives under `tempdir()` by default and moves
  to a persistent directory only through
  `options(rmoriedata.cache_dir = )`; `clear_chicago_cache()` empties it.
  `load_chicago_data(as = "parquet_path")` also writes under `tempdir()`:
  it wrote the bundled sample into the user's `R_user_dir()` cache, and a
  bounded `full = TRUE` fetch could land on the full-dataset cache path.
  `load_siu_reports()` documents
  that it returns the corpus as text (`""` for empty cells) while
  `morie_data_load("siu_directors_reports")` returns the typed frame.
* Every bundled table ships as Parquet again, next to its CSV
  (`inst/extdata/parquet/<slug>.parquet`, plus `_catalog.parquet` and
  `siu_directors_reports_corpus.parquet`). `morie_data_load(format = "parquet")` and
  `load_siu_reports(format = "parquet")` read those copies; the new
  `morie_data_path(slug, format)` returns the verified path of either
  copy, which is the bridge to `pandas.read_parquet()`. The catalog gains
  a `parquet_path` column and the signed manifest covers the new files.
* The Parquet writer no longer mangles non-ASCII text in a C locale
  (`enc2utf8()` on an unmarked string turned each byte into its `<c3><a9>`
  display form, and `load_chicago_data(full = TRUE)` wrote that into the
  cross-session cache). `load_siu_reports()` reads its CSV as UTF-8 like
  the store does, so both copies agree in every locale; a data page v2
  file is reported as such before any decompression; and CI runs the
  check in a C locale. Every CSV reader in the package now declares
  UTF-8, so a live Chicago fetch and its cached copy are `identical()`
  in any locale. A string that is not valid UTF-8 and carries no
  encoding mark is refused by column name (a Parquet string is UTF-8;
  escaping lost the data, passing the bytes through made a file no other
  reader opens), and duplicate column names are refused on write and kept
  apart on read. The cross-session Chicago cache carries a SHA-256
  sidecar checked on every read. `load_cihi_data_tables()` rejects an
  `archived_only` that is not TRUE or FALSE instead of ignoring it.
* `morie_data_checksums()` gains a `path` column relative to the extdata
  root; the bare `file` basenames it returned were not unique and 20 of
  them did not resolve from the root (`morie_data_verify()` already
  returned `path`).
* `ask()` quotes every argument it hands to the `rmorie` CLI. The
  preamble contains a parenthesis, so with the CLI installed every call
  had died in the shell before the binary ran; a `;` in the question
  would have run as a command. `model` and `backend` are validated, and a
  blank or `NA` question is rejected like `""` and `NULL`. A stub binary
  on `PATH` now exercises the branch the tests never reached.
* `morie_data_load()` on a dictionary slug says to use
  `morie_data_dictionary()` instead of pointing back at the catalog.
* `load_chicago_data(full = TRUE)` no longer caches a response that is not
  the dataset. A 200 carrying an outage page, a header-only body or an
  export shorter than the row count the service reports is refused with
  the reason; before, an outage was written to the cross-session cache and
  every later session read the empty frame back. The cache is written to
  a temporary file and renamed, so a concurrent reader never sees a
  half-written file; a cache that cannot be read is discarded and
  refetched; and a new `refresh = TRUE` argument refetches on demand. When
  the service's count endpoint is down the data is returned but not
  cached across sessions.
* `fetch_cihi_table()` checks the downloaded file's size and signature
  against the catalogue's declared format and validates `which` (a whole
  number within the catalogue, or a non-empty title substring) and
  `timeout` before any request. A live URL that answers 200 with an
  outage page now falls through to the Wayback copy.
* The verifier pins the signing key's XMSS root and public seed in package
  code. A store re-signed with another key, even with a consistent
  manifest and shipped public key, no longer verifies; the signature now
  means more than a checksum against local tampering.
* CSV tables are read with `encoding = "UTF-8"` instead of
  `fileEncoding = "UTF-8-BOM"`: in a C locale the latter truncated 22 of
  the 99 tables (5 to zero rows); the bytes are now left alone and
  marked as UTF-8 in every locale.
* The data store is signed. `_checksums.csv` lists every shipped file
  with its SHA-256, and the manifest's own SHA-256 carries an XMSS
  (RFC 8391, SHA-256) signature whose public key ships as
  `_signing_key.json`. The signature is checked once per session and each
  file when first read, so a modified or corrupted install errors instead
  of returning altered data; `morie_data_verify()` checks the whole store
  at once. Needs rmoriebricklayer 0.4.0 or newer for the verification.
* `load_siu_reports(format = "parquet")` pointed at the parquet copy this
  release removed; the option now errors with a note that the gzip CSV is
  the same corpus. rmorie reads the corpus through the default `"csv"`.
* `morie_dp_gaussian_mean()` now rejects infinite `lower` or `upper` with
  the error its message already promised, instead of returning `NaN` with
  a warning from `rnorm()`.

* The data store ships every table once. `morie_data_load()` reads the
  table's CSV (the file rmorie reads by name) and applies a bundled column
  schema, so each table comes back with exactly the names and classes the
  retired parquet copies had (verified identical for all 99 tables), and
  keeps it in a session cache: repeated loads are instant. The parquet
  directory, a duplicate `samples/` directory and a second copy of the SIU
  reports are gone, which takes the source tarball from 6.8 MB to under the
  5 MB CRAN cap. The ten Victoria tables that existed only as parquet now
  ship as CSV under `vic/`. `morie_data_catalog()` has `n_rows` and
  `n_cols` for every table; `morie_data_dictionary()` returns the shipped
  JSON.
* Documentation is generated with markdown roxygen; backticks in the help pages are now `\code{}` (they rendered as stray opening quotes in the PDF manual).

# rmoriedata 0.3.2 - 2026-09-08

## describe_corpus.Rds ships here again

The narrative corpus behind `morie_describe()` was excluded from the
0.3.1 tarball to get this package under 5 MB, which left rmorie
carrying the only shipped copy. rmorie has no room for it either, so
the corpus is back where it belongs, and both packages sit in the
5-10 MB range CRAN accepts with a written justification.

# rmoriedata 0.3.1 - 2026-09-08

## Source tarball down to 4.77 MB, under CRAN's 5 MB guideline

The package shipped 9.2 MB, and most of the excess was duplication:

* `rmoriedata.sqlite` (15 MB uncompressed) was retired by the
  SQLite-to-Parquet migration and no shipped code reads it. Kept in the
  repository, excluded from the tarball.
* The SIU director's-report corpus was bundled three times -- as a
  top-level Parquet file, again inside the Parquet store, and as a
  `.csv.gz`. `load_siu_reports(format = "parquet")` now reads the store
  copy that `morie_data_load()` already serves, so the top-level
  duplicate is gone. The CSV remains: it is the default format and a
  genuinely different encoding, not a third copy of the same one.
* `describe_corpus.Rds` (1.6 MB, and it does not compress) is referenced
  by no R code, Rd page or test. Excluded.

Verified after the change: the Parquet path, the CSV path and the
`siu_directors_reports` store slug all return the same 5,157 x 65 corpus.

# rmoriedata 0.3.0 - 2026-09-08

## Native Parquet codec: one fewer hard dependency

* `nanoparquet` is gone from Imports. The bundled store is now read and
  written by this package's own codec (`R/aaa_parquet.R`), so a plain
  install no longer pulls a compiled Parquet dependency, and
  `load_siu_reports(format = "parquet")` works on a machine that never
  had one -- previously it turned a missing optional package into a hard
  stop, despite the corpus being bundled in exactly that format.

## Victorian crime data

* Ten Victorian (Australia) crime tables added to the bundled Parquet
  store, from the Crime Statistics Agency's "Latest Victorian crime data"
  release (year ending March 2026, CC BY 4.0): criminal incidents,
  recorded offences, victim reports, alleged offender incidents, family
  incidents, the LGA cuts of each, and the two Indigenous-status
  breakdowns. Reach them as `morie_data_load("vic_<key>")`; they appear
  in `morie_data_catalog()` like any other slug.
* The workbooks are .xlsx and were read with rmorie's native reader, so
  the bundled data comes through the same code path a user hits -- no
  readxl/openxlsx dependency and no second parser to disagree with the
  first. Rebuild with `data-raw/build_vic_tables.R`.
* This closes a real gap rather than adding a convenience: rmorie's
  `morie_datasets_vic_table()` defaults to `offline = TRUE`, and with
  nothing bundled it returned a 0-row frame on any machine that had not
  already downloaded the workbook.

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
