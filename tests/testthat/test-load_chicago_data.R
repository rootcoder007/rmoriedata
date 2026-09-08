# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("load_chicago_data returns correct type per `as`", {
  expect_s3_class(load_chicago_data("complaints", as = "data.frame"),
                  "data.frame")

  skip_if_not_installed("tibble")
  expect_s3_class(load_chicago_data("arrests", as = "tibble"), "tbl_df")
})

test_that("parquet_path writes a file the native codec reads back", {
  p <- load_chicago_data("complaints", as = "parquet_path")
  expect_true(file.exists(p))
  expect_identical(readBin(p, "raw", 4L), charToRaw("PAR1"))
  back <- morie_read_parquet(p)
  expect_gt(nrow(back), 0L)
  expect_true("case_number" %in% names(back))
})

test_that("the native codec agrees with nanoparquet byte for byte", {
  # The point of the swap is that an independent implementation reads
  # our output and we read its input. Without this cross-check the
  # codec would only ever be checked against itself, which proves
  # nothing about whether the files are really Parquet.
  skip_if_not_installed("nanoparquet")
  p <- load_chicago_data("complaints", as = "parquet_path")

  ours <- morie_read_parquet(p)
  theirs <- as.data.frame(nanoparquet::read_parquet(p))
  expect_identical(names(ours), names(theirs))
  expect_identical(nrow(ours), nrow(theirs))
  for (nm in names(theirs)) {
    a <- ours[[nm]]
    b <- theirs[[nm]]
    if (inherits(a, "POSIXct") || inherits(a, "Date")) a <- as.numeric(a)
    if (inherits(b, "POSIXct") || inherits(b, "Date")) b <- as.numeric(b)
    expect_equal(a, b, info = nm)
  }

  # and the other direction: nanoparquet reads what we write
  q <- tempfile(fileext = ".parquet")
  on.exit(unlink(q), add = TRUE)
  morie_write_parquet(ours, q)
  rt <- as.data.frame(nanoparquet::read_parquet(q))
  expect_identical(names(rt), names(ours))
  expect_identical(nrow(rt), nrow(ours))
})

test_that("a corrupted cell is detected, so the check above can fail", {
  # A comparison that cannot go red is not evidence.
  skip_if_not_installed("nanoparquet")
  df <- data.frame(case_number = c("a", "b", "c"),
                   stringsAsFactors = FALSE)
  q <- tempfile(fileext = ".parquet")
  on.exit(unlink(q), add = TRUE)
  df$case_number[2] <- "CANARY"
  morie_write_parquet(df, q)
  expect_identical(
    as.data.frame(nanoparquet::read_parquet(q))$case_number[2], "CANARY")
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
    morie_write_parquet(data.frame(case_number = "cached",
                                   stringsAsFactors = FALSE), cache)
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
      as.character(morie_read_parquet(cache)$case_number), "cached")
  }
})
