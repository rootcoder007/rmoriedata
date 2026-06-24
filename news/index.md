# Changelog

## rmoriedata (development version)

### rmoriedata 0.1.1

#### New exported helpers — differential privacy + re-identification risk

Six small, base-R-only helpers for analysts releasing aggregate
statistics from the bundled fixtures (or any other dataset) without
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

### rmoriedata 0.1.0

- Initial public release. Bundled fixtures only; no exported functions.
