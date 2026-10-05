# Load the Ontario SIU director's-report corpus

Returns the bundled Ontario Special Investigations Unit (SIU)
director's-report table: one row per report drid, 66 structured columns
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

- format:

  `"csv"` (the gzip CSV, default) or `"parquet"` (the same rows and
  columns, read from the typed store's Parquet copy and returned as
  text).

## Value

A `data.frame` (or tibble) of SIU director's-report rows.

## Details

For the English reports marked `panel_reviewed == "TRUE"`, the 16 key
columns were verified by a multi-agent LLM review panel against the full
report text and the parser's guess resolved to the correct value; the
subject-official count is filled for every one of them
(witness-officer-only investigations are a genuine 0). A French report
carries its English report's reviewed case facts (the dates, the team,
the counts, the affected person's age and sex, the charges and the
director's view) and `panel_reviewed == "FALSE"`; its text fields stay
French, and its `police_service` is its English report's service under
the name the SIU's French pages use.

`charges_recommended` is `"FALSE"`, `"TRUE"` or empty here (every column
is text); in the typed table,
`morie_data_load("siu_directors_reports")`, it is logical (`FALSE`,
`TRUE`, or `NA` when the report does not say). `corrigenda` holds the
SIU's correction notice of a report (a corrigendum is applied to the
report it corrects, not counted as a report). `narrative_summary` is the
opening of the report's own account of the incident (about 900
characters, at most 1,500, cut at a sentence end): its "Incident
Narrative" / "Description de l'incident" section, or, in reports without
one (2005-2016 and re-opened files), the "Notification of the SIU" /
"Avis a l'UES" section, which holds the account there. It is empty on
the 8 reports whose page has neither. `supplemental_materials` lists the
legislation and case-law links a report cites.

`police_service` is the service of the subject officials – not the force
that notified the SIU, which is often a custody, requesting or
neighbouring service. Each correction to it is listed with the reason
read from the report in `data-raw/siu_police_service_review.csv` of the
source repository.

One row is one published report, keyed by `drid` and `_language`. A case
number can appear on more than one row: the SIU publishes a further
report when a case is reconsidered or reported again, each with its own
`drid`. Some schema columns (for example the raw times of injury and
notification, evidence types, and weapons used) are not stated in the
published reports and are empty throughout; they are kept so the table's
shape matches the parser's schema.

This is the machine-readable companion to the SIU parser and data-mining
subsystem in rmorie / morie – the first open-source pipeline for the SIU
director's-report corpus, created by Vansh Singh Ruhela as part of the
MORIE / MRM framework. The table is regenerated from the parser over the
full public corpus; see `rmorie::morie_fetch_siu()` to rebuild it live.

This loader returns the corpus as text: every column is character and an
empty cell is `""`, which is the form the SIU parser writes and rmorie
reads back. The same table is also in the typed data store:
`morie_data_load("siu_directors_reports")` applies the bundled schema
(integer `drid` and counts, `NA` for empty cells), so counts of missing
values differ between the two entry points by construction; pick the
typed store for analysis and this loader for the parser round trip.

## Examples

``` r
# Default: every parsed report, as a base data.frame.
all <- load_siu_reports()
nrow(all)
#> [1] 4613
ncol(all)
#> [1] 66

# `lang` filters the corpus by report language.
en <- load_siu_reports(lang = "en") # English director's reports
fr <- load_siu_reports(lang = "fr") # French director's reports
nrow(en)
#> [1] 2309
nrow(fr)
#> [1] 2304

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
#>                             503                             450 
#>            Peel Regional Police Niagara Regional Police Service 
#>                             200                             102 
#>           Ottawa Police Service 
#>                              99 
```
