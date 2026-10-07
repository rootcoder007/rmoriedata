# Cell suppression with complementary suppression and a recoverability audit

Suppresses (sets to `NA`) every count below `threshold`, then, when
`return_complementary = TRUE`, hides further cells until no suppressed
value can be solved exactly from the table's row and column totals,
which a published table normally carries.

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

  Logical; if `TRUE` (default), add complementary suppressions until no
  hidden cell is recoverable from the row and column totals.

## Value

A list with class `"morie_cell_suppress"`:

- `suppressed`:

  numeric matrix, suppressed cells set to NA.

- `primary_mask`:

  logical matrix, TRUE for primary suppressions.

- `complementary_mask`:

  logical matrix, TRUE for complementary suppressions (all FALSE when
  `return_complementary = FALSE`).

- `recoverable_mask`:

  logical matrix, TRUE for a hidden cell whose value the row and column
  totals determine exactly.

- `protected`:

  logical, TRUE when no hidden cell is recoverable. Test this before
  publishing.

- `n_primary`:

  integer.

- `n_complementary`:

  integer.

- `n_recoverable`:

  integer.

- `threshold`:

  the threshold used.

## Details

Complements are added to a fixed point. A row or column holding exactly
one hidden cell gives that cell away by subtraction, so every line with
a hidden cell gets a second one; a complement placed for a row is a
hidden cell in its column too, so the passes repeat until no line holds
a lone hidden cell. That condition is necessary but not sufficient, so
the result is then audited exactly: a hidden cell is recoverable when
the linear system of row and column totals determines it (its indicator
lies in the row space of the constraints over the hidden cells). Any
recoverable cell receives another complement in its row, and the audit
repeats. Complements are taken from positive cells, preferring one in a
line that already holds a hidden cell (which creates no new lone cell),
then the largest such cell, which leaves the widest range for the hidden
values. A zero cell is never used as a complement: it would bound the
hidden values from below at nothing.

The audit covers exact recovery from the margins. It does not compute
the feasible interval of each hidden cell, which bounds from
non-negativity can narrow; a table whose hidden values must stay inside
a wide interval needs an interval audit (linear programming) on top.

Only finite numeric cells are eligible for suppression. `NA` cells in
the input pass through unchanged and are treated as unpublished.

## Examples

``` r
tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60),
  nrow = 3,
  dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
)

res <- morie_cell_suppress(tbl, threshold = 5)
res$suppressed # NA where suppressed
#>    X  Y  Z
#> A NA NA 14
#> B NA NA 51
#> C 47 99 60
res$protected # no hidden cell can be solved from the totals
#> [1] TRUE
res$n_primary # cells below threshold
#> [1] 2
res$n_complementary # extra cells hidden to protect them
#> [1] 2

# Without complements the small cells are hidden but recoverable.
bare <- morie_cell_suppress(tbl, threshold = 5, return_complementary = FALSE)
bare$protected
#> [1] FALSE
bare$recoverable_mask
#>       X     Y     Z
#> A FALSE FALSE FALSE
#> B  TRUE  TRUE FALSE
#> C FALSE FALSE FALSE

# Works on a 2-D table too; NA cells pass through untouched.
t2 <- as.table(matrix(c(2, 40, 30, 1), 2,
  dimnames = list(c("a", "b"), c("c", "d"))
))
morie_cell_suppress(t2, threshold = 5)$suppressed
#>   c d
#> a    
#> b    
```
