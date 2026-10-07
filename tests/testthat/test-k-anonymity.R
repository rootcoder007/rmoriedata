# SPDX-License-Identifier: AGPL-3.0-or-later

# Synthetic dataset with hand-counted equivalence classes:
#   (25, "F") -> 3 rows
#   (32, "M") -> 2 rows
#   (40, "M") -> 1 row
synth_df <- function() {
  data.frame(
    age = c(25, 25, 25, 32, 32, 40),
    sex = c("F", "F", "F", "M", "M", "M"),
    stringsAsFactors = FALSE
  )
}

test_that("k_anonymity returns the expected class sizes", {
  df <- synth_df()
  result <- morie_k_anonymity_verify(df, c("age", "sex"), k = 2)
  expect_s3_class(result, "morie_k_anon")
  expect_equal(result$n_classes, 3L)
  expect_equal(result$min_class_size, 1L)
  expect_false(result$satisfies)
  expect_equal(result$n_violations, 1L)
  expect_true("age" %in% names(result$violating_classes))
  expect_true("sex" %in% names(result$violating_classes))
  expect_equal(result$violating_classes$.n, 1L)
  expect_equal(result$violating_classes$age, 40)
  expect_equal(result$violating_classes$sex, "M")
})

test_that("k_anonymity with k=1 always satisfies non-empty data", {
  df <- synth_df()
  result <- morie_k_anonymity_verify(df, c("age", "sex"), k = 1)
  expect_true(result$satisfies)
  expect_equal(result$n_violations, 0L)
})

test_that("k_anonymity with k larger than every class fails", {
  df <- synth_df()
  result <- morie_k_anonymity_verify(df, c("age", "sex"), k = 100)
  expect_false(result$satisfies)
  expect_equal(result$n_violations, result$n_classes)
})

test_that("k_anonymity input validation", {
  df <- synth_df()
  expect_error(
    morie_k_anonymity_verify(list(a = 1), "a"),
    "data.frame"
  )
  expect_error(
    morie_k_anonymity_verify(df, character(0)),
    "non-empty character vector"
  )
  expect_error(
    morie_k_anonymity_verify(df, "not_a_column"),
    "Columns not found"
  )
  expect_error(
    morie_k_anonymity_verify(df, "age", k = 0),
    "positive integer"
  )
  expect_error(
    morie_k_anonymity_verify(df, "age", k = 2.5),
    "positive integer"
  )
})

test_that("l_diversity computes correct per-class distinct counts", {
  df <- data.frame(
    age = c(25, 25, 25, 25, 32, 32, 32),
    sex = c("F", "F", "F", "F", "M", "M", "M"),
    dx = c("A", "B", "C", "A", "X", "Y", "Z"),
    stringsAsFactors = FALSE
  )
  # (25,F) -> distinct {A,B,C} = 3
  # (32,M) -> distinct {X,Y,Z} = 3
  result <- morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 3)
  expect_s3_class(result, "morie_l_div")
  expect_true(result$satisfies)
  expect_equal(result$min_diversity, 3L)
  expect_equal(result$n_violations, 0L)

  # Tightening to l=4 should violate both classes.
  result_strict <- morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 4)
  expect_false(result_strict$satisfies)
  expect_equal(result_strict$n_violations, 2L)
})

test_that("l_diversity input validation", {
  df <- data.frame(a = 1:3, s = c("x", "y", "z"))
  expect_error(morie_l_diversity_verify(list(), "a", "s"), "data.frame")
  expect_error(
    morie_l_diversity_verify(df, character(0), "s"),
    "non-empty character vector"
  )
  expect_error(
    morie_l_diversity_verify(df, "a", c("s", "extra")),
    "single column name"
  )
  expect_error(
    morie_l_diversity_verify(df, "missing", "s"),
    "Columns not found"
  )
  expect_error(
    morie_l_diversity_verify(df, "a", "s", l = 0),
    "positive integer"
  )
})

test_that("cell_suppress suppresses primary cells below threshold", {
  tbl <- matrix(
    c(
      120, 47, 88,
      3, 99, 14,
      51, 60, 2
    ),
    nrow = 3, byrow = TRUE,
    dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
  )
  res <- morie_cell_suppress(tbl, threshold = 5, return_complementary = FALSE)
  expect_s3_class(res, "morie_cell_suppress")
  expect_equal(res$n_primary, 2L)
  expect_equal(res$n_complementary, 0L)
  expect_true(is.na(res$suppressed["B", "X"]))
  expect_true(is.na(res$suppressed["C", "Z"]))
  # Non-suppressed cells preserved.
  expect_equal(res$suppressed["A", "X"], 120)
  expect_equal(res$suppressed["B", "Y"], 99)
})

