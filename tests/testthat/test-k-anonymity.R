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
  expect_error(morie_k_anonymity_verify(list(a = 1), "a"),
               "data.frame")
  expect_error(morie_k_anonymity_verify(df, character(0)),
               "non-empty character vector")
  expect_error(morie_k_anonymity_verify(df, "not_a_column"),
               "Columns not found")
  expect_error(morie_k_anonymity_verify(df, "age", k = 0),
               "positive integer")
  expect_error(morie_k_anonymity_verify(df, "age", k = 2.5),
               "positive integer")
})

test_that("l_diversity computes correct per-class distinct counts", {
  df <- data.frame(
    age = c(25, 25, 25, 25, 32, 32, 32),
    sex = c("F", "F", "F", "F", "M", "M", "M"),
    dx  = c("A", "B", "C", "A", "X", "Y", "Z"),
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
  expect_error(morie_l_diversity_verify(df, character(0), "s"),
               "non-empty character vector")
  expect_error(morie_l_diversity_verify(df, "a", c("s", "extra")),
               "single column name")
  expect_error(morie_l_diversity_verify(df, "missing", "s"),
               "Columns not found")
  expect_error(morie_l_diversity_verify(df, "a", "s", l = 0),
               "positive integer")
})

test_that("cell_suppress suppresses primary cells below threshold", {
  tbl <- matrix(
    c(120, 47, 88,
        3, 99, 14,
       51, 60,  2),
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

test_that("complementary suppression hides reconstructability per row + col", {
  # One small cell in row 'B' (value 3 < 5). The remaining row-B cells are
  # 99 and 14; complementary picks the smallest -> 14 -> "B","Z".
  # The same primary cell anchors column 'X' (other cells 120, 51);
  # complementary picks the smallest -> 51 -> "C","X".
  tbl <- matrix(
    c(120, 47, 88,
        3, 99, 14,
       51, 60, 60),
    nrow = 3, byrow = TRUE,
    dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
  )
  res <- morie_cell_suppress(tbl, threshold = 5, return_complementary = TRUE)
  expect_equal(res$n_primary, 1L)
  # one row-comp + one col-comp = 2 complementary suppressions
  expect_equal(res$n_complementary, 2L)
  expect_true(is.na(res$suppressed["B", "X"]))      # primary
  expect_true(is.na(res$suppressed["B", "Z"]))      # row complement (min of 99,14)
  expect_true(is.na(res$suppressed["C", "X"]))      # col complement (min of 120,51)
  # Untouched cells preserved.
  expect_equal(res$suppressed["A", "X"], 120)
  expect_equal(res$suppressed["A", "Y"], 47)
  expect_equal(res$suppressed["A", "Z"], 88)
  expect_equal(res$suppressed["B", "Y"], 99)
  expect_equal(res$suppressed["C", "Y"], 60)
  expect_equal(res$suppressed["C", "Z"], 60)
})

test_that("cell_suppress input validation", {
  tbl <- matrix(1:9, nrow = 3)
  expect_error(morie_cell_suppress(tbl, threshold = 0),
               "positive number")
  expect_error(morie_cell_suppress(tbl, threshold = 5,
                                   return_complementary = NA),
               "TRUE or FALSE")
  char_tbl <- matrix(letters[1:9], nrow = 3)
  expect_error(morie_cell_suppress(char_tbl, threshold = 5),
               "numeric matrix or table")
})
