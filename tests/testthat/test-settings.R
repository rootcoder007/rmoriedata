# SPDX-License-Identifier: AGPL-3.0-or-later
# Results that do not follow the session's settings: options(scipen, OutDec, digits,
# warn, warnPartialMatch*, check.bounds, encoding, useFancyQuotes, width, max.print),
# the time zone, the locale and the language of base R's messages. Each block is
# run under the defaults and under every setting of helper-settings.R, and must
# give the identical result.

test_that("case is folded in ASCII alone, the same in every locale", {
  # Turkish lowers "I" to the dotless "\u0131" and uppers "i" to "\u0130": emulated here
  # whatever locales the system has
  x <- c("I", "i", "\u0130", "\u0131", "INJURY", "PUBLIC", "UUID", "\u00c9t\u00c9")
  want <- c("i", "i", "\u0130", "\u0131", "injury", "public", "uuid", "\u00c9t\u00c9")
  under_settings(function() .rmd_lower(x))
  expect_identical(.rmd_lower(x), want)
  expect_true(.rmd_open_marks(list(access = "PUBLIC")))
  expect_true(.rmd_open_marks(list(access = "Open")))
  expect_false(.rmd_open_marks(list(access = "\u0130OPEN")))
  under_settings(function() .rmd_open_marks(list(access = "PUBLIC", restricted = FALSE)))
})

test_that("cihiget() matches a title in any case, in every locale", {
  testthat::local_mocked_bindings(
    .rmd_fetch_file = function(url, dest, wayback, timeout) {
      writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, 0, 0)), dest)
      invisible(dest)
    })
  got <- under_settings(function() {
    d <- withr::local_tempfile(fileext = ".xlsx")
    title <- "INJURY AND TRAUMA EMERGENCY DEPARTMENT AND HOSPITALIZATION STATISTICS, 2024"
    list(cihiget(title, dest = d) == d,
         sum(grepl("\u2013", cihitbls()$title, fixed = TRUE)))
  }, "cihiget")
  expect_true(got[[1L]])
  # (the titles in the message are base R's to write: <U+2013> in a C locale)
  expect_error(cihiget("Injury"), "'Injury' matches 9 tables", fixed = TRUE)
})

test_that("numbers are written as text the same under any options", {
  x <- c(3, 1e5, 123456, 1e-5, 0.1 + 0.2, 41.87654321098765, 2^53 + 2, -0, NA, NaN,
         Inf, -Inf, 1e15, 1234567890123456)
  got <- under_settings(function() .rmd_ntxt(x))
  expect_identical(got[1:4], c("3", "100000", "123456", "1e-05"))
  expect_identical(.rmd_num(got[!is.na(x) & is.finite(x)]), x[!is.na(x) & is.finite(x)])
  expect_identical(got[9:10], c(NA, "NaN"))
  under_settings(function() .rmd_rtxt(c(1e-5, 1e5, 0.25)))
  expect_identical(.rmd_rtxt(c(1e-5, 1e5, 0.25)), c("1e-05", "1e+05", "0.25"))
  under_settings(function() .rmd_count_txt(c(0L, 12L, 1234L, 1234567L, NA)))
  expect_identical(.rmd_count_txt(c(12L, 1234567L)), c("12", "1,234,567"))
})

test_that("a Parquet file of every type reads and writes the same under any settings", {
  t <- c(0, 1.5, -1e-6, 1709642096.123456, 9223372036854.775390625,
         -9223372036854.775390625, NA)
  d <- data.frame(
    int = c(1L, -2147483647L, 0L, NA, 2147483647L, 7L, 8L),
    dbl = c(0.1 + 0.2, 1e-5, 1e5, 2^53 + 2, -0, NaN, NA),
    lgl = c(TRUE, FALSE, NA, TRUE, TRUE, FALSE, NA),
    chr = c("", "\u0130\u0131", "caf\u00e9", NA, "a,b", "1e+05", "I"),
    day = as.Date(c(-1, 0, 19000.5, NA, 2932896, -719162, 1)),
    tim = .POSIXct(t, tz = "America/Chicago"),
    fct = factor(c("b", "a", NA, "b", "a", "a", "b")),
    stringsAsFactors = FALSE)
  names(d)[7L] <- ""
  got <- under_settings(function() {
    f <- withr::local_tempfile(fileext = ".parquet")
    morie_write_parquet(d, f)
    bytes <- readBin(f, "raw", file.size(f))
    list(bytes = bytes, read = morie_read_parquet(f), raw = morie_read_parquet(bytes),
         some = morie_read_parquet(f, columns = c("tim", "")))
  }, "parquet round trip")
  expect_identical(got$read$tim, .POSIXct(t, tz = "UTC"))
  expect_identical(got$read$int, d$int)
  expect_identical(got$read[[7L]], as.character(d[[7L]]))
  expect_identical(got$raw, got$read)
})

