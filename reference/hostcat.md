# Curated datasets at data.rmorie.com

Beyond the open data this package ships, the MORIE project keeps
databases materialised from Google BigQuery public datasets (Chicago
crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
Ethereum, World Bank, ...) and serves their tables from the edge. They
need no sign-in; a MORIE key stored earlier by rmorie, morie or
rmoriebricklayer is still sent. `hostcat()` returns every table with its
key, description, rows and BigQuery source (the manifest is kept for a
day); tables whose source terms do not allow redistribution (ICPSR
studies, among them the NCVS 38604 extract, and any table the manifest
marks restricted) are not served: they are left out, with a message
counting them, and `hostload()` refuses them before any request.
`hostload()` checks each table against the SHA-256 the manifest lists
for it (`sha256_gz`, `sha256` or `sha`) and refuses a file that does not
match; a table listed without any digest is used with a warning, once
per session. `hostload("db/table")` returns one table, cached under the
package cache directory
([`tempdir()`](https://rdrr.io/r/base/tempfile.html) unless
`options(rmoriedata.cache_dir = )` names a persistent one).

## Usage

``` r
hostcat(refresh = FALSE)

hostlogin(
  token = NULL,
  email = NULL,
  code = NULL,
  openbro = interactive(),
  ...
)

hostload(key, refresh = FALSE)
```

## Arguments

- refresh:

  Fetch again even when a day-old copy is cached.

- token, email, code, openbro:

  Passed to
  [`rmoriebricklayer::dlogin()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/dlogin.html):
  a key you already hold (no longer needed for the tables, which open
  without sign-in), or an email address (a one-time code is sent; pass
  it as `code` in a non-interactive session). With neither, the GitHub
  device flow runs. The service address comes from the signed services
  document
  ([`rmoriebricklayer::svcs()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/svcs.html)).

- ...:

  Passed to
  [`rmoriebricklayer::dlogin()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/dlogin.html):
  the data access terms and who is asking, which a new key needs
  (`accter`, `name`, `affil`, `purp`); what is not given is asked at the
  console.

- key:

  A `db/table` key from the catalog.

## Value

`hostlogin()`: the key, invisibly, after storing it in the shared
credentials file. `hostcat()`: a data frame with `key`, `name`, `rows`
and `source`; `hostload()`: the table as a data frame.

## Examples

``` r
if (FALSE) { # \dontrun{
head(hostcat())
df <- hostload("chicago_crime/incidents")
} # }
```
