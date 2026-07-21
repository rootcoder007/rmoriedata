# Getting started with rmoriedata

`rmoriedata` bundles the open-data fixtures used across the `rmorie`
ecosystem and ships a small set of analyst-facing helpers for releasing
aggregate statistics without re-identification risk. Everything shown
here runs **offline** against data that installs with the package – no
network required.

The package has four surfaces:

1.  **A bundled dataset store** you browse and load by slug.
2.  **Named loaders** for the Chicago crime samples, the Ontario SIU
    director’s-report corpus, and the CIHI data-table catalogue.
3.  **Differential-privacy mechanisms** (`morie_dp_*`).
4.  **Re-identification-risk verifiers** (`morie_k_anonymity_verify`,
    `morie_l_diversity_verify`, `morie_cell_suppress`).

## 1. Browsing the bundled store

Every bundled table lives in a Parquet store.
[`morie_data_catalog()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_catalog.md)
lists what’s there, with row/column counts and the original source path.

``` r

cat <- morie_data_catalog()
table(cat$kind)
#> 
#> dictionary      table 
#>          8         88
head(cat[cat$kind == "table", c("slug", "n_rows", "n_cols")])
#>                                                          slug n_rows n_cols
#> 1                 arsau_uof_detailed_dataset_2020_2022_sample      5    167
#> 2                         arsau_uof_individual_records_sample      5    112
#> 3 arsau_2020_2022_useofforce_agrregatesummarybyyear_2020_2022      5      6
#> 4        arsau_2020_2022_useofforce_detaileddataset_2020_2022      5    167
#> 5                           arsau_2023_uof_individual_records      5    112
#> 6                                 arsau_2023_uof_main_records      5     23
```

Load any table by its `slug`:

``` r

iucr <- morie_data_load("chicago_iucr_codes")
head(iucr)
#>   iucr primary_description         secondary_description index_code active
#> 1 031A             ROBBERY               ARMED - HANDGUN          I   True
#> 2 031B             ROBBERY         ARMED - OTHER FIREARM          I   True
#> 3 033A             ROBBERY       ATTEMPT ARMED - HANDGUN          I   True
#> 4 033B             ROBBERY ATTEMPT ARMED - OTHER FIREARM          I   True
#> 5 041A             BATTERY          AGGRAVATED - HANDGUN          I   True
#> 6 041B             BATTERY    AGGRAVATED - OTHER FIREARM          I   True
```

Unknown slugs error with guidance rather than failing silently:

``` r

morie_data_load("no_such_dataset")
#> Error:
#> ! No dataset 'no_such_dataset'. See morie_data_catalog() for valid slugs.
```

Some tables ship a data dictionary (JSON). Find them via the catalogue’s
`kind` column:

``` r

dict_slugs <- cat$slug[cat$kind == "dictionary"]
head(dict_slugs)
#> [1] "arsau_2020_2022_dictionary" "arsau_2023_dictionary"     
#> [3] "arsau_2024_dictionary"      "corrections_uof_dictionary"
#> [5] "cpads_data_provenance"      "otis_dictionary"
```

## 2. The named loaders

### Chicago crime samples

Two CRAN-safe slices of the City of Chicago open data ship as
lazy-loaded data objects, and
[`load_chicago_data()`](https://rootcoder007.github.io/rmoriedata/reference/load_chicago_data.md)
wraps them (with an optional `full = TRUE` network fetch of the complete
dataset).

``` r

comp <- load_chicago_data("complaints")
dim(comp)
#> [1] 25000    16
head(sort(table(comp$primary_type), decreasing = TRUE), 5)
#> 
#>           THEFT         BATTERY CRIMINAL DAMAGE         ASSAULT   OTHER OFFENSE 
#>            5825            4800            2362            1975            1760

arr <- load_chicago_data("arrests")
sort(table(arr$charge_type), decreasing = TRUE)
#> 
#>     M           F 
#> 12342  6464  6194
```

### Ontario SIU director’s reports

The first open, machine-readable parse of the Ontario Special
Investigations Unit director’s-report corpus – one row per report, 64
structured columns.

``` r

en <- load_siu_reports(lang = "en")
nrow(en)
#> [1] 2182
head(sort(table(en$police_service), decreasing = TRUE), 5)
#> 
#>          Toronto Police Service       Ontario Provincial Police 
#>                             467                             404 
#>            Peel Regional Police Niagara Regional Police Service 
#>                             188                              95 
#>         Hamilton Police Service 
#>                              91
```

### CIHI data-table catalogue

A catalogue of the public CIHI data-table workbooks, each with a live
URL and an Internet Archive fallback so the table stays retrievable if
CIHI rotates the file.
([`fetch_cihi_table()`](https://rootcoder007.github.io/rmoriedata/reference/fetch_cihi_table.md)
does the actual download and is a network call, so it isn’t run here.)

``` r

tables <- load_cihi_data_tables()
nrow(tables)
#> [1] 232
head(tables$title, 3)
#> [1] "Injury and Trauma Emergency Department and Hospitalization Statistics, 2024–2025"
#> [2] "Wait Times for Priority Procedures in Canada, 2008 to 2025 — Data Tables"        
#> [3] "Health Workforce in Canada, 2024 — Quick Stats"
```

## 3. Data integrity

Verify you’re using the exact data slice the package shipped:

``` r

ck <- morie_data_checksums()
head(ck[order(-ck$bytes), c("file", "bytes")], 3)
#>                              file    bytes
#> 165             rmoriedata.sqlite 14831616
#> 28            describe_corpus.Rds  1712072
#> 171 siu_directors_reports.parquet  1035827

# The same compiled SHA256 kernel the whole ecosystem uses:
morie_core_sha256("abc")
#> [1] "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
```

## 4. Differential privacy

Release counts, means, and histograms with calibrated noise. Smaller
`epsilon` means stronger privacy and more noise.

``` r

set.seed(1)

# A private count of records matching a predicate.
morie_dp_laplace_count(true_count = 42, epsilon = 1.0)
#> [1] 41.36704

# The mechanism is unbiased -- averaging many releases recovers the truth.
mean(replicate(2000, morie_dp_laplace_count(42, epsilon = 1.0)))
#> [1] 41.98688

# A private mean of bounded data.
x <- runif(1000, 0, 1)
morie_dp_gaussian_mean(x, lower = 0, upper = 1, epsilon = 1.0)
#> [1] 0.4893552

# A private histogram straight from tabulated data.
counts <- as.integer(table(comp$year))
round(pmax(0, morie_dp_laplace_histogram(counts, epsilon = 1.0)))
#> [1] 24999     2
```

## 5. Re-identification risk

Check a release against the standard disclosure-control thresholds
before publishing it.

``` r

df <- data.frame(
  age = c(25, 25, 25, 32, 32, 40),
  sex = c("F", "F", "F", "M", "M", "M")
)

# k-anonymity: every quasi-identifier combo must appear >= k times.
morie_k_anonymity_verify(df, c("age", "sex"), k = 2)$summary
#> [1] "k=2: VIOLATED (min class size=1; 1/3 classes below threshold)"

# l-diversity: each class must hold >= l distinct sensitive values.
df2 <- data.frame(
  age = c(25, 25, 25, 25, 32, 32, 32),
  sex = c("F", "F", "F", "F", "M", "M", "M"),
  dx  = c("A", "B", "C", "A", "X", "Y", "Z")
)
morie_l_diversity_verify(df2, c("age", "sex"), "dx", l = 3)$summary
#> [1] "l=3: SATISFIED (min diversity=3; 0/2 classes below threshold)"
```

Cell suppression hides small counts and (by default) applies
complementary suppression so the hidden values can’t be recovered from
the marginals:

``` r

tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60), nrow = 3,
              dimnames = list(c("A", "B", "C"), c("X", "Y", "Z")))
res <- morie_cell_suppress(tbl, threshold = 5)
res$suppressed
#>     X  Y  Z
#> A 120 NA 14
#> B  NA NA NA
#> C  NA 99 60
```

## Bridging to Python

`load_chicago_data(..., as = "parquet_path")` writes a Parquet file and
returns its path – the recommended hand-off to `pandas.read_parquet()`.
Because the store is Parquet throughout, the same tables load natively
in R, Python, DuckDB, and Arrow.
