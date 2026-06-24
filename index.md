# rmoriedata

Bundled open-data fixtures for
[rmorie](https://github.com/rootcoder007/rmorie). This is a
**data-only** companion package — no functions, just `inst/extdata/`
files used by `rmorie`’s examples, vignettes, and tests.

## Install

``` r

# pak (recommended)
pak::pkg_install("rootcoder007/rmoriedata")

# remotes
remotes::install_github("rootcoder007/rmoriedata")
```

## Why a separate package?

CRAN packages have a 5 MB soft-cap on source tarball size. `rmorie`’s
~6.4 MB of bundled fixtures would push it over that threshold and
trigger a reviewer pushback. Splitting the data out keeps `rmorie` lean
(~few hundred KB of code) and lets data ship at any size via r-universe.

## License

AGPL-3.0-or-later. The fixtures themselves are public-domain or under
permissive open-data licenses from their source portals; see the
per-file headers in `inst/extdata/` for attribution.
