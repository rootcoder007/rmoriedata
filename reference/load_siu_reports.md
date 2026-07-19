# Load the Ontario SIU director's-report corpus

Returns the bundled Ontario Special Investigations Unit (SIU)
director's-report table: one row per report drid, 65 structured columns
(police service, incident / notification / decision dates, investigator
and witness / subject-official counts, affected-person demographics,
injuries, legislation, charges verdict, director's decision, and
news-release linkage), plus a `panel_reviewed` flag.

## Usage

``` r
load_siu_reports(
  lang = c("all", "en", "fr"),
  as = c("data.frame", "tibble"),
  format = c("csv", "parquet")
)
```

## Source

Ontario Special Investigations Unit director's reports,
<https://www.siu.on.ca/en/directors_reports.php> (post-2018) and the
Ontario Government archive (pre-2018). Parsed with the rmorie SIU
subsystem.

## Arguments

- lang:

  One of `"all"` (default), `"en"`, or `"fr"`: filter to the
  English-only, French-only, or all rows.

- as:

  Return format: `"data.frame"` (default) or `"tibble"`.

## Value

A `data.frame` (or tibble) of SIU director's-report rows.

## Details

For every English report (`panel_reviewed == "TRUE"`), the 16 key
columns were verified by a multi-agent LLM review panel against the full
report text and the parser's guess resolved to the correct value; the
subject-official count is filled for 100% of English reports
(witness-officer-only investigations are a genuine 0). French reports
carry the parser values. See the `siu` pipeline repo for the audit
provenance.

This is the machine-readable companion to the SIU parser and data-mining
subsystem in rmorie / morie – the first open-source pipeline for the SIU
director's-report corpus, created by Vansh Singh Ruhela as part of the
MORIE / MRM framework. The table is regenerated from the parser over the
full public corpus; see `rmorie::morie_fetch_siu()` to rebuild it live.

## Examples

``` r
# Default: every parsed report, as a base data.frame.
all <- load_siu_reports()
nrow(all)
#> [1] 5157
ncol(all)
#> [1] 65

# `lang` filters the corpus by report language.
en <- load_siu_reports(lang = "en")   # English director's reports
fr <- load_siu_reports(lang = "fr")   # French director's reports
nrow(en); nrow(fr)
#> [1] 2182
#> [1] 2191

# `as = "tibble"` returns a tibble when the tibble package is present.
if (requireNamespace("tibble", quietly = TRUE)) {
  tb <- load_siu_reports(lang = "en", as = "tibble")
  class(tb)
}
#> [1] "tbl_df"     "tbl"        "data.frame"

# The five police services with the most reports.
if (nrow(en)) {
  top <- sort(table(en$police_service), decreasing = TRUE)
  head(top, 5)
}
#> 
#>          Toronto Police Service       Ontario Provincial Police 
#>                             467                             404 
#>            Peel Regional Police Niagara Regional Police Service 
#>                             188                              95 
#>         Hamilton Police Service 
#>                              91 
```
