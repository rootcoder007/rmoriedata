# Cell suppression with optional complementary suppression

Standard StatCan / open-data complementary-suppression: identifies
counts below `threshold`, suppresses them by setting to `NA`, and (if
`return_complementary = TRUE`) also suppresses the smallest other count
in each affected row and column so the suppressed value can't be
reconstructed from marginal sums.

## Usage

``` r
morie_cell_suppress(tbl, threshold = 5, return_complementary = TRUE)
```

## Arguments

- tbl:

  A numeric matrix or 2-D table of counts. Will be coerced to matrix;
  row/column names are preserved.

- threshold:

  Minimum count to remain unsuppressed. Default 5.

- return_complementary:

  Logical; if `TRUE` (default), apply complementary suppression so
  primary-suppressed cells can't be recovered from marginal sums.

## Value

A list with class `"morie_cell_suppress"`:

- `suppressed`:

  numeric matrix, suppressed cells set to NA.

- `primary_mask`:

  logical matrix, TRUE for primary suppressions.

- `complementary_mask`:

  logical matrix, TRUE for complementary suppressions (all FALSE when
  `return_complementary = FALSE`).

- `n_primary`:

  integer.

- `n_complementary`:

  integer.

- `threshold`:

  the threshold used.

## Details

Only finite numeric cells are eligible for suppression. `NA` cells in
the input pass through unchanged.

## Examples

``` r
tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60), nrow = 3,
              dimnames = list(c("A","B","C"), c("X","Y","Z")))
morie_cell_suppress(tbl, threshold = 5)
#> $suppressed
#>     X  Y  Z
#> A 120 NA 14
#> B  NA NA NA
#> C  NA 99 60
#> 
#> $primary_mask
#>       X     Y     Z
#> A FALSE FALSE FALSE
#> B  TRUE  TRUE FALSE
#> C FALSE FALSE FALSE
#> 
#> $complementary_mask
#>       X     Y     Z
#> A FALSE  TRUE FALSE
#> B FALSE FALSE  TRUE
#> C  TRUE FALSE FALSE
#> 
#> $n_primary
#> [1] 2
#> 
#> $n_complementary
#> [1] 3
#> 
#> $threshold
#> [1] 5
#> 
#> attr(,"class")
#> [1] "morie_cell_suppress"
```