test_that("each store format loads the same under any settings", {
  cat0 <- mdcat()
  tb <- cat0[cat0$kind == "table", ]
  slugs <- c("arsau_2023_uof_main_records", tb$slug[which.max(tb$n_cols)])
  dict <- cat0$slug[cat0$kind == "dictionary"][1L]
  under_settings(function() {
    list(cat = mdcat(),
         csv = lapply(slugs, mdload, refresh = TRUE, format = "csv"),
         pq = lapply(slugs, mdload, refresh = TRUE, format = "parquet"),
         dict = mddict(dict), cihi = cihitbls(), siu = siuload(),
         ok = mdverify()$ok, path = basename(mdpath(slugs[[1L]])))
  }, "store")
})

test_that("a hosted table is read from its cache the same under any settings", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  served <- withr::local_tempfile(fileext = ".csv.gz")
  con <- gzfile(served, "w")
  writeLines(c("code,rate,big,small,flag,when,text",
               "046,0.25,3000000000,1e-05,TRUE,2024-01-01,caf\u00e9",
               "120,1.50,2,2.5e-10,FALSE,2024-01-02,\"a, b\"",
               "871,-3,4,1e-05,,2024-01-03,\u0130"), con)
  close(con)
  dig <- .rmd_digest(served)
  manifest <- paste0('{"datasets":[{"key":"justice_open/t","rows":3,',
                     '"access":"PUBLIC","sha256_gz":"', dig, '"}]}')
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      if (path == "/manifest.json") writeLines(manifest, dest)
      else file.copy(served, dest, overwrite = TRUE)
      invisible(dest)
    })
  got <- under_settings(function() {
    withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
    list(cat = hostcat(), t = hostload("justice_open/t"),
         again = hostload("justice_open/t"),
         bad = tryCatch(hostload("justice_open/./t"), error = conditionMessage))
  }, "hosted")
  expect_identical(got$t$small, c(1e-05, 2.5e-10, 1e-05))
  expect_identical(got$t$code, c("046", "120", "871"))
  expect_identical(got$t$big, c(3e9, 2, 4))
})

test_that("the privacy functions give the same results under any settings", {
  # the OS random source replaced by a seeded stream, so a run can be repeated
  testthat::local_mocked_bindings(.rmd_bl_get = function(name) {
    if (name != "rndbytes") return(getExportedValue("rmoriebricklayer", name))
    function(n) as.raw(sample.int(256L, n, replace = TRUE) - 1L)
  })
  d <- data.frame(age = c(30, 30, 40, 40, NA, 30), sex = c("M", "M", "F", "F", "F", "M"),
                  dx = c("a", "b", "a", "a", NA, "a"), stringsAsFactors = FALSE)
  d$z <- c(1, 1, 2, 2, 2, 1)
  names(d)[4L] <- ""
  tbl <- matrix(c(1, 9, 20, 3, 15, 40, 12, 2, 30), 3)
  under_settings(function() {
    withr::local_seed(42)
    .morie_dp_rng$buf <- NULL
    b <- dpbudget(2, 1e-5)
    out <- list(cnt = dplapcnt(100, 0.5, b),
                hist = dplaphist(c(a = 3, b = 0, c = 10), 0.5, b),
                mean = dpgmean(c(1, 5, 9, 10), 0, 10, 0.5, 1e-6, b),
                spent = dpspent(b)[c("spent_epsilon", "releases")],
                printed = utils::capture.output(print(b)),
                k = unclass(kanonvrf(d, c("age", "sex", ""), k = 2)),
                l = unclass(ldivvrf(d, c("", "sex"), "dx", l = 2)),
                cell = unclass(cellsupp(tbl, threshold = 5)))
    .morie_dp_rng$buf <- NULL
    out
  }, "privacy")
})

test_that("mdask() sends the same catalogue under any settings", {
  skip_if_old_bricklayer()
  testthat::local_mocked_bindings(
    llmask = function(prompt, model = NULL, tmout = 120, syspro = NULL, route = NULL,
                      docs = TRUE, pkgs = NULL) {
      syspro
    },
    .package = "rmoriebricklayer")
  got <- under_settings(function() mdask("which tables?", route = "auto"), "mdask")
  expect_match(got, "arsau_2023_uof_main_records: table, [0-9,]+", perl = TRUE)
})

test_that("the Parquet reader and writer ignore options(check.bounds = TRUE)", {
  # base R's own code warns under it (a data frame given a column); the reader made
  # every such warning "the file is damaged"
  d <- data.frame(a = 1:3, b = c("x", "y", NA), t = .POSIXct(c(0, 1.5, NA), tz = "UTC"))
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(d, f)
  ref <- list(readBin(f, "raw", file.size(f)), morie_read_parquet(f))
  got <- local({
    op <- options(check.bounds = TRUE)
    on.exit(options(op))
    # base R's own warnings under it are let be; the reader must not fail on them
    suppressWarnings({
      morie_write_parquet(d, f)
      list(list(readBin(f, "raw", file.size(f)), morie_read_parquet(f)),
           mdload("arsau_2023_uof_main_records", TRUE, "parquet"))
    })
  })
  expect_identical(got[[1L]], ref)
  expect_identical(got[[2L]], mdload("arsau_2023_uof_main_records", TRUE, "parquet"))
})
