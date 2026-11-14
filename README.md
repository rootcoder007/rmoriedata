# rmoriedata <img src="man/figures/logo.png" align="right" height="139" alt="rmoriedata hex logo" />

<!-- badges: start -->
[![CRAN status](https://www.r-pkg.org/badges/version/rmoriedata)](https://CRAN.R-project.org/package=rmoriedata)
[![CRAN downloads](https://cranlogs.r-pkg.org/badges/grand-total/rmoriedata)](https://cran.r-project.org/package=rmoriedata)
[![R-CMD-check](https://github.com/rootcoder007/rmoriedata/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/rootcoder007/rmoriedata/actions/workflows/R-CMD-check.yaml)
[![r-universe](https://rootcoder007.r-universe.dev/badges/rmoriedata)](https://rootcoder007.r-universe.dev/rmoriedata)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://spdx.org/licenses/AGPL-3.0-or-later.html)
<!-- badges: end -->

Disclosure control for aggregate releases, with open datasets to use it on.

- **Differential privacy**: an exact discrete Laplace sampler for counts
  (`dplapcnt()`, `dplaphist()`), the analytic Gaussian mechanism for means
  (`dpgmean()`), and privacy-budget accounting (`dpbudget()`, `dpspent()`),
  drawing on the operating system's random source.
- **k-anonymity and l-diversity** checks (`kanonvrf()`, `ldivvrf()`).
- **Cell suppression** audited for exact recovery from the margins
  (`cellsupp()`).
- **Open datasets**, bundled and checksummed, with the functions that read
  and verify them (`mdcat()`, `mdload()`, `mdverify()`), and the curated
  tables at data.rmorie.com (`hostcat()`, `hostload()`).

## Install

Install the current release from r-universe (prebuilt binaries for macOS and
Windows), which can be newer than CRAN. rmoriebricklayer, its companion, is
named too, so an older copy already installed is replaced: rmoriedata needs
rmoriebricklayer 1.1.1 or later.

With [pak](https://pak.r-lib.org) (progress bars, parallel downloads, compiler
output hidden unless a build fails, and the named packages always upgraded to
the current release). Keep the `repos` arguments as written: under `Rscript`
there is no mirror chooser, so a bare `install.packages()` stops with "trying to
use CRAN without setting a mirror", and CRAN can carry older versions than
r-universe.

```r
if (!requireNamespace("pak", quietly = TRUE)) {
  install.packages("pak", repos = "https://cloud.r-project.org")
}
pak::repo_add(rootcoder007 = "https://rootcoder007.r-universe.dev")
pak::pkg_install(c("rmoriebricklayer", "rmoriedata"))
```

From a terminal (single quotes outside, double quotes inside, so the shell
passes the R code through untouched):

```sh
Rscript -e 'if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak", repos = "https://cloud.r-project.org"); pak::repo_add(rootcoder007 = "https://rootcoder007.r-universe.dev"); pak::pkg_install(c("rmoriebricklayer", "rmoriedata"))'
```

Without pak, plain `install.packages()` does the same with R's own output:

```sh
Rscript -e 'install.packages(c("rmoriebricklayer", "rmoriedata"), repos = c("https://rootcoder007.r-universe.dev", "https://cloud.r-project.org"))'
```

Development version from GitHub (a source build; needs a C/C++ toolchain):

```sh
Rscript -e 'if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak", repos = "https://cloud.r-project.org"); pak::repo_add(rootcoder007 = "https://rootcoder007.r-universe.dev"); pak::pkg_install("rootcoder007/rmoriedata")'
# without pak
Rscript -e 'repos <- c("https://rootcoder007.r-universe.dev", "https://cloud.r-project.org"); install.packages("remotes", repos = repos); remotes::install_github("rootcoder007/rmoriedata", repos = repos, upgrade = "always")'
```

On macOS, CRAN's R (from <https://CRAN.R-project.org/bin/macosx/>) installs
r-universe's prebuilt binaries in seconds. Homebrew's R cannot use them, so
there every package is compiled from source.

## Quick start

```r
library(rmoriedata)

# Release a private count, then check a table for re-identification risk.
dplapcnt(truecnt = 42, epsilon = 1.0)
df <- data.frame(age = c(25, 25, 25, 40), sex = c("F", "F", "F", "M"))
kanonvrf(df, c("age", "sex"), k = 2)$summary
cellsupp(matrix(c(120, 3, 47, 88), 2), threshold = 5)$protected

# Browse and load a bundled table by slug.
cat <- mdcat()
head(cat[cat$kind == "table", c("slug", "n_rows", "n_cols")])
iucr <- mdload("chicago_iucr_codes")
```

See `vignette("rmoriedata")` for the full tour.

## Functions

- **Differential privacy** — `dplapcnt()`, `dplaphist()`, `dpgmean()`;
  `dpbudget()` holds an epsilon (and delta) the releases draw down, and
  `dpspent()` reports what has been spent.
- **k-anonymity and l-diversity** — `kanonvrf()`, `ldivvrf()`.
- **Cell suppression** — `cellsupp()`, with complementary suppression and an
  exact recoverability audit.
- **Bundled datasets and readers** — `mdcat()`, `mdload()`, `mdpath()`,
  `mddict()`, `mdsums()`; `mdverify()` checks every bundled file against the
  signed manifest.
- **Ontario SIU director's reports** — `siuload()` returns the reviewed
  corpus (one row per report, French and English, with corrigenda applied).
- **CIHI data tables** — `cihitbls()` lists the open workbooks and
  `cihiget()` downloads one (live, with a Wayback fallback).
- **Chicago** — `chiload()` (below) and `chiclr()` for the
  cached full datasets.
- **Hosted tables** — `hostcat()` and `hostload()` (below).
- **Shared compiled core** — `mdsha()` and `mdmean()` delegate
  to the C core of rmoriebricklayer via `LinkingTo` (one source of truth).
- **Language model** — `mdask()` and `mdllmconf()` (below).

## Chicago sample data — R and Python

Bundled samples (`complaint_sample`, `arrest_sample`) from the City of Chicago
open data; the full datasets are fetched on demand and cached.

```r
library(rmoriedata)
data(complaint_sample)                       # bundled sample, offline
crimes <- chiload("complaints", full = TRUE, limit = 200)  # the full data, first 200 rows
# omit `limit` for the whole multi-million-row dataset (large: minutes and gigabytes)
pq <- chiload("arrests", as = "parquet_path")  # Parquet for Python
```

```python
import pandas as pd
df = pd.read_parquet(pq)                      # path printed by chiload

# Or read the sample's .rda from the package source (data/complaint_sample.rda
# in the source tarball or the GitHub repository; an installed package keeps it
# in a lazy-load database instead) — use the date_iso column, since POSIXct
# does not roundtrip cleanly through pyreadr:
import pyreadr
complaints = pyreadr.read_r("data/complaint_sample.rda")["complaint_sample"]
```

Every bundled table also ships as Parquet: `mdpath("<slug>")` gives
the verified path, `pd.read_parquet()` reads it.

**Recommended Python bridge:** the Parquet path (`as = "parquet_path"`) — typed,
columnar, read natively by pandas/polars/duckdb with correct timestamps and no R
runtime. `pyreadr` on the source `.rda` works for quick read-only access but is slower
and mangles `POSIXct` (use `date_iso`).

## Curated tables at data.rmorie.com

The tables the MORIE project materialises from BigQuery public datasets, Statistics
Canada and the survey, court and justice data its ledger uses are served from the edge
with no sign-in: `hostcat()` lists them and `hostload("db/table")` opens one, checked
against the SHA-256 its manifest lists; a large table comes down in parts that resume.
Each table keeps its source's licence; the terms are at `www.rmorie.com/data-license/`.
ICPSR studies are not served there (ICPSR's terms do not allow redistribution): `hostcat()`
leaves them out and `hostload()` refuses them before any request. The endpoint
comes from a signed services document the packages verify before use, so it can change without
a release.

```r
cat_ <- hostcat()            # key, name, rows, source dataset
df <- hostload("fec_cm_2020/fec_cm_2020")
```

## Asking a language model

`mdask()` puts a question about the datasets to a language model you bring: a
provider's key (OpenAI, Anthropic, Google Gemini, OpenRouter, Groq, Mistral and
more, each from its usual variable), an Ollama server, or an OpenAI-compatible
server of your own. The model gets the catalogue and every function of
rmoriedata and rmoriebricklayer, with tools to read their help.

```r
Sys.setenv(ANTHROPIC_API_KEY = "...")          # or mdllmconf(anthropic.key = "...")
mdask("which tables cover police stops?")
mdask("which tables cover police stops?", route = "ollama", model = "qwen3:8b")
```

## Citation

If you use rmoriedata in your research, please cite the software:

> Ruhela, V. S. (2026). *rmoriedata: Disclosure Control for Aggregate Releases, with Open Datasets.* R package version 0.4.3. doi:10.32614/CRAN.package.rmoriedata. https://rootcoder007.r-universe.dev/rmoriedata

BibTeX (or run `citation("rmoriedata")` after installation for the entry
stamped with the exact installed version, sourced from `inst/CITATION`):

```bibtex
@Manual{ruhela_rmoriedata_2026,
  title  = {rmoriedata: Disclosure Control for Aggregate Releases, with Open Datasets},
  author = {Ruhela, Vansh Singh},
  year   = {2026},
  doi    = {10.32614/CRAN.package.rmoriedata},
  url    = {https://rootcoder007.r-universe.dev/rmoriedata}
}
```

See [`CITATION.cff`](https://github.com/rootcoder007/rmoriedata/blob/main/CITATION.cff) for the
machine-readable metadata GitHub's "Cite this repository" button uses.

## License

AGPL-3.0-or-later for the code. The bundled data are snapshots of public
data, each under the licence or terms of use of the body that published it;
the publisher and source of every table are named in its help page
(`?complaint_sample`, `?arrest_sample`, `?siuload`, `?cihitbls`,
`` ?`rmoriedata-victoria` ``), in the catalogue (`mdcat()`, from
`inst/extdata/_catalog.csv`), and in the data-attribution section of
`inst/NOTICE`.
