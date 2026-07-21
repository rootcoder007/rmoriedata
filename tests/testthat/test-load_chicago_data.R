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

test_that("limit and fraction are mutually exclusive and validated", {
  expect_error(load_chicago_data("arrests", full = TRUE, limit = 5,
                                 fraction = 0.5), "not both")
  expect_error(load_chicago_data("arrests", full = TRUE, limit = 0))
  expect_error(load_chicago_data("arrests", full = TRUE, limit = "x"))
  expect_error(load_chicago_data("arrests", full = TRUE, fraction = 0))
  expect_error(load_chicago_data("arrests", full = TRUE, fraction = 1.5))
  expect_error(load_chicago_data("arrests", full = TRUE, fraction = -0.1))
})

test_that("fraction resolves to a row cap from the live total (mocked)", {
  seen_limit <- NULL
  testthat::local_mocked_bindings(
    .rmd_full_count = function(type) 1000,
    .rmd_fetch_full = function(type, mirror, limit = NULL) {
      seen_limit <<- limit
      data.frame(case_number = as.character(seq_len(limit)))
    },
    .package = "rmoriedata"
  )
  df <- load_chicago_data("complaints", full = TRUE, fraction = 0.05)
  expect_identical(seen_limit, 50L)      # ceiling(1000 * 0.05)
  expect_equal(nrow(df), 50L)
})

test_that("limit is passed through verbatim (mocked)", {
  seen_limit <- NULL
  testthat::local_mocked_bindings(
    .rmd_fetch_full = function(type, mirror, limit = NULL) {
      seen_limit <<- limit
      data.frame(case_number = "x")
    },
    .package = "rmoriedata"
  )
  load_chicago_data("arrests", full = TRUE, limit = 123)
  expect_equal(seen_limit, 123)
})

test_that("a bounded fetch never reads or writes the full-dataset cache", {
  cache_dir <- rmoriedata:::.rmd_cache_dir()
  cache <- file.path(cache_dir, "arrests_full.parquet")
  # Plant a poisoned cache; a bounded fetch must ignore it and, on its own
  # network failure, error rather than silently serving the cache.
  had <- file.exists(cache)
  if (!had) {
    nanoparquet::write_parquet(data.frame(case_number = "cached"), cache)
    on.exit(unlink(cache), add = TRUE)
  }
  testthat::local_mocked_bindings(
    .rmd_endpoint = function(type) "http://127.0.0.1:9/nothing.csv",
    .package = "rmoriedata"
  )
  expect_error(
    rmoriedata:::.rmd_fetch_full("arrests", mirror = NULL, limit = 5),
    "could not fetch"
  )
  # And the poisoned cache was not overwritten by the bounded attempt.
  if (!had) {
    expect_identical(
      as.character(nanoparquet::read_parquet(cache)$case_number), "cached")
  }
})
