# The live-network branches, driven by local files instead of a server:
# `.rmd_full_url()` is pointed at file:// URLs and the row count is mocked.

local_chicago_cache <- function(env = parent.frame()) {
  d <- file.path(tempfile("cache"), "rmoriedata")
  dir.create(d, recursive = TRUE)
  testthat::local_mocked_bindings(.rmd_cache_dir = function() d,
                                  .package = "rmoriedata", .env = env)
  d
}
csv_file <- function(text) {
  f <- tempfile(fileext = ".csv")
  writeLines(text, f)
  paste0("file://", f)
}
good_csv <- function(n) {
  csv_file(c("id,name,value", sprintf("%d,row %d,%g", seq_len(n), seq_len(n),
                                      seq_len(n) * 1.5)))
}
point_at <- function(url, count = NA_real_, env = parent.frame()) {
  testthat::local_mocked_bindings(
    .rmd_full_url = function(type, n) url,
    .rmd_full_count_or_na = function(type) count,
    .package = "rmoriedata", .env = env
  )
}

test_that("outage page, header-only body and short export are refused, not cached", {
  d <- local_chicago_cache()
  cache <- file.path(d, "arrests_full.parquet")
  html <- csv_file("<html><body><h1>Service Unavailable</h1></body></html>")
  point_at(html, count = 500)
  expect_error(rmoriedata:::.rmd_fetch_full("arrests", NULL), "single column")
  expect_false(file.exists(cache))
  point_at(csv_file("id,name,value"), count = 500)
  expect_error(rmoriedata:::.rmd_fetch_full("arrests", NULL), "no rows")
  expect_false(file.exists(cache))
  point_at(good_csv(10), count = 500)
  expect_error(rmoriedata:::.rmd_fetch_full("arrests", NULL),
               "10 rows where the service reports 500")
  expect_false(file.exists(cache))
})

test_that("a complete export is cached and survives a later outage", {
  d <- local_chicago_cache()
  cache <- file.path(d, "arrests_full.parquet")
  point_at(good_csv(500), count = 500)
  df <- rmoriedata:::.rmd_fetch_full("arrests", NULL)
  expect_equal(nrow(df), 500L)
  expect_true(file.exists(cache))
  expect_length(list.files(d, pattern = "^write-"), 0L)
  point_at(csv_file("<html>down</html>"), count = 500)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 500L)
})

test_that("a damaged cache is discarded and refetched; refresh forces a refetch", {
  d <- local_chicago_cache()
  cache <- file.path(d, "arrests_full.parquet")
  writeLines("not parquet", cache)
  point_at(good_csv(500), count = 500)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 500L)
  expect_equal(nrow(morie_read_parquet(cache)), 500L)
  point_at(good_csv(600), count = 600)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 500L)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL,
                                                 refresh = TRUE)), 600L)
  expect_equal(nrow(load_chicago_data("arrests", full = TRUE,
                                      refresh = TRUE)), 600L)
})

test_that("a bounded fetch still refuses an HTML page but ignores the count", {
  local_chicago_cache()
  point_at(csv_file("<html>down</html>"), count = 500)
  expect_error(rmoriedata:::.rmd_fetch_full("arrests", NULL, limit = 5),
               "single column")
  point_at(good_csv(10), count = 500)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL, limit = 10)),
               10L)
})

test_that("the cache write is atomic: no partial file is ever left in place", {
  d <- tempfile("atomic")
  dir.create(d)
  path <- file.path(d, "x.parquet")
  rmoriedata:::.rmd_cache_write(data.frame(a = 1:3), path)
  expect_identical(list.files(d), "x.parquet")
  expect_equal(morie_read_parquet(path)$a, 1:3)
})

test_that(".rmd_check_download rejects outage pages, empty bodies and the wrong format", {
  f <- tempfile(fileext = ".xlsx")
  writeLines("<html><body>Service Unavailable</body></html>", f)
  expect_error(rmoriedata:::.rmd_check_download(f, "xlsx"), "not a xlsx file")
  expect_false(file.exists(f))
  file.create(f)
  expect_error(rmoriedata:::.rmd_check_download(f, "xlsx"), "empty")
  writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, 0x00)), f)
  expect_true(rmoriedata:::.rmd_check_download(f, "xlsx"))
  expect_true(rmoriedata:::.rmd_check_download(f, "zip"))
  expect_error(rmoriedata:::.rmd_check_download(f, "xls"), "not a xls file")
  writeLines("id,n\n1,2", f)
  expect_true(rmoriedata:::.rmd_check_download(f, "csv"))
})

test_that("fetch_cihi_table validates its arguments before any network call", {
  n <- nrow(load_cihi_data_tables())
  expect_error(fetch_cihi_table(0), "between 1 and")
  expect_error(fetch_cihi_table(-1), "between 1 and")
  expect_error(fetch_cihi_table(n + 1), "between 1 and")
  expect_error(fetch_cihi_table(1.7), "whole number")
  expect_error(fetch_cihi_table(NA_integer_), "between 1 and")
  expect_error(fetch_cihi_table(c(1, 2)), "between 1 and")
  expect_error(fetch_cihi_table(""), "which")
  expect_error(fetch_cihi_table(NA_character_), "which")
  expect_error(fetch_cihi_table(1, timeout = -1), "timeout")
  expect_error(fetch_cihi_table(1, timeout = NA), "timeout")
  expect_error(fetch_cihi_table(1, timeout = "60"), "timeout")
  expect_error(fetch_cihi_table(1, timeout = c(1, 2)), "timeout")
})
