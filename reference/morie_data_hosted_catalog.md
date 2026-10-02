# Curated datasets at data.rmorie.com

Beyond the open data this package ships, the MORIE project keeps 160
databases materialised from Google BigQuery public datasets (Chicago
crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
Ethereum, World Bank, ...) and serves their tables from the edge. They
open with the MORIE key that rmorie, morie or rmoriebricklayer store
(`rmorie login`, `rmorie::morie_llm_login()`,
[`rmoriebricklayer::bricklayer_llm_login()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_login.html)).
`morie_data_hosted_catalog()` returns every table with its key,
description, rows and BigQuery source (the manifest is kept for a day);
`morie_data_hosted_load("db/table")` returns one table, cached under the
package cache directory
([`tempdir()`](https://rdrr.io/r/base/tempfile.html) unless
`options(rmoriedata.cache_dir = )` names a persistent one).

## Usage

``` r
morie_data_hosted_catalog(refresh = FALSE)

morie_data_hosted_login(
  token = NULL,
  email = NULL,
  code = NULL,
  open_browser = interactive()
)

morie_data_hosted_load(key, refresh = FALSE)
```

## Arguments

- refresh:

  Fetch again even when a day-old copy is cached.

- token, email, code, open_browser:

  Passed to
  [`rmoriebricklayer::bricklayer_llm_login()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_login.html):
  a key you already hold, or an email address (a 6-digit code is sent;
  pass it as `code` in a non-interactive session). With neither, the
  GitHub device flow runs.

- key:

  A `db/table` key from the catalog.

## Value

`morie_data_hosted_login()`: the key, invisibly, after storing it in the
shared credentials file. `morie_data_hosted_catalog()`: a data frame
with `key`, `name`, `rows` and `source`; `morie_data_hosted_load()`: the
table as a data frame.

## Examples

``` r
if (FALSE) { # \dontrun{
head(morie_data_hosted_catalog())
df <- morie_data_hosted_load("chicago_crime/incidents")
} # }
```
