# rmoriedata

[![r-universe](https://rootcoder007.r-universe.dev/badges/rmoriedata)](https://rootcoder007.r-universe.dev/rmoriedata)

Integrated open-data fixtures for
[rmorie](https://github.com/rootcoder007/rmorie), plus a small set of
base-R helpers. Its core job remains the `inst/extdata/` files used by
`rmorie`’s examples, vignettes, and tests.

## Install

``` r

# pak (recommended)
pak::pkg_install("rootcoder007/rmoriedata")

# remotes
remotes::install_github("rootcoder007/rmoriedata")
```

## Functions

A small, deliberate set of base-R helpers (the bulk of the package is
still data):

- **Data access** —
  [`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md),
  [`morie_data_load()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_load.md),
  [`morie_data_dictionary()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_dictionary.md),
  [`morie_data_checksums()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_checksums.md).
- **Differential privacy + re-identification risk** —
  [`morie_dp_laplace_count()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_count.md),
  [`morie_dp_gaussian_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_gaussian_mean.md),
  [`morie_dp_laplace_histogram()`](https://rootcoder007.github.io/rmoriedata/reference/morie_dp_laplace_histogram.md),
  [`morie_cell_suppress()`](https://rootcoder007.github.io/rmoriedata/reference/morie_cell_suppress.md),
  [`morie_k_anonymity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_k_anonymity_verify.md),
  [`morie_l_diversity_verify()`](https://rootcoder007.github.io/rmoriedata/reference/morie_l_diversity_verify.md).
- **Shared compiled core** —
  [`morie_core_sha256()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  and
  [`morie_core_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  delegate to the family’s C core via `LinkingTo: rmoriebricklayer` (one
  source of truth).

## Why a separate package?

CRAN packages have a 5 MB soft-cap on source tarball size. `rmorie`’s
~6.4 MB of integrated fixtures would push it over that threshold and
trigger a reviewer pushback. Splitting the data out keeps `rmorie` lean
(~few hundred KB of code) and lets data ship at any size via r-universe.

## Citation

If you use rmoriedata in your research, please cite the software:

> Ruhela, V. S. (2026). *rmoriedata: Integrated Datasets for the rmorie
> Package.* <https://github.com/rootcoder007/rmoriedata>

BibTeX (or run `citation("rmoriedata")` after installation for the entry
stamped with the exact installed version, sourced from `inst/CITATION`):

``` bibtex
@Manual{ruhela_rmoriedata_2026,
  title  = {rmoriedata: Integrated Datasets for the rmorie Package},
  author = {Ruhela, Vansh Singh},
  year   = {2026},
  url    = {https://github.com/rootcoder007/rmoriedata}
}
```

See
[`CITATION.cff`](https://github.com/rootcoder007/rmoriedata/blob/main/CITATION.cff)
for the machine-readable metadata GitHub’s “Cite this repository” button
uses.

## License

AGPL-3.0-or-later. The fixtures themselves are public-domain or under
permissive open-data licenses from their source portals; see the
per-file headers in `inst/extdata/` for attribution.
