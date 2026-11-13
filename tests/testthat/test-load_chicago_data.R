# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("chiload returns correct type per `as`", {
  expect_s3_class(
    chiload("complaints", as = "data.frame"),
    "data.frame"
  )

  skip_if_not_installed("tibble")
  expect_s3_class(chiload("arrests", as = "tibble"), "tbl_df")
})

test_that("parquet_path writes a file the native codec reads back", {
  p <- chiload("complaints", as = "parquet_path")
  expect_true(file.exists(p))
  expect_true(startsWith(normalizePath(p), normalizePath(tempdir())))
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
  p <- chiload("complaints", as = "parquet_path")

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
  df <- data.frame(
    case_number = c("a", "b", "c"),
    stringsAsFactors = FALSE
  )
  q <- tempfile(fileext = ".parquet")
  on.exit(unlink(q), add = TRUE)
  df$case_number[2] <- "CANARY"
  morie_write_parquet(df, q)
  expect_identical(
    as.data.frame(nanoparquet::read_parquet(q))$case_number[2], "CANARY"
  )
})

test_that("type + as are validated", {
  expect_error(chiload("bogus"), "should be one of")
  expect_error(chiload("arrests", as = "xml"), "should be one of")
})

test_that("full=TRUE fetches live Chicago data (opt-in only)", {
  # Heavy live Socrata fetch — never run in CI/CRAN. Opt in explicitly with
  # RMORIEDATA_TEST_LIVE=true when you actually want to hit the network.
  skip_on_cran()
  if (!identical(tolower(Sys.getenv("RMORIEDATA_TEST_LIVE")), "true")) {
    skip("live network test (set RMORIEDATA_TEST_LIVE=true to run)")
  }
  df <- chiload("complaints", full = TRUE)
  expect_s3_class(df, "data.frame")
  expect_gt(nrow(df), 0L)
})

test_that("limit and fraction are mutually exclusive and validated", {
  expect_error(chiload("arrests",
    full = TRUE, limit = 5,
    fraction = 0.5
  ), "not both")
  expect_error(chiload("arrests", full = TRUE, limit = 0))
  expect_error(chiload("arrests", full = TRUE, limit = "x"))
  expect_error(chiload("arrests", full = TRUE, fraction = 0))
  expect_error(chiload("arrests", full = TRUE, fraction = 1.5))
  expect_error(chiload("arrests", full = TRUE, fraction = -0.1))
})

test_that("fraction resolves to a row cap from the live total (mocked)", {
  seen_limit <- NULL
  testthat::local_mocked_bindings(
    .rmd_full_count = function(type) 1000,
    .rmd_fetch_full = function(type, mirror, limit = NULL, ...) {
      seen_limit <<- limit
      data.frame(case_number = as.character(seq_len(limit)))
    },
    .package = "rmoriedata"
  )
  df <- chiload("complaints", full = TRUE, fraction = 0.05)
  expect_identical(seen_limit, 50L) # 5 percent of 1000 rows, rounded up
  expect_equal(nrow(df), 50L)
})

test_that("limit is passed through verbatim (mocked)", {
  seen_limit <- NULL
  testthat::local_mocked_bindings(
    .rmd_fetch_full = function(type, mirror, limit = NULL, ...) {
      seen_limit <<- limit
      data.frame(case_number = "x")
    },
    .package = "rmoriedata"
  )
  chiload("arrests", full = TRUE, limit = 123)
  expect_equal(seen_limit, 123)
})

test_that("a bounded fetch never reads or writes the full-dataset cache", {
  cache_dir <- local_chicago_cache()
  cache <- file.path(cache_dir, "arrests_full.parquet")
  # Plant a poisoned cache; a bounded fetch must ignore it and, on its own
  # network failure, error rather than silently serving the cache.
  had <- file.exists(cache)
  if (!had) {
    morie_write_parquet(data.frame(
      case_number = "cached",
      stringsAsFactors = FALSE
    ), cache)
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
      as.character(morie_read_parquet(cache)$case_number), "cached"
    )
  }
})

test_that("the cache directory is tempdir() unless the user names one", {
  old <- options(rmoriedata.cache_dir = NULL)
  on.exit(options(old), add = TRUE)
  d <- rmoriedata:::.rmd_cache_dir()
  expect_true(startsWith(normalizePath(d), normalizePath(tempdir())))
  mine <- file.path(tempfile("opt"), "chicago")
  options(rmoriedata.cache_dir = mine)
  expect_identical(normalizePath(rmoriedata:::.rmd_cache_dir()),
                   normalizePath(mine))
  writeLines("x", file.path(mine, "arrests_full.parquet"))
  expect_identical(normalizePath(chiclr()), normalizePath(mine))
  expect_length(list.files(mine), 0L)
})

