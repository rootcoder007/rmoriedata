# rmoriedata 0.3.5

* **Privacy verifiers (review of 0.3.5).** `morie_k_anonymity_verify()` treats a missing
  quasi-identifier as a level of its own: `stats::aggregate()` had dropped every row with an `NA`
  key, so a class of one person could pass `k = 3`; class sizes now always sum to `nrow(data)`.
  `morie_l_diversity_verify()` counts only known sensitive values (`"HIV", NA, NA` is diversity 1,
  not 2). `morie_cell_suppress()` adds complementary suppressions to a fixed point and then audits
  the result exactly: a hidden cell the row and column totals determine (its indicator in the row
  space of the margin constraints) gets another complement, and the result carries
  `recoverable_mask`, `n_recoverable` and a `protected` verdict to test before publishing. The
  0.3.5 passes left a lone hidden cell in a row or column, from which the primary value followed
  by two subtractions; zero cells are no longer used as complements. Checked against brute-force
  enumeration of every margin-consistent fill on 464 random tables: no disagreement.
* **Differential privacy.** Noise comes from the operating system's CSPRNG
  (`rmoriebricklayer::random_bytes()`), not R's seeded generator, so `set.seed()` no longer
  reproduces a release. Counts and histograms use the exact discrete Laplace sampler of Canonne,
  Kamath and Steinke (2020) in integer arithmetic (whole-number releases; no floating-point
  artefact of the kind Mironov (2012) showed in the textbook Laplace sampler). The mean uses the
  analytic Gaussian mechanism of Balle and Wang (2018), valid for every epsilon; the classical
  bound, valid only for epsilon <= 1, is gone. All three mechanisms use one neighbouring relation
  (add or remove one record): the mean is a noised sum over a noised count. New
  `morie_dp_budget()` / `morie_dp_spent()` charge releases against a budget (basic composition)
  and refuse one that would exceed it. Examples no longer call `set.seed()`.
* **Parquet reader.** Every byte access is bounds-checked (an out-of-range raw index had silently
  read zeros); varints, lists, maps and nesting are capped by the bytes that remain, so the 21-byte
  file that looped forever is refused at once; the decoded row count must equal the row group's
  and the footer's exactly (no padding with `NA`, no truncation); a column chunk's type must match
  the schema's; PLAIN values must fill their page exactly; dictionary indices are range-checked;
  page sizes and footer row counts are capped (`options(rmoriedata.parquet_max_page_bytes,
  rmoriedata.parquet_max_rows)`); `PageHeader.crc` is verified when present and the writer now
  writes it. `tests/testthat/test-parquet-hostile.R` fuzzes all three codecs.
* **Downloads.** `.rmd_dl()`, which carries the MORIE key as a bearer header, goes through
  `rmoriebricklayer::bricklayer_download()` (https to public hosts only, no `file://`, size cap)
  instead of base `url()`; requires rmoriebricklayer 0.5.9. `load_cihi_data_tables()` checks the
  catalogue against the signed manifest before reading it. `morie_data_verify()` reports files
  added to the store (`listed = FALSE`), and `morie_data_checksums()` compares each digest with the
  manifest (`in_manifest`).
* **Workflows.** The SIU manifest refresh runs only on demand and uploads an artifact instead of
  committing: the manifest is covered by the XMSS-signed `_checksums.csv`, whose key never leaves
  the maintainer's machine, so it is re-signed locally with `data-raw/sign_store.R`. A new
  ASAN/UBSAN job builds the C and runs the suite, including `test-codec-hostile.R`.
* **Packaging.** `utils` is declared in `Imports`; the stale `RoxygenNote` is dropped
  (`Config/roxygen2/version` is the roxygen 8 field); `NOTICE` moves to `inst/NOTICE` so it
  installs, and its data attribution now names the publishers instead of per-file headers that did
  not exist. The licence text itself stays out of the tarball, as CRAN asks for a standard licence.
  DESCRIPTION describes the disclosure-control helpers by what they do.

* The curated-data service address comes from the signed services document at
  rmorie.com (through `rmoriebricklayer::bricklayer_services()` when the installed
  bricklayer has it; an older bricklayer keeps the default address), so the endpoint can
  move or be paused without a release. Keys are personal and issued on request at
  <https://rmorie.com/access>; every hint says so, and `morie_data_hosted_login(token = )`
  stores one (the GitHub and emailed-code sign-ins keep working).
* `ask()` follows `rmoriebricklayer::bricklayer_llm_ask()`'s route order: an endpoint of
  your own, a local Ollama server, then the hosted MORIE tier as a last resort;
  `backend = "hosted"` insists on the hosted tier. The setup hint when nothing answers
  names all three.

# rmoriedata 0.3.4

* The Parquet store is compressed: the writer's Snappy stream was literal-only (valid, but it
  compressed nothing), so every table's Parquet copy was as large as its raw pages. Pages are now
  written with GZIP (zlib, level 9) by default, and Snappy, still available, has a real
  match-finder; both codecs and the reader are C (`src/gzip.c`, `src/snappy.c`). The Parquet copies
  shrink from 16.1 MB to 3.3 MB (the SIU corpus from 10.0 MB to 2.1 MB) and the installed package
  from about 27 MB to 14.5 MB; pandas/pyarrow read them as before.
