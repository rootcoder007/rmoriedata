# l-diversity verification

Checks whether a data.frame satisfies l-diversity: within each
equivalence class defined by the quasi-identifiers, the sensitive
attribute must take at least `l` distinct values.

## Usage

``` r
morie_l_diversity_verify(data, quasi_identifiers, sensitive, l = 3)
```

## Arguments

- data:

  data.frame.

- quasi_identifiers:

  Character vector of QI column names.

- sensitive:

  Name of the sensitive-attribute column.

- l:

  Minimum number of distinct sensitive values per class. Default 3.

## Value

A list with class `"morie_l_div"` containing:

- `satisfies`:

  logical.

- `l`:

  the threshold used.

- `min_diversity`:

  integer, lowest per-class distinct count.

- `n_classes`:

  integer.

- `n_violations`:

  integer, classes below the threshold.

- `violating_classes`:

  data.frame of class keys plus their `.diversity` count.

- `summary`:

  human-readable.

## Examples

``` r
df <- data.frame(
  age = c(25, 25, 25, 25, 32, 32, 32),
  sex = c("F", "F", "F", "F", "M", "M", "M"),
  dx  = c("A", "B", "C", "A", "X", "Y", "Z")
)
morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 3)
#> $satisfies
#> [1] TRUE
#> 
#> $l
#> [1] 3
#> 
#> $min_diversity
#> [1] 3
#> 
#> $n_classes
#> [1] 2
#> 
#> $n_violations
#> [1] 0
#> 
#> $violating_classes
#> [1] age        sex        .diversity
#> <0 rows> (or 0-length row.names)
#> 
#> $summary
#> [1] "l=3: SATISFIED (min diversity=3; 0/2 classes below threshold)"
#> 
#> attr(,"class")
#> [1] "morie_l_div"
```
