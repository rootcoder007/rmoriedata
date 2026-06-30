# AGENTS.md

Behavioural guidance for AI coding agents working in this repository.
`CLAUDE.md` and `GEMINI.md` are thin pointers (`@AGENTS.md`).

**rmoriedata** is the data + light-helper companion R package for
[rmorie](https://github.com/rootcoder007/rmorie). Its core job is
bundled open-data fixtures, but it has grown a small, deliberate set of
analyst-facing helpers:

- **Differential privacy + re-identification risk** — `morie_dp_*`,
  `morie_k_anonymity_verify`, `morie_l_diversity_verify`,
  `morie_cell_suppress` (base-R only).
- **Shared C backend** —
  [`morie_core_sha256()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  /
  [`morie_core_mean()`](https://rootcoder007.github.io/rmoriedata/reference/morie_core.md)
  delegate to the ecosystem’s compiled core via
  `LinkingTo: rmoriebricklayer` (one shared copy of morie’s arithmetic;
  see
  [rmoriebricklayer](https://github.com/rootcoder007/rmorie-bricklayer)).
  `src/` exists for this and must stay a thin link to the core — do NOT
  reimplement numeric kernels here.

Keep additions small and fixture-adjacent; heavy analysis belongs in
rmorie, not here.

## License — AGPL-3.0-or-later

Strong copyleft, matching morie + rmorie. See those repos’ AGENTS.md for
the full rationale. Short version:

- Every R source file (there’s only `R/zzz.R`) carries
  `# SPDX-License-Identifier: AGPL-3.0-or-later`. Preserve it.
- Bundled data files are released under the SAME license terms. Do NOT
  relabel `inst/extdata/*` as CC0, CC-BY, or anything else unless the
  upstream source explicitly grants it.

## Interaction rules

### Ask with multiple-choice options

When clarifying intent, scope, or approach, use `AskUserQuestion` with a
comprehensive option set and an “other” escape.

### Ask before pushing — every push, every remote

Particularly important: this package is referenced as a `Remotes:`
target from rmorie’s DESCRIPTION. A bad push here breaks rmorie’s CI.

### Don’t guess; verify

Especially for bundled data provenance. Every dataset must have a
documented upstream URL, license, and refresh script.

## What NOT to do

- **No fabricated data.** Every file in `inst/extdata/` must be a REAL
  slice from a public API or a typed-empty 0-row data frame with a
  documented schema. Never
  [`rnorm()`](https://rdrr.io/r/stats/Normal.html) /
  [`sample()`](https://rdrr.io/r/base/sample.html) fake values. This
  rule has been violated before; do not violate it again.
- **No private datasets.** Anything that requires FOI, an agreement, or
  paywalled access does NOT belong in `inst/extdata/`. Open data only.
- **No false license claims.** Check `data.ontario.ca` /
  `open.canada.ca` / `health-infobase` for the actual upstream license
  before adding a license note to a docstring. OTIS + CPADS were both
  falsely flagged as FOI/private — they are open.
- **No bloat.** This package is intentionally small. If a fixture would
  push it past ~5 MB, host it externally and add a fetcher function in
  rmorie instead.

## Where things live

| Path                        | What                                     |
|-----------------------------|------------------------------------------|
| `R/zzz.R`                   | Package skeleton (no exported functions) |
| `man/rmoriedata-package.Rd` | Package-level help                       |
| `inst/extdata/`             | The actual bundled data files            |
| `DESCRIPTION`               | Imports: none required at runtime        |
| `NAMESPACE`                 | Empty except for `useDynLib()` if any    |

## Adding a new fixture

1.  Find the upstream URL + verify the license is open.
2.  Write a refresh script under `data-raw/` (if not already present)
    that downloads + slices + saves to `inst/extdata/`.
3.  Document the upstream in a comment at the top of the file produced
    (URL + license + retrieval date).
4.  Run R CMD check locally — fixtures must round-trip without warnings.

## Commits

- Subject in imperative

- Body: WHY \> WHAT

- Dual co-author trailer required:

      Co-Authored-By: Claude <noreply@anthropic.com>
      Co-Authored-By: Vansh Singh Ruhela (rootcoder007) <vsruhela@proton.me>

## Contact

Vansh Singh Ruhela ([rootcoder007](https://github.com/rootcoder007)) ·
<vsruhela@proton.me>