test_that("complementary suppression leaves no hidden cell recoverable from the totals", {
  # One small cell in row B. The 0.3.5 passes hid one complement in row B and one in
  # column X and stopped: row C then held a lone hidden cell, readable off row C's total.
  tbl <- matrix(
    c(
      120, 47, 88,
      3, 99, 14,
      51, 60, 60
    ),
    nrow = 3, byrow = TRUE,
    dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
  )
  res <- morie_cell_suppress(tbl, threshold = 5, return_complementary = TRUE)
  expect_equal(res$n_primary, 1L)
  expect_true(is.na(res$suppressed["B", "X"]))
  expect_true(res$protected)
  expect_equal(res$n_recoverable, 0L)
  hidden <- is.na(res$suppressed)
  # no row or column holds exactly one hidden cell
  expect_false(any(rowSums(hidden) == 1L))
  expect_false(any(colSums(hidden) == 1L))
  # published cells are untouched
  expect_equal(res$suppressed[!hidden], tbl[!hidden])
  # without complements the lone cell is recoverable, and the result says so
  bare <- morie_cell_suppress(tbl, threshold = 5, return_complementary = FALSE)
  expect_false(bare$protected)
  expect_true(bare$recoverable_mask["B", "X"])
})

test_that("a primary cell is not recoverable from the margins (review reproducer)", {
  # 0.3.5 published (NA NA 57 / NA 10 10 / 90 5 5): R2C1 = 100 - 20 = 80, then
  # R1C1 = 173 - 90 - 80 = 3, the primary cell, exactly
  tbl <- matrix(c(3, 40, 57, 80, 10, 10, 90, 5, 5), nrow = 3, byrow = TRUE,
                dimnames = list(c("R1", "R2", "R3"), c("C1", "C2", "C3")))
  res <- morie_cell_suppress(tbl, threshold = 5)
  expect_true(is.na(res$suppressed["R1", "C1"]))
  expect_true(res$protected)
  hidden <- is.na(res$suppressed)
  expect_false(any(rowSums(hidden) == 1L))
  expect_false(any(colSums(hidden) == 1L))
  # complements are never zero cells
  expect_false(any(tbl[res$complementary_mask] == 0))
})

test_that("k-anonymity counts rows with a missing quasi-identifier (review reproducer)", {
  d <- data.frame(zip = c(NA, NA, NA, "60601", "60601", "60601", "60601", "60601"),
                  sex = c("M", "F", "M", "F", "F", "F", "F", "F"))
  r <- morie_k_anonymity_verify(d, c("zip", "sex"), k = 3)
  expect_false(r$satisfies)
  expect_equal(r$min_class_size, 1L)
  expect_equal(r$n_classes, 3L)
  expect_true(any(is.na(r$violating_classes$zip)))
  # every row is accounted for
  # at k = 1 every class passes, the NA classes included
  expect_true(morie_k_anonymity_verify(d, c("zip", "sex"), k = 1)$satisfies)
})

test_that("l-diversity counts only known sensitive values (review reproducer)", {
  C <- data.frame(
    g = c("a", "a", "a", "b", "b", "b"),
    s = c("HIV", NA, NA, "FLU", "FLU", NA)
  )
  r <- morie_l_diversity_verify(C, "g", "s", l = 2)
  expect_false(r$satisfies)
  expect_equal(r$min_diversity, 1L)
  # a missing quasi-identifier is its own class here too
  D <- data.frame(g = c("a", "a", NA, NA), s = c("x", "y", "z", "z"))
  r2 <- morie_l_diversity_verify(D, "g", "s", l = 2)
  expect_equal(r2$n_classes, 2L)
  expect_false(r2$satisfies)
})

test_that("cell_suppress input validation", {
  tbl <- matrix(1:9, nrow = 3)
  expect_error(
    morie_cell_suppress(tbl, threshold = 0),
    "positive number"
  )
  expect_error(
    morie_cell_suppress(tbl,
      threshold = 5,
      return_complementary = NA
    ),
    "TRUE or FALSE"
  )
  char_tbl <- matrix(letters[1:9], nrow = 3)
  expect_error(
    morie_cell_suppress(char_tbl, threshold = 5),
    "numeric matrix or table"
  )
})
