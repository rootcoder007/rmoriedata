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

test_that("without the service's count the data is returned but not cached", {
  d <- local_chicago_cache()
  point_at(good_csv(10), count = NA_real_)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 10L)
  expect_false(file.exists(file.path(d, "arrests_full.parquet")))
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

test_that("a write that dies midway leaves the previous cache intact", {
  d <- local_chicago_cache()
  cache <- file.path(d, "arrests_full.parquet")
  point_at(good_csv(500), count = 500)
  rmoriedata:::.rmd_fetch_full("arrests", NULL)
  testthat::local_mocked_bindings(
    morie_write_parquet = function(df, path, ...) {
      writeLines("PAR1 half", path)
      stop("disk full")
    },
    .package = "rmoriedata"
  )
  point_at(good_csv(600), count = 600)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL,
                                                 refresh = TRUE)), 600L)
  expect_equal(nrow(morie_read_parquet(cache)), 500L)
  expect_setequal(list.files(d), c("arrests_full.parquet", "arrests_full.parquet.sha256"))
})

test_that("the cache write is atomic: no partial file is ever left in place", {
  d <- tempfile("atomic")
  dir.create(d)
  path <- file.path(d, "x.parquet")
  rmoriedata:::.rmd_cache_write(data.frame(a = 1:3), path)
  expect_setequal(list.files(d), c("x.parquet", "x.parquet.sha256"))
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
  writeLines(c("id,n", "1,2"), f)
  expect_true(rmoriedata:::.rmd_check_download(f, "csv"))
  writeLines("id,n", f)
  expect_error(rmoriedata:::.rmd_check_download(f, "csv"), "not a csv file")
})

test_that("fetch_cihi_table refuses an outage page and falls back to Wayback", {
  fake_cat <- data.frame(
    title = "Stub table", url = "https://live.example/t.xlsx",
    format = "xlsx", wayback_url = "https://web.archive.org/t.xlsx",
    stringsAsFactors = FALSE
  )
  fetched <- character()
  testthat::local_mocked_bindings(
    load_cihi_data_tables = function(...) fake_cat,
    .rmd_fetch_file = function(url, dest, wayback, timeout) {
      fetched <<- c(fetched, url)
      if (grepl("archive", url)) {
        writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, 0x00)), dest)
      } else {
        writeLines("<html><body>Service Unavailable</body></html>", dest)
      }
      invisible(dest)
    },
    .package = "rmoriedata"
  )
  out <- tempfile(fileext = ".xlsx")
  expect_identical(fetch_cihi_table(1, dest = out), out)
  expect_identical(fetched, c(fake_cat$url, fake_cat$wayback_url))
  expect_identical(readBin(out, "raw", 2L), as.raw(c(0x50, 0x4b)))
  # no archived copy: the outage page is refused and removed
  fake_cat$wayback_url <- ""
  out2 <- tempfile(fileext = ".xlsx")
  expect_error(fetch_cihi_table(1, dest = out2), "not a xlsx file")
  expect_false(file.exists(out2))
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
  expect_error(fetch_cihi_table(1, timeout = Inf), "timeout")
})

test_that("a live fetch returns UTF-8-marked strings, like the cache does", {
  local_chicago_cache()
  f <- tempfile(fileext = ".csv")
  writeBin(c(charToRaw("id,name\n1,"), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)),
             charToRaw("\n")), f)
  point_at(paste0("file://", f), count = 1)
  d <- rmoriedata:::.rmd_fetch_full("arrests", NULL)
  expect_identical(Encoding(d$name), "UTF-8")
  expect_identical(charToRaw(d$name), as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  expect_identical(nchar(d$name), 4L)
})

test_that("a cache whose bytes changed is not served: the sidecar catches it", {
  d <- local_chicago_cache()
  cache <- file.path(d, "arrests_full.parquet")
  point_at(good_csv(500), count = 500)
  rmoriedata:::.rmd_fetch_full("arrests", NULL)
  expect_true(file.exists(paste0(cache, ".sha256")))
  raw <- readBin(cache, "raw", file.size(cache))
  raw[length(raw) %/% 2] <- xor(raw[length(raw) %/% 2], as.raw(0xff))
  writeBin(raw, cache)
  point_at(good_csv(600), count = 600)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 600L)
  expect_equal(nrow(morie_read_parquet(cache)), 600L)
  unlink(paste0(cache, ".sha256"))
  point_at(good_csv(700), count = 700)
  expect_equal(nrow(rmoriedata:::.rmd_fetch_full("arrests", NULL)), 700L)
})

test_that("load_cihi_data_tables rejects anything but TRUE or FALSE", {
  for (bad in list(1, "yes", NA, c(TRUE, FALSE), NULL)) {
    expect_error(load_cihi_data_tables(archived_only = bad), "TRUE or FALSE")
  }
  expect_lt(nrow(load_cihi_data_tables(archived_only = TRUE)),
            nrow(load_cihi_data_tables()))
})
