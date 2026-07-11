# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("load_chicago_data returns correct type per `as`", {
  expect_s3_class(load_chicago_data("complaints", as = "data.frame"),
                  "data.frame")

  skip_if_not_installed("tibble")
  expect_s3_class(load_chicago_data("arrests", as = "tibble"), "tbl_df")
})

test_that("parquet_path writes a readable file (nanoparquet)", {
  p <- load_chicago_data("complaints", as = "parquet_path")
  expect_true(file.exists(p))
  back <- as.data.frame(nanoparquet::read_parquet(p))
  expect_gt(nrow(back), 0L)
  expect_true("case_number" %in% names(back))
})

test_that("type + as are validated", {
  expect_error(load_chicago_data("bogus"), "should be one of")
  expect_error(load_chicago_data("arrests", as = "xml"), "should be one of")
})

test_that("full=TRUE fetches live Chicago data (opt-in only)", {
  # Heavy live Socrata fetch — never run in CI/CRAN. Opt in explicitly with
  # RMORIEDATA_TEST_LIVE=true when you actually want to hit the network.
  skip_on_cran()
  if (!identical(tolower(Sys.getenv("RMORIEDATA_TEST_LIVE")), "true")) {
    skip("live network test (set RMORIEDATA_TEST_LIVE=true to run)")
  }
  df <- load_chicago_data("complaints", full = TRUE)
  expect_s3_class(df, "data.frame")
  expect_gt(nrow(df), 0L)
})
