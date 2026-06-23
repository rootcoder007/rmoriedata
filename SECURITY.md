# Security policy & architecture

`rmoriedata` is the **R companion data package** for
[rmorie](https://github.com/rootcoder007/rmorie). AGPL-3.0-or-later.
Distributed via r-universe today; CRAN submission planned alongside
rmorie v1.0.0 alpha.

This package ships only **bundled `.rda` / `.csv` fixtures** drawn from
public Canadian + US open-data portals (TPS, OTIS, ARSAU, Chicago, NYC,
Vancouver, Statistics Canada CODR, Montreal, Calgary, Ottawa, Edmonton).
**No private, FOI-restricted, or agreement-only data is in this package.**
That property is the central security claim and the rest of this document
explains how it is enforced.

> **Status (2026-05-26):** repository scaffold exists; package contents
> are being staged in [`/Volumes/VSR/rootcoderfiles/rmoriedata-staging/`](../rmoriedata-staging/)
> in parallel. The SECURITY policy is being put in place ahead of the
> first public r-universe push so the conformance discipline is
> established from day one.

## Reporting a vulnerability

Email **<vsruhela@proton.me>** with subject `[SECURITY] rmoriedata` —
**do not** open a public GitHub Issue for security reports. GitHub's
[private vulnerability reporting](https://github.com/rootcoder007/rmoriedata/security/advisories/new)
will be enabled at first public push. PGP preferred:

```
gpg --recv-keys F2A44D5982E7585E48DF861E335990B9336F7DD6
```

Please include:

- Description, impact, CVSS estimate.
- For data-leak reports: the dataset key, the licence the upstream
  publishes under, and the redistribution restriction you believe
  applies.
- `packageVersion("rmoriedata")` + `R.version.string` + platform.
- Whether you want CHANGELOG + NEWS.md credit.

**SLA**

| Severity                                                            | Acknowledge | Fix or mitigation |
| ------------------------------------------------------------------- | ----------- | ----------------- |
| High (private / FOI / agreement-only data in a bundled fixture)     | 24 hours    | 24 hours (yank)   |
| High (fabricated `rnorm()` / `sample()` data documented as real)    | 72 hours    | 14 days           |
| Moderate (stale fixture vs. live portal, missing licence note)      | 72 hours    | 30 days           |
| Low (typo, broken provenance URL)                                   | 72 hours    | 90 days           |

A **High data-leak report triggers same-day package retraction** from
r-universe and a CRAN withdrawal request if applicable. No bug bounty
(yet). Valid reports get credit by default.

## Threat model

`rmoriedata` is a **data-only R package**. The host R session and
user are trusted; **the contents of this package are the asset**.

**Adversaries we model:**

1. **A maintainer (me, or an LLM-driven agent) accidentally bundling
   private / FOI / agreement-only data.** This is the dominant
   threat. Mitigation: every CSV / `.rda` in `inst/extdata/` and
   `data/` carries a provenance note in `data-raw/` recording:
   - The public open-data portal URL.
   - The licence string verbatim (Open Government Licence — Ontario;
     City of Toronto Open Data Licence; Open Data Commons; etc.).
   - The fetch date and the upstream version / SHA.
   - The retrieval script that produced the bundled artifact.

   The CI gate refuses to publish a fixture whose `data-raw/` script
   doesn't exist or doesn't pass a portal-URL + licence sanity check.

2. **An LLM-driven agent fabricating bundled data.** Bit us on the
   morie side before; the rule here is hard: any bundled file is
   either (a) a real slice from a public portal or (b) a
   typed-empty 0-row frame with a documented schema. **Never**
   `rnorm()` / `sample()` invented values, ever, regardless of
   how innocuous it looks.

3. **An attacker tampering with a bundled fixture in flight.**
   Mitigated by GPG-signed Git tags + SHA-256 sidecars on
   release artifacts + GitHub's transparency log + the SLSA build
   provenance attestation.

4. **A stale fixture mis-represented as current.** Every `data/*.rda`
   ships with a `last_fetched` attribute (UTC, RFC 3339) and an
   `upstream_url` attribute. `R/rmoriedata_provenance.R` exposes
   these. v1.0+: a `rmoriedata_check_freshness()` helper diffs
   bundled vs. live for the user.

5. **A re-identification attack on a "public-but-sensitive" fixture.**
   Some open-data portals publish low-cell counts that, joined with
   other public data, may be re-identifiable. Mitigated by:
   - Refusing to bundle small-cell tables (n < threshold per
     upstream guidance).
   - Documenting any aggregation we apply before bundling.
   - Linking to upstream methodology for caveats.

**Assets we protect:**

- **The "no private data" invariant** (highest priority).
- **The "no fabricated data" invariant.**
- **Fixture integrity** (no tampering between maintainer and user).
- **Provenance accuracy** — the URL + licence + date on every
  bundled artifact.

**Out of scope:**

- **Host-OS / R-runtime compromise.** Beyond our reach.
- **Analytical conclusions drawn from the data.** Those live in
  rmorie / morie / papers, not here.
- **Upstream portal availability.** If `data.ontario.ca` goes
  down, the bundled fixture is the user's only copy until the
  portal returns; we make no SLA promise.
- **Upstream portal correctness.** If OTIS publishes wrong numbers,
  we bundle wrong numbers. We are a faithful mirror.

**Trust boundaries:**

| Boundary                              | Crossing                                                |
| ------------------------------------- | ------------------------------------------------------- |
| Public portal → maintainer machine    | `data-raw/*.R` ingestion scripts (one-time, audited)    |
| Maintainer → packaged `.rda`          | `data-raw/*.R` → `usethis::use_data()`                  |
| Packaged `.rda` → user R session      | `data(<name>, package = "rmoriedata")`                  |
| Provenance metadata → user            | Attributes on every bundled object                      |

## Cryptographic posture

`rmoriedata` is a **passive data package**. No crypto primitives are
exposed at the API surface. The crypto that matters is:

- **Release-tag GPG signature** with
  `F2A44D5982E7585E48DF861E335990B9336F7DD6` (same key as the rest of
  the morie family).
- **SHA-256** sidecar (`.sha256`) on each release artifact.
- **SLSA L3 build provenance** attestation from
  [`actions/attest-build-provenance`](https://github.com/actions/attest-build-provenance);
  `gh attestation verify` confirms what tag built what bytes.
- **(Roadmap)** RFC 3161 timestamp from a Canadian TSA
  (`timestamp.entrust.net`) over each bundled-fixture manifest, so
  the user can prove the bundled bytes existed at a given moment
  even if the GitHub Release is later deleted.

For users who want to seal *their own* derivatives, the crypto stack
in [rmorie](https://github.com/rootcoder007/rmorie) is available:
X25519 + ML-KEM-768 KEX, Ed25519 + ML-DSA-65 signatures,
ChaCha20-Poly1305 AEAD, Argon2id KDF — all libsodium + liboqs.

## Control mapping

| Requirement                                  | Where                                                                                                | ITSG-33     | NIST 800-53 (Mod) | OWASP ASVS L2 | Ontario MGCS IT Sec |
| -------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------- | ----------------- | ------------- | ------------------- |
| Data provenance (URL + licence + date)       | `data-raw/*.R` per-fixture + attributes on every `data/*.rda`                                        | SI-12       | SI-12             | V14.3.3       | §4 Data class       |
| "No private data" gate                       | CI step refuses release if any fixture lacks a `data-raw/` script + portal URL + licence string     | AC-21       | AC-21             | V1.8.1        | §4 Data class       |
| "No fabricated data" gate                    | Per-fixture parity check vs. live portal at build time (best-effort) + maintainer policy             | SI-7        | SI-7              | V14.3.3       | §6.3 Integrity      |
| Open licence compatibility check             | `inst/LICENCES/` enumerates every upstream licence; CI fails on unknown licence                      | SA-4        | SA-4              | V1.1.1        | §3 Acceptable use   |
| Reproducible build                           | `DESCRIPTION` pins R-deps; `data-raw/` is fully deterministic given fetch-date                       | CM-2        | CM-2              | V14.2.1       | §6.2 Change ctrl    |
| SHA-256 sidecars on release                  | release workflow                                                                                     | SI-7        | SI-7              | V10.3.1       | §6.3 Integrity      |
| GPG-signed Git tags                          | key `F2A44D5982E7585E48DF861E335990B9336F7DD6`                                                       | AU-10       | AU-10             | V10.3.1       | §6.3 Integrity      |
| SLSA L3 build provenance                     | `actions/attest-build-provenance`                                                                    | SR-4        | SR-4              | V14.2.6       | §6.2 Change ctrl    |
| Vulnerability disclosure                     | This document + GitHub Security Advisories                                                           | IR-6        | IR-6              | V1.1.4        | §7 Incident         |
| Same-day yank procedure for data leaks       | Documented retraction procedure (see "Audit & non-repudiation")                                      | IR-4        | IR-4              | V1.1.4        | §7 Incident         |

ITSG-33: Treasury Board of Canada IT Security Guidance. NIST 800-53 Rev 5 moderate baseline. [OWASP ASVS 4.0.3](https://github.com/OWASP/ASVS/).

## Supply chain

- **Reproducible fetches.** Every `data-raw/*.R` script is
  deterministic given the fetch date and the upstream portal state.
  Scripts pin upstream SHAs / resource IDs / Socrata view-IDs
  where the portal exposes them.
- **SBOM.** A CycloneDX SBOM of the R-package surface is attached
  per release; the per-fixture provenance file
  (`inst/provenance.json`) acts as the data-asset BoM.
- **Signed releases.** GPG-signed tags + SHA-256 sidecars on every
  release artifact + SLSA L3 attestation.
- **CI action pinning.** All `uses:` in `.github/workflows/` pinned
  by full commit SHA, never tag.

## Audit & non-repudiation

- **Per-fixture provenance** — embedded as attributes on every
  bundled object and as a sibling `inst/provenance.json` for
  programmatic inspection.
- **Hash-chained release manifest** — each release publishes a
  signed manifest of `{fixture_name, sha256, fetched_at,
  upstream_url, licence}` rows; the chain ties to the prior release
  so insertions / deletions are detectable.
- **(Roadmap)** RFC 3161 timestamp on the manifest.

**Data-leak retraction procedure:**

1. Maintainer marks the affected release as **withdrawn** on
   r-universe + GitHub Releases.
2. New patch release ships with the fixture removed + a
   `Deprecated` note in `NEWS.md`.
3. If CRAN submission has happened, a withdrawal request goes to
   CRAN simultaneously.
4. A post-mortem entry in `docs/POSTMORTEMS.md` records what
   leaked, how it got in, and what gate failed.

## What this component does NOT defend against

- **A user re-distributing bundled fixtures under an incompatible
  licence.** The bundled licences are documented; downstream
  compliance is the user's.
- **A determined re-identification attack across portals.** We
  refuse low-cell tables, but composability across portals is
  beyond our visibility.
- **Stale fixtures.** A bundled `.rda` is a snapshot, not a live
  view; the `last_fetched` attribute is the user's clue.
- **Upstream portal misinformation.** Garbage in, garbage in (we're
  a mirror).
- **A user querying upstream portals directly via rmorie/morie.**
  That trust boundary is [rmorie's SECURITY](https://github.com/rootcoder007/rmorie/blob/main/SECURITY.md),
  not ours.

## Roadmap

**Wave 1 — in flight (initial release)**

- "No private data" CI gate.
- "No fabricated data" parity-against-live gate.
- Per-fixture provenance attributes + `inst/provenance.json`.
- GPG-signed release tags + SHA-256 sidecars.
- Same-day yank procedure documented.

**Wave 2 — in progress / done**

- **DP + k-anonymity helpers — done (v0.1.1).** Six exported, base-R-only
  primitives for analysts releasing aggregates without re-identification
  risk: `morie_dp_laplace_count()`, `morie_dp_gaussian_mean()`,
  `morie_dp_laplace_histogram()`, `morie_k_anonymity_verify()`,
  `morie_l_diversity_verify()`, `morie_cell_suppress()`. Round-trip /
  variance-scaling tests under `tests/testthat/`.
- SLSA L3 attestation on every release.
- Hash-chained release manifest.
- `rmoriedata_check_freshness()` helper.
- macOS / Windows binary-package signing once CRAN submission
  begins.

**Future**

- RFC 3161 timestamping over the manifest from a Canadian TSA.
- CRAN submission alongside rmorie v1.0.0 alpha.

---

Maintainer: **Vansh Singh Ruhela** ([rootcoder007](https://github.com/rootcoder007))
&nbsp;·&nbsp; <vsruhela@proton.me>
