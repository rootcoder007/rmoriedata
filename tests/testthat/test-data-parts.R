# Large curated tables come down in byte-range parts: kept once whole, resumed
# from the first missing part, joined in order. No network: the transport is a
# stub that serves the range asked for from memory.

test_that("a large table comes in parts, resumed and joined in order", {
  st <- new.env()
  set.seed(1)
  bytes <- as.raw(sample(0:255, 5000, replace = TRUE))
  st$seen <- character()
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, headers = NULL, ...) {
      r <- as.numeric(strsplit(sub("^bytes=", "", headers[["Range"]]), "-")[[1]])
      st$seen <- c(st$seen, headers[["Range"]])
      writeBin(bytes[(r[1] + 1):(r[2] + 1)], dest)
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(readBin(dest, "raw", 6000), bytes)
  expect_length(st$seen, 5L)
  expect_false(dir.exists(paste0(dest, ".parts")))
  unlink(dest)
  pd <- paste0(dest, ".parts")
  dir.create(pd)
  writeBin(bytes[1:1024], file.path(pd, "00001"))
  writeBin(bytes[1025:1100], file.path(pd, "00002"))
  st$seen <- character()
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(readBin(dest, "raw", 6000), bytes)
  expect_identical(st$seen, c("bytes=1024-2047", "bytes=2048-3071", "bytes=3072-4095",
                           "bytes=4096-4999"))
})

test_that("a short or failed part is refused and can be resumed", {
  fail <- NULL
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, ...) {
      if (!is.null(fail)) stop(fail, call. = FALSE)
      writeBin(as.raw(1:10), dest)
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  expect_error(.rmd_get_parts("/db/t.csv.gz", dest, character(), "db/t", 5000, 1024, 60),
               "part 1 of db/t came back with 10 bytes, not 1024; run again to resume")
  expect_false(file.exists(file.path(paste0(dest, ".parts"), "00001")))
  fail <- "bldl: https://data.example.test/x answered HTTP 410"
  expect_error(.rmd_get_parts("/icpsr_9/t.csv.gz", dest, character(), "icpsr_9/t",
                              5000, 1024, 60),
               "icpsr_9/t is not served by data.rmorie.com")
})

test_that("only a table more than twice the part size goes in parts", {
  st <- new.env()
  withr::local_options(rmoriedata.dpart = 10)
  expect_error(.rmd_part_bytes(), "at least 1 MB")
  withr::local_options(rmoriedata.dpart = NULL)
  expect_identical(.rmd_part_bytes(), 90 * 2^20)
  st$called <- NULL
  testthat::local_mocked_bindings(
    .rmd_hosted_key = function() NULL,
    .rmd_hosted_size = function(path) 300 * 2^20,
    .rmd_get_parts = function(path, dest, hdr, label, size, part, timeout) {
      st$called <- c(size, part)
      invisible(dest)
    }
  )
  .rmd_data_get("/db/t.csv.gz", withr::local_tempfile())
  expect_identical(st$called, c(300 * 2^20, 90 * 2^20))
})
