# Cell suppression with optional complementary suppression

Standard StatCan / open-data complementary-suppression: identifies
counts below \`threshold\`, suppresses them by setting to \`NA\`, and
(if \`return_complementary = TRUE\`) also suppresses the smallest other
count in each affected row and column so the suppressed value can't be
reconstructed from marginals.

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
              dimnames = list(c("A", "B", "C"), c("X", "Y", "Z")))

# Default: primary suppression (cells 1..4) PLUS complementary suppression
# so a suppressed cell can't be recovered from row/column marginals.
res <- morie_cell_suppress(tbl, threshold = 5)
res$suppressed              # NA where suppressed
#>     X  Y  Z
#> A 120 NA 14
#> B  NA NA NA
#> C  NA 99 60
res$n_primary              # cells below threshold
#> [1] 2
res$n_complementary        # extra cells hidden to protect the marginals
#> [1] 3
res$primary_mask
#>       X     Y     Z
#> A FALSE FALSE FALSE
#> B  TRUE  TRUE FALSE
#> C FALSE FALSE FALSE

# Turn complementary suppression off: only the small cells are hidden.
morie_cell_suppress(tbl, threshold = 5,
                    return_complementary = FALSE)$suppressed
#>     X  Y  Z
#> A 120 88 14
#> B  NA NA 51
#> C  47 99 60

# A higher threshold suppresses more cells.
morie_cell_suppress(tbl, threshold = 50)$n_primary
#> [1] 4

# Works on a 2-D table too; NA cells pass through untouched.
t2 <- as.table(matrix(c(2, 40, 30, 1), 2,
                      dimnames = list(c("a", "b"), c("c", "d"))))
morie_cell_suppress(t2, threshold = 5)$suppressed
#>   c d
#> a    
#> b    
```
