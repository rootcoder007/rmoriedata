# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("bundled samples load as base data.frames", {
  data(complaint_sample, package = "rmoriedata")
  data(arrest_sample, package = "rmoriedata")
  expect_s3_class(complaint_sample, "data.frame")
  expect_false(inherits(complaint_sample, "tbl_df"))   # base data.frame
  expect_s3_class(arrest_sample, "data.frame")
  expect_gt(nrow(complaint_sample), 0L)
  expect_gt(nrow(arrest_sample), 0L)
})

test_that("key columns exist", {
  data(complaint_sample, package = "rmoriedata")
  data(arrest_sample, package = "rmoriedata")
  for (col in c("case_number", "date", "date_iso", "iucr", "primary_type",
                "latitude", "longitude")) {
    expect_true(col %in% names(complaint_sample), info = col)
  }
  for (col in c("case_number", "date", "date_iso", "race", "charge_type")) {
    expect_true(col %in% names(arrest_sample), info = col)
  }
})

test_that("date_iso roundtrips (cross-language safety)", {
  data(complaint_sample, package = "rmoriedata")
  expect_type(complaint_sample$date_iso, "character")
  parsed <- as.POSIXct(complaint_sample$date_iso, format = "%Y-%m-%dT%H:%M:%S%z")
  expect_false(all(is.na(parsed)))
})
