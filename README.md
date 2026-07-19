# rmoriedata

[![r-universe](https://rootcoder007.r-universe.dev/badges/rmoriedata)](https://rootcoder007.r-universe.dev/rmoriedata)

Integrated open-data fixtures for [rmorie](https://github.com/rootcoder007/rmorie),
plus a small set of base-R helpers. Its core job remains the `inst/extdata/`
files used by `rmorie`'s examples, vignettes, and tests.

## Install

```r
# r-universe (recommended -- prebuilt binaries, no compiler needed)
install.packages(
  "rmoriedata",
  repos = c("https://rootcoder007.r-universe.dev",
            "https://cloud.r-project.org")
)

# or from GitHub source
# pak::pkg_install("rootcoder007/rmoriedata")
# remotes::install_github("rootcoder007/rmoriedata")
```

## Quick start

```r
library(rmoriedata)

# Browse and load a bundled table by slug.
cat <- morie_data_catalog()
head(cat[cat$kind == "table", c("slug", "n_rows", "n_cols")])
iucr <- morie_data_load("chicago_iucr_codes")

# Release a private count, then check a table for re-identification risk.
morie_dp_laplace_count(true_count = 42, epsilon = 1.0)
df <- data.frame(age = c(25, 25, 25, 40), sex = c("F", "F", "F", "M"))
morie_k_anonymity_verify(df, c("age", "sex"), k = 2)$summary
```

See `vignette("rmoriedata")` for the full tour.

## Functions

A small, deliberate set of base-R helpers (the bulk of the package is still data):

- **Data access** — `morie_data_catalog()`, `morie_data_load()`,
  `morie_data_dictionary()`, `morie_data_checksums()`.
- **Differential privacy + re-identification risk** — `morie_dp_laplace_count()`,
  `morie_dp_gaussian_mean()`, `morie_dp_laplace_histogram()`,
  `morie_cell_suppress()`, `morie_k_anonymity_verify()`, `morie_l_diversity_verify()`.
- **Shared compiled core** — `morie_core_sha256()` and `morie_core_mean()` delegate
  to the family's C core via `LinkingTo: rmoriebricklayer` (one source of truth).

## Chicago sample data — R and Python

Bundled samples (`complaint_sample`, `arrest_sample`) from the City of Chicago
open data; the full datasets are fetched on demand and cached.

```r
library(rmoriedata)
data(complaint_sample)                       # bundled sample, offline
crimes <- load_chicago_data("complaints", full = TRUE)   # full data (Socrata)
pq <- load_chicago_data("arrests", as = "parquet_path")  # Parquet for Python
```

```python
import pandas as pd
df = pd.read_parquet(pq)                      # path printed by load_chicago_data

# Or read the bundled .rda directly (no R install) — use the date_iso column,
# since POSIXct does not roundtrip cleanly through pyreadr:
import pyreadr
complaints = pyreadr.read_r("rmoriedata/data/complaint_sample.rda")["complaint_sample"]
```

**Recommended Python bridge:** the Parquet path (`as = "parquet_path"`) — typed,
columnar, read natively by pandas/polars/duckdb with correct timestamps and no R
runtime. `pyreadr` on the `.rda` works for quick read-only access but is slower
and mangles `POSIXct` (use `date_iso`).

## Why a separate package?

CRAN packages have a 5 MB soft-cap on source tarball size. `rmorie`'s
~6.4 MB of integrated fixtures would push it over that threshold and trigger
a reviewer pushback. Splitting the data out keeps `rmorie` lean
(~few hundred KB of code) and lets data ship at any size via r-universe.

## Citation

If you use rmoriedata in your research, please cite the software:

> Ruhela, V. S. (2026). *rmoriedata: Integrated Datasets for the rmorie Package.* https://github.com/rootcoder007/rmoriedata

BibTeX (or run `citation("rmoriedata")` after installation for the entry
stamped with the exact installed version, sourced from `inst/CITATION`):

```bibtex
@Manual{ruhela_rmoriedata_2026,
  title  = {rmoriedata: Integrated Datasets for the rmorie Package},
  author = {Ruhela, Vansh Singh},
  year   = {2026},
  url    = {https://github.com/rootcoder007/rmoriedata}
}
```

See [`CITATION.cff`](https://github.com/rootcoder007/rmoriedata/blob/main/CITATION.cff) for the
machine-readable metadata GitHub's "Cite this repository" button uses.

## License

AGPL-3.0-or-later. The fixtures themselves are public-domain or
under permissive open-data licenses from their source portals; see
the per-file headers in `inst/extdata/` for attribution.
