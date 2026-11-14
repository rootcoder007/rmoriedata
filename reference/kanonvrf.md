# k-anonymity verification

Checks whether a data.frame satisfies k-anonymity over the supplied
quasi-identifier columns. A dataset is k-anonymous if every combination
of quasi-identifier values appears in at least `k` rows.

## Usage

``` r
kanonvrf(data, qids, k = 5)
```

## Arguments

- data:

  data.frame.

- qids:

  Character vector of column names.

- k:

  Minimum equivalence-class size. Default 5 (a common public-health /
  open-data threshold).

## Value

A list with class `"morie_k_anon"` containing:

- `satisfies`:

  logical, whether the dataset is k-anonymous.

- `k`:

  the threshold used.

- `min_class_size`:

  integer, size of the smallest class.

- `n_classes`:

  integer, total number of equivalence classes.

- `n_violations`:

  integer, number of classes below the threshold.

- `violating_classes`:

  data.frame of class keys plus their `.n` sizes (empty data.frame when
  none).

- `summary`:

  human-readable one-line summary.

## Details

A missing value (`NA`) in a quasi-identifier is treated as a value of
its own: rows with an unrecorded ward, age band or race form their own
classes and are counted, never dropped. Unrecorded values are often the
rarest records, which makes them the most re-identifiable, so they must
meet the threshold like any other class. Every row is accounted for: the
class sizes sum to `nrow(data)`. `NaN` counts as missing, in the same
class as `NA`.

Values are compared exactly. Two numbers are in one class only when they
are the same number in storage, whatever the column's class (plain
double, `Date`, `POSIXct`, `difftime`,
[`I()`](https://rdrr.io/r/base/AsIs.html) and other classed numbers
alike), so `0.1 + 0.2` and `0.3`, which differ in the last bit, are two
classes, and so are two times a microsecond apart; `-0` and `0` are one.
A complex number is compared by both parts. Integer, logical, character
and raw columns are compared by value, a factor by its level label and a
`POSIXlt` by the instant it names. A factor level that is itself `NA` is
missing, and the string `"NA"` is a value, not a missing one. A column
that cannot be compared exactly is refused with an error naming it: a
`bit64::integer64` column (convert it with
[`as.character()`](https://rdrr.io/r/base/character.html)), a list
column and a matrix column.

## Examples

``` r
df <- data.frame(
  age = c(25, 25, 25, 32, 32, 40),
  sex = c("F", "F", "F", "M", "M", "M")
)

# k = 2: the class {age=40, sex=M} has only 1 row -> VIOLATED.
res <- kanonvrf(df, c("age", "sex"), k = 2)
res$summary
#> [1] "k=2: VIOLATED (min class size=1; 1/3 classes below threshold)"
res$satisfies
#> [1] FALSE
res$violating_classes # the offending quasi-identifier combos
#>   age sex .n
#> 1  40   M  1

# Loosening to k = 1 always holds; the default k = 5 is stricter.
kanonvrf(df, c("age", "sex"), k = 1)$satisfies
#> [1] TRUE
kanonvrf(df, c("age", "sex"))$satisfies # k = 5
#> [1] FALSE

# A single quasi-identifier is fine too.
kanonvrf(df, "sex", k = 3)$min_class_size
#> [1] 3

# On real bundled data: are (year, arrest) cells 5-anonymous?
kanonvrf(complaint_sample,
  c("year", "arrest"),
  k = 5
)$summary
#> [1] "k=5: VIOLATED (min class size=1; 1/3 classes below threshold)"
```