test_that("chiclr() removes only what chiload() wrote and leaves the rest", {
  mine <- withr::local_tempdir()
  withr::local_options(rmoriedata.cache_dir = mine)
  own <- file.path(mine, c("arrests_full.parquet", "arrests_full.parquet.sha256",
                           "crimes_full.parquet", "write-ab12.parquet"))
  keep <- file.path(mine, c("notes.txt", "my_full.parquet.bak", ".hidden"))
  dir.create(file.path(mine, "hosted", "fec"), recursive = TRUE)
  dir.create(file.path(mine, "odd_full.parquet"))
  for (f in c(own, keep, file.path(mine, "hosted", "fec", "t.csv.gz"))) writeLines("x", f)
  chiclr()
  expect_false(any(file.exists(own)))
  expect_true(all(file.exists(keep)))
  expect_true(file.exists(file.path(mine, "hosted", "fec", "t.csv.gz")))
  expect_true(dir.exists(file.path(mine, "odd_full.parquet")))
})

test_that("chiload's arguments are checked in its own words", {
  for (bad in list(Inf, 1e10, "10", NA, c(1, 2), 0, 2.5)) {
    expect_error(chiload("arrests", full = TRUE, limit = bad),
                 "`limit` must be a whole number of rows from 1 to 2147483647.",
                 fixed = TRUE)
  }
  for (bad in list(0, 1.5, -0.1, NA, "0.5", c(0.1, 0.2))) {
    expect_error(chiload("arrests", full = TRUE, fraction = bad),
                 "`fraction` must be one number above 0 and at most 1.", fixed = TRUE)
  }
  for (bad in list("yes", NA, 1, c(TRUE, FALSE), NULL)) {
    expect_error(chiload("arrests", full = bad), "`full` must be TRUE or FALSE.",
                 fixed = TRUE)
    expect_error(chiload("arrests", refresh = bad), "`refresh` must be TRUE or FALSE.",
                 fixed = TRUE)
  }
})

# Rows as Socrata's CSV export gives them, every field as text.
raw_complaints <- function() {
  data.frame(
    id = c("14380668", "14381189"), case_number = c("JK477973", "JK478752"),
    date = c("2026-07-05T13:30:00.000", "2026-01-05T00:00:00.000"),
    block = c("022XX W JACKSON BLVD", "092XX S HALSTED ST"), iucr = c("0560", "031A"),
    primary_type = c("ASSAULT", "ROBBERY"), description = c("SIMPLE", "ARMED: HANDGUN"),
    location_description = c("APARTMENT", "STREET"), arrest = c("false", "true"),
    domestic = c("true", "false"), beat = c("1225", "2223"), district = c("12", "22"),
    ward = c("27", ""), community_area = c("28", "73"), fbi_code = c("08A", "03"),
    x_coordinate = c("1161646", "1172599"), y_coordinate = c("1898661", "1843643"),
    year = c("2026", "2026"), updated_on = c("2026-11-12T15:45:23.000", ""),
    latitude = c("41.87760112", ""), longitude = c("-87.681941224", "-87.6"),
    location = c("(41.87, -87.68)", ""), stringsAsFactors = FALSE
  )
}

raw_arrests <- function() {
  data.frame(
    cb_no = c("30642834", "30642831"), case_number = c("", "JK483991"),
    arrest_date = c("2026-11-09T23:50:00.000", "2026-02-01T08:05:00.000"),
    race = c("WHITE", "BLACK"),
    charge_1_statute = c("625 ILCS 5.0/11-501-A-1", "720 ILCS"),
    charge_1_description = c("DUI", "POSS CAN"), charge_1_type = c("M", "F"),
    charge_1_class = c("A", "4"), charge_2_statute = c("x", ""),
    charges_type = c("M | M", "F |"), stringsAsFactors = FALSE
  )
}

