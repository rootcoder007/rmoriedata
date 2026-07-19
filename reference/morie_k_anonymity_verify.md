# k-anonymity verification

Checks whether a data.frame satisfies k-anonymity over the supplied
quasi-identifier columns. A dataset is k-anonymous if every combination
of quasi-identifier values appears in at least \`k\` rows.

## Usage

``` r
morie_k_anonymity_verify(data, quasi_identifiers, k = 5)
```

## Arguments

- data:

  data.frame.

- quasi_identifiers:

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

## Examples

``` r
df <- data.frame(
  age = c(25, 25, 25, 32, 32, 40),
  sex = c("F", "F", "F", "M", "M", "M")
)

# k = 2: the class {age=40, sex=M} has only 1 row -> VIOLATED.
res <- morie_k_anonymity_verify(df, c("age", "sex"), k = 2)
res$summary
#> [1] "k=2: VIOLATED (min class size=1; 1/3 classes below threshold)"
res$satisfies
#> [1] FALSE
res$violating_classes        # the offending quasi-identifier combos
#>   age sex .n
#> 1  40   M  1

# Loosening to k = 1 always holds; the default k = 5 is stricter.
morie_k_anonymity_verify(df, c("age", "sex"), k = 1)$satisfies
#> [1] TRUE
morie_k_anonymity_verify(df, c("age", "sex"))$satisfies   # k = 5
#> [1] FALSE

# A single quasi-identifier is fine too.
morie_k_anonymity_verify(df, "sex", k = 3)$min_class_size
#> [1] 3

# On real bundled data: are (year, arrest) cells 5-anonymous?
morie_k_anonymity_verify(complaint_sample,
  c("year", "arrest"), k = 5)$summary
#> [1] "k=5: VIOLATED (min class size=1; 1/3 classes below threshold)"
```
