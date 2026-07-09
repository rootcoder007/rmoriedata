# rmoriedata

[![r-universe](https://rootcoder007.r-universe.dev/badges/rmoriedata)](https://rootcoder007.r-universe.dev/rmoriedata)

Integrated open-data fixtures for [rmorie](https://github.com/rootcoder007/rmorie),
plus a small set of base-R helpers. Its core job remains the `inst/extdata/`
files used by `rmorie`'s examples, vignettes, and tests.

## Install

```r
# pak (recommended)
pak::pkg_install("rootcoder007/rmoriedata")

# remotes
remotes::install_github("rootcoder007/rmoriedata")
```

## Functions

A small, deliberate set of base-R helpers (the bulk of the package is still data):

- **Data access** — `morie_data_catalog()`, `morie_data_load()`,
  `morie_data_dictionary()`, `morie_data_checksums()`.
- **Differential privacy + re-identification risk** — `morie_dp_laplace_count()`,
  `morie_dp_gaussian_mean()`, `morie_dp_laplace_histogram()`,
  `morie_cell_suppress()`, `morie_k_anonymity_verify()`, `morie_l_diversity_verify()`.
- **Shared compiled core** — `morie_core_sha256()` and `morie_core_mean()` delegate
  to the family's C core via `LinkingTo: rmoriebricklayer` (one source of truth).

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
