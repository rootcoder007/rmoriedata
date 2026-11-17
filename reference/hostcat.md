# Curated datasets at data.rmorie.com

Beyond the open data this package ships, the MORIE project keeps
databases materialised from Google BigQuery public datasets (Chicago
crime, EPA air quality, US census, FEC, FDA, NOAA, NHTSA, Hacker News,
Ethereum, World Bank, ...) and serves their tables from the edge. They
need no sign-in and no key; a key that an earlier version of this or a
related package stored is not read and never sent. `hostcat()` returns
every table with its key, description, rows and BigQuery source (the
manifest is kept for a day); tables whose source terms do not allow
redistribution (ICPSR studies, among them the NCVS 38604 extract, and
any table the manifest marks restricted) are not served: they are left
out, with a message counting them, and `hostload()` refuses them before
any request. A table is served only when its `access` mark, if any, is
`"open"` or `"public"` and its `restricted` mark, if any, is `false`; a
mark of any other value or shape counts as restricted. `hostload()`
checks each table against the SHA-256 the manifest lists for it
(`sha256_gz`, `sha256` or `sha`) and refuses a file that does not match;
a table listed without any digest is used with a warning, once per
session. `hostload("db/table")` returns one table, cached under the
package cache directory
([`tempdir()`](https://rdrr.io/r/base/tempfile.html) unless
`options(rmoriedata.cache_dir = )` names a persistent one).

## Usage

``` r
hostcat(refresh = FALSE)

hostload(key, refresh = FALSE)
```

## Arguments

- refresh:

  Fetch again even when a day-old copy is cached.

- key:

  A `db/table` key from the catalog: segments of ASCII letters, digits,
  `_`, `-` and `.`, none starting with a dot, joined by single slashes.
  Any other key is refused before anything is requested, and a manifest
  entry whose key is not of this form is not served.

## Value

`hostcat()`: a data frame with `key`, `name`, `rows` (`NA` where the
manifest gives no whole count) and `source`; `hostload()`: the table as
a data frame.

## Details

`hostload()` returns the table as the file holds it, as the bundled
tables are read: the column names as written (as the manifest lists
them); an empty field is missing in a logical or number column and `""`
in a text column (the text `"NA"` is a value). A column is logical,
integer or double only when every value in it is written the way R
writes such a value: `TRUE` or `FALSE`; whole numbers without a leading
zero or a plus sign; for double, numbers without a leading zero, whole
ones of at most 15 digits (which a double holds exactly) and decimal
ones of at most 17 significant digits (zeros after the decimal point are
formatting, and `"6.0"` is 6), or in R's own exponent form (`1e-05`).
Any other column is text, so a code such as `"046"` keeps its leading
zero, and `"+3"`, `".5"`, `"0x1A"`, `"Inf"` or an identifier of 16 or
more digits keep every character. A column with no value at all is
logical `NA`. Text is marked UTF-8, whatever the session's locale; bytes
that are not valid UTF-8 are marked `"bytes"`, and a NUL byte, which no
R string holds, is dropped. Quoted fields may hold commas, quotes and
line breaks (a Windows line end inside a field reads as `"\n"`); Windows
line ends and a byte-order mark are allowed. A record with more or fewer
fields than the header is a damaged download: the copy is deleted and
the call fails, so the next call fetches it again.

The manifest is fetched again once the cached copy is a day old. When
that fails (offline, or the service is down) the cached copy is used,
with a message, so a table already cached in a persistent
`rmoriedata.cache_dir` still loads offline; every table is still checked
against the digest the manifest lists, and one that does not match is
not used. With `refresh = TRUE` the manifest must be fetched: when it
cannot be, `hostcat()` and `hostload()` stop with an error instead of
using the cached copy.

R sessions loading the same table take turns: while one downloads it, or
checks its cached copy, the others wait. A session whose wait sees the
download not grow for `options(rmoriedata.lockwait = )` seconds (600 by
default) stops with an error saying the other session may be stalled.

## Examples

``` r
if (FALSE) { # \dontrun{
head(hostcat())
df <- hostload("chicago_crime/incidents")
} # }
```