* SIU corpus: `narrative_summary` holds each report's own account of the incident on 4,605 of 4,613
  reports (it was empty but for three values that described the SIU's investigation). The text is
  the opening of the report's "Incident Narrative" / "Description de l'incident" section, or of the
  "Notification of the SIU" / "Avis à l'UES" section in reports that have no narrative section (2005-2016
  and re-opened files), about 900 characters cut at a sentence end. It was read from the SIU's pages,
  re-crawled on 2026-10-05 at one request every 3 seconds; `data-raw/add_siu_narratives.R` rebuilds it.
* SIU corpus, round 8 (4,613 rows; every change is a row of `data-raw/siu_round8_review.csv`, with
  the reason read from the page, or a rule of `data-raw/siu_round8_rules.R`):
  - six French reports of 2005-2011 filed under /en/ are labelled French and carry the service their
    page names; three of them held "Guelph Police Service", which the pages never name (05-TCD-004
    is Toronto, 10-PFD-078 the OPP, 10-OOD-009 Ottawa);
  - a corrigendum is applied to the report it corrects, in a new column `corrigenda`, not counted as
    a report (drids 385, 620/621 and 5065 correct 328, 521/522 and 4561); six second copies of one
    report (identical page text) are removed;
  - case numbers the page body gives: drids 925/926 are 19-TCI-073a, and drid 2209 is the French
    report of 22-PCI-191 (the OPP in Quinte West), not of 21-OCI-191 as the SIU page's header says;
  - a French report carries its English report's reviewed case facts (dates, team, counts, the
    affected person's age and sex, the charges, the director's view): they were empty on about
    2,240 of 2,304 French rows; the French text fields stay French;
  - `charges_recommended` is `"FALSE"`, `"TRUE"` or empty (it had 39 spellings), and logical in the
    typed table (`morie_data_load("siu_directors_reports")`, CSV and Parquet), as `panel_reviewed` is;
    `sex_gender_affected` is `male` or `female`; one name for Kawartha Lakes and for Cornwall (the
    Cornwall Community Police Service is now the Cornwall Police Service);
  - `narrative_summary` held the SIU's mandate paragraph or the page title, not a narrative, and is
    empty except on the three rows that held report text; `supplemental_materials` lists the
    legislation and case law a report cites (it held the page's share and privacy links).
* `ask()` sends the bundled catalogue (slug, kind, rows) with the question, so the model names tables
  (it was told only to "prefer the bundled catalog", which it could not see). Through the rmorie binary it
  calls `rmorie agent [--model NAME] QUESTION`, the agent's own options: it passed `--backend`, which
  the agent refuses, and `-m` for the model; `backend` is `"auto"`, `"hosted"` or `"cli"`. The examples that need a stored key or the binary are `\dontrun`; the one that runs
  switches the hosted tier off (`MORIE_HOSTED_BASE_URL = "off"`), so it reaches no network
  whatever key the machine holds.
* `morie_dp_laplace_count()` and `morie_dp_laplace_histogram()` refuse `Inf` in words (they warned
  about integer coercion, then failed in R's internals) and refuse counts above 2^53: a double that
  large has no room for Laplace noise of scale 1/epsilon, so `morie_dp_laplace_count(1e300, 1)`
  returned exactly 1e300, a "private" release equal to the true count. A whole count beyond R's
  integer range but below 2^53 is still a count. `morie_core_mean()` refuses text instead of
  averaging `NA`.
* Help: `?rmoriedata` describes the package's functions (it said there were none); `?load_siu_reports`
  lost "% of them" to an Rd escape; "more than 160" databases at data.rmorie.com; a garbled sentence
  in `?load_chicago_data`; the README's Chicago example is bounded (`limit = 200`).
* The SIU director's-report corpus: `police_service` is the service of the subject officials
  on every row (it was the notifying force on many French rows, and on 24 English rows a
  custody, requesting or neighbouring service -- each corrected after reading the report);
  one spelling per service; 59 English reports published since the last build, reviewed by
  the same model panel, and their 60 French reports added; 54 French reports filed under
  /en/ relabelled; 29 rows that held no director's report removed.

* `ask()` answers through the hosted MORIE tier with the key
  `morie_data_hosted_login()` stores (ollama.com cloud models and additional AI
  models such as `kimi-k2.6:cf` or `gpt-oss-120b:cf`), and only falls back to the
  optional `rmorie` command-line agent when no key is stored.

* Hosted tables download with a live progress bar (percent, size, rate) in
  an interactive session; `options(morie.quiet = TRUE)` silences it.

* Requires rmoriebricklayer 0.5.2 or newer (the login flow).
* `morie_data_hosted_login()` signs in to the hosted MORIE tier (GitHub device
  flow, email code, or a key you hold) and stores the key in the credentials
  file every MORIE package reads, so rmoriedata alone is enough to use
  data.rmorie.com.
* `morie_data_hosted_catalog()` and `morie_data_hosted_load("db/table")`: the
  160 databases the MORIE project materialises from BigQuery public datasets,
  served from the edge at data.rmorie.com and opened by the MORIE key that
  rmorie, morie or rmoriebricklayer store. Cached under the package cache
  directory (`tempdir()` unless `options(rmoriedata.cache_dir = )`).

# rmoriedata 0.3.3

* Nothing is written outside `tempdir()` unless the user asks. The
  Chicago full-dataset cache lives under `tempdir()` by default and moves
  to a persistent directory only through
  `options(rmoriedata.cache_dir = )`; `clear_chicago_cache()` empties it.
  `load_chicago_data(as = "parquet_path")` also writes under `tempdir()`:
  it wrote the bundled sample into the user's `R_user_dir()` cache, and a
  bounded `full = TRUE` fetch could land on the full-dataset cache path.
  The schema names the language column of `siu_directors_reports` and
  `siu_drid_manifest` `_language`, as the files do; it carried the
  `X_language` that `check.names` had made of it, so the typed store and
  `load_siu_reports()` disagreed on the name. `load_siu_reports()` documents
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