test_that("a full fetch has the bundled sample's columns, order and types", {
  for (type in c("complaints", "arrests")) {
    raw <- if (type == "arrests") raw_arrests() else raw_complaints()
    testthat::local_mocked_bindings(.rmd_fetch_full = function(...) raw)
    got <- chiload(type, full = TRUE)
    s <- chiload(type)
    expect_identical(names(got), names(s))
    expect_identical(lapply(got, class), lapply(s, class))
    expect_identical(attr(got$date, "tzone"), attr(s$date, "tzone"))
    expect_identical(nrow(got), 2L)
  }
  testthat::local_mocked_bindings(.rmd_fetch_full = function(...) raw_complaints())
  got <- chiload("complaints", full = TRUE)
  expect_identical(got$iucr, c("0560", "031A"))
  expect_identical(got$date_iso,
                   c("2026-07-05T13:30:00-0500", "2026-01-05T00:00:00-0600"))
  expect_identical(format(got$date, "%Y-%m-%d %H:%M"),
                   c("2026-07-05 13:30", "2026-01-05 00:00"))
  expect_identical(got$arrest, c(FALSE, TRUE))
  expect_identical(got$ward, c(27L, NA))
  expect_identical(got$latitude, c(41.87760112, NA))
  testthat::local_mocked_bindings(.rmd_fetch_full = function(...) raw_arrests())
  a <- chiload("arrests", full = TRUE)
  expect_identical(a$case_number, c("", "JK483991"))
  expect_identical(a$charge_desc, c("DUI", "POSS CAN"))
  expect_identical(a$date_iso, c("2026-11-09T23:50:00-0600", "2026-02-01T08:05:00-0600"))
  # a frame already in the sample's shape (a mirror serving it) passes unchanged
  s <- chiload("arrests", limit = 3)
  testthat::local_mocked_bindings(.rmd_fetch_full = function(...) s)
  expect_identical(chiload("arrests", full = TRUE), s)
})

test_that("a mirror URL is downloaded, checked against its .sha256 and used", {
  local_chicago_cache()
  src <- withr::local_tempfile(fileext = ".parquet")
  served <- data.frame(id = as.character(1:5), x = letters[1:5], stringsAsFactors = FALSE)
  morie_write_parquet(served, src)
  sha <- .rmd_bl("sha256file")(src)
  st <- new.env()
  st$urls <- character()
  st$sha <- sha
  testthat::local_mocked_bindings(
    .rmd_dl = function(url, dest, ...) {
      st$urls <- c(st$urls, url)
      if (endsWith(url, ".sha256")) {
        if (is.null(st$sha)) stop("bldl: answered HTTP 404", call. = FALSE)
        writeLines(paste0(st$sha, "  arrests_full.parquet"), dest)
      } else {
        file.copy(src, dest, overwrite = TRUE)
      }
      invisible(dest)
    },
    .rmd_full_count_or_na = function(type) 5,
    .rmd_full_url = function(type, n) "file:///nonexistent/socrata.csv"
  )
  got <- .rmd_fetch_full("arrests", "https://mirror.example.test/cran/")
  expect_identical(got, served)
  u <- "https://mirror.example.test/cran/arrests_full.parquet"
  expect_identical(st$urls, c(u, paste0(u, ".sha256")))
  # no .sha256 beside it: used as it is
  st$sha <- NULL
  expect_identical(.rmd_fetch_full("arrests", "https://mirror.example.test/cran",
                                   refresh = TRUE), served)
  # a digest that does not match: the mirror is skipped and Socrata asked
  st$sha <- strrep("0", 64)
  testthat::local_mocked_bindings(.rmd_full_url = function(type, n) {
    f <- tempfile(fileext = ".csv")
    writeLines(c("id,x", "1,a", "2,b", "3,c", "4,d", "5,e"), f)
    paste0("file://", f)
  })
  got <- .rmd_fetch_full("arrests", "https://mirror.example.test/cran", refresh = TRUE)
  expect_identical(got$x, letters[1:5])
  # and a failing mirror falls back the same way
  testthat::local_mocked_bindings(.rmd_dl = function(...) stop("bldl: answered HTTP 404"))
  expect_identical(nrow(.rmd_fetch_full("arrests", "https://mirror.example.test/cran",
                                        refresh = TRUE)), 5L)
})

test_that("a cache directory that cannot be written is named, not blamed on the server", {
  f <- withr::local_tempfile()
  writeLines("x", f)
  withr::local_options(rmoriedata.cache_dir = f)
  msg <- paste0("rmoriedata: cannot write to the cache directory ", f)
  expect_error(.rmd_cache_dir(), msg, fixed = TRUE)
  expect_error(hostcat(), "cannot write to the cache directory", fixed = TRUE)
  skip_on_os("windows")
  d <- withr::local_tempdir()
  Sys.chmod(d, "0555")
  withr::defer(Sys.chmod(d, "0755"))
  skip_if(file.access(d, 2L) == 0L, "running as a user who can write anywhere")
  withr::local_options(rmoriedata.cache_dir = d)
  expect_error(hostload("db/t"), paste0("cannot write to the cache directory ", d, ";"),
               fixed = TRUE)
})
