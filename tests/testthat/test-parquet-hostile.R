# SPDX-License-Identifier: AGPL-3.0-or-later
# The native Parquet reader on files it did not write: every malformed file is either read
# back exactly or refused with an error. Never a silently different data frame, never a
# hang, never an allocation the bytes cannot justify.

pq_mutants_ok <- function(path, truth, n = 300L) {
  bytes <- readBin(path, "raw", file.size(path))
  bad <- character()
  for (i in seq_len(n)) {
    m <- bytes
    kind <- i %% 3L
    if (kind == 0L) {
      m <- m[seq_len(sample.int(length(m) - 1L, 1L))]
    } else {
      j <- sample.int(length(m), 1L)
      m[j] <- if (kind == 1L) xor(m[j], as.raw(bitwShiftL(1L, sample.int(8L, 1L) - 1L)))
              else as.raw(sample.int(256L, 1L) - 1L)
    }
    f <- tempfile(fileext = ".parquet")
    writeBin(m, f)
    got <- suppressWarnings(tryCatch(morie_read_parquet(f), error = function(e) NULL))
    unlink(f)
    # values must come back exactly: pages carry a CRC, and every structural field is
    # bounds- and count-checked. Column names live in the footer, which Parquet does not
    # checksum, so a flipped name character cannot be detected by any reader.
    if (!is.null(got) && !identical(unname(got), unname(truth))) {
      bad <- c(bad, sprintf("mutant %d (kind %d)", i, kind))
    }
  }
  bad
}

test_that("a 21-byte file claiming a huge map is refused at once, not looped on", {
  f <- tempfile(fileext = ".parquet")
  body <- as.raw(c(0x1b, 0x80, 0x80, 0x80, 0x80, 0x80, 0x02, 0x88, 0x00))
  footer_len <- writeBin(length(body), raw(), size = 4L, endian = "little")
  writeBin(c(charToRaw("PAR1"), body, footer_len, charToRaw("PAR1")), f)
  t0 <- proc.time()[["elapsed"]]
  expect_error(morie_read_parquet(f), "parquet")
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
})

test_that("mutated files are refused or read back exactly, for every codec", {
  set.seed(42)
  df <- data.frame(
    id = 1:40, x = seq(0.5, 20, by = 0.5),
    s = rep(c("alpha", "beta", "gamma", "delta", "epsilon"), 8),
    stringsAsFactors = FALSE
  )
  df$s[c(3, 17)] <- NA
  for (codec in list("gzip", "snappy", NULL)) {
    f <- tempfile(fileext = ".parquet")
    morie_write_parquet(df, f, compression = codec)
    truth <- morie_read_parquet(f)
    expect_equal(truth$id, df$id)
    expect_identical(pq_mutants_ok(f, truth, n = 200L), character(), info = format(codec))
    unlink(f)
  }
})

test_that("a footer row count above the cap is refused before allocation", {
  f <- tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = 1:3), f)
  old <- options(rmoriedata.parquet_max_rows = 2)
  on.exit(options(old))
  expect_error(morie_read_parquet(f), "cap")
})

test_that("deeply nested thrift lists and maps are refused, not a stack overflow", {
  f <- withr::local_tempfile(fileext = ".parquet")
  # 5000 list headers, each a one-element list of lists (0x19)
  writeBin(c(charToRaw("PAR1"), as.raw(rep(0x19, 5000)), as.raw(c(0x88, 0x13, 0, 0)),
             charToRaw("PAR1")), f)
  expect_error(morie_read_parquet(f), "parquet: metadata nested deeper than 64 levels",
               fixed = TRUE)
  e <- .pq_reader(c(as.raw(rep(c(0x01, 0xbb), 100)), raw(4)))
  expect_error(.pq_map(e), "parquet: metadata nested deeper than 64 levels", fixed = TRUE)
})

test_that("a stray base-R error while parsing is reported as a damaged file", {
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = 1:3), f)
  testthat::local_mocked_bindings(.pq_read_footer = function(con, size) {
    stop("subscript out of bounds")
  })
  expect_error(morie_read_parquet(f),
               "parquet: the file is damaged (subscript out of bounds)", fixed = TRUE)
  testthat::local_mocked_bindings(.pq_read_footer = function(con, size) {
    stop("parquet: footer length 9 does not fit", call. = FALSE)
  })
  expect_error(morie_read_parquet(f), "^parquet: footer length 9 does not fit$")
})

test_that("a mutation fuzzer: every refusal starts with parquet:, nothing else escapes", {
  skip_on_cran()
  withr::local_options(rmoriedata.parquet_max_rows = 1e5,
                       rmoriedata.parquet_max_page_bytes = 2^20)
  df <- data.frame(i = c(1L, NA, 3L, 2147483647L, -5L), x = c(0.5, NaN, NA, -1e300, 2),
                   s = c("a", NA, "\u00e9t\u00e9", "", "zz"),
                   b = c(TRUE, NA, FALSE, TRUE, TRUE),
                   d = as.Date("2020-01-01") + 0:4, stringsAsFactors = FALSE)
  bad <- character()
  n <- 0L
  for (codec in list("snappy", NULL, "gzip")) {
    f <- tempfile(fileext = ".parquet")
    morie_write_parquet(df, f, compression = codec)
    bytes <- readBin(f, "raw", file.size(f))
    set.seed(2026)
    for (i in seq_len(700L)) {
      m <- bytes
      k <- i %% 4L
      if (k == 0L) {
        m <- m[seq_len(sample.int(length(m) - 1L, 1L))]
      } else {
        j <- sample.int(length(m), sample(1:3, 1L))
        m[j] <- if (k == 1L) xor(m[j], as.raw(bitwShiftL(1L, sample.int(8L, 1L) - 1L)))
                else if (k == 2L) as.raw(sample.int(256L, length(j), TRUE) - 1L)
                else as.raw(c(0xff, 0x7f, 0x80, 0x00)[sample.int(4L, length(j), TRUE)])
      }
      g <- tempfile(fileext = ".parquet")
      writeBin(m, g)
      n <- n + 1L
      res <- tryCatch(
        withCallingHandlers(
          {
            morie_read_parquet(g)
            "ok"
          },
          warning = function(w) {
            bad <<- c(bad, paste("warning:", conditionMessage(w)))
            invokeRestart("muffleWarning")
          },
          message = function(c) {
            bad <<- c(bad, paste("message:", conditionMessage(c)))
            invokeRestart("muffleMessage")
          }),
        error = function(e) conditionMessage(e))
      if (!identical(res, "ok") && !startsWith(res, "parquet: ")) {
        bad <- c(bad, paste("error:", res))
      }
      unlink(g)
    }
    unlink(f)
  }
  expect_gte(n, 2000L)
  expect_identical(unique(bad), character())
})

test_that("NaN survives, and frames Parquet cannot hold are refused in words", {
  f <- withr::local_tempfile(fileext = ".parquet")
  for (codec in list("gzip", "snappy", NULL)) {
    morie_write_parquet(data.frame(x = c(1, NaN, NA, -0)), f, compression = codec)
    x <- morie_read_parquet(f)$x
    expect_identical(is.nan(x), c(FALSE, TRUE, FALSE, FALSE))
    expect_identical(is.na(x), c(FALSE, TRUE, TRUE, FALSE))
  }
  unlink(f)
  expect_error(morie_write_parquet(data.frame(a = 1:3)[, 0], f),
               "a data frame with no columns cannot be written", fixed = TRUE)
  expect_false(file.exists(f))
  l <- data.frame(a = 1:2)
  l$v <- list(1, "b")
  expect_error(morie_write_parquet(l, f), "column .v. is of type list")
  expect_error(morie_write_parquet(data.frame(z = complex(real = 1:2)), f),
               "column .z. is of type complex")
  expect_error(morie_write_parquet(data.frame(r = as.raw(1:2)), f),
               "column .r. is of type raw")
  expect_error(morie_write_parquet(data.frame(t = as.difftime(1:2, units = "mins")), f),
               "column .t. is of type difftime")
  m <- data.frame(id = 1:2)
  m$m <- matrix(1:4, 2)
  expect_error(morie_write_parquet(m, f), "column .m. is a matrix or array column")
  m <- data.frame(id = 1:2)
  m$d <- data.frame(u = 1:2, v = 3:4)
  expect_error(morie_write_parquet(m, f), "column .d. is a data frame column")
  i64 <- data.frame(b = structure(c(1, 2), class = "integer64"))
  expect_error(morie_write_parquet(i64, f), "column .b. is of type integer64")
  inf <- data.frame(d = structure(c(1, Inf), class = "Date"))
  expect_error(morie_write_parquet(inf, f), "column .d. has a Date outside the range")
  expect_error(morie_write_parquet(data.frame(t = .POSIXct(c(0, -Inf), tz = "UTC")), f),
               "column .t. has a time that is infinite")
  expect_false(file.exists(f))
  expect_error(morie_read_parquet(file.path(tempdir(), "no-such.parquet")),
               "^parquet: no such file: ")
  writeBin(charToRaw("hello"), f)
  expect_error(morie_read_parquet(f), "^parquet: not a parquet file: ")
})

test_that("Dates and times before 1970 or with fractions keep the day and second", {
  f <- withr::local_tempfile(fileext = ".parquet")
  d <- structure(c(-0.5, -1, -1.5, 0.5, 19000.75, -719528.25), class = "Date")
  morie_write_parquet(data.frame(d = d), f)
  expect_identical(format(morie_read_parquet(f)$d), format(d))
  expect_identical(as.numeric(morie_read_parquet(f)$d), floor(unclass(d)))
  tt <- .POSIXct(c(-0.0004, -0.5, -1.25, 0.9996, 1.0005, -86400.0001, 1e9 + 0.123),
                 tz = "UTC")
  morie_write_parquet(data.frame(t = tt), f)
  back <- morie_read_parquet(f)$t
  expect_identical(format(back, "%Y-%m-%d %H:%M:%S"), format(tt, "%Y-%m-%d %H:%M:%S"))
  expect_identical(as.numeric(back) * 1000, floor(as.numeric(tt) * 1000))
})

# A page header: type, sizes, and for a data page its value count and
# encoding, for a dictionary page its value count.
pq_hdr <- function(type, usize, csize, n = 1L, enc = .pqEPlain) {
  ph <- .pq_writer()
  l <- .pq_wi32(ph, 1L, type, 0L)
  l <- .pq_wi32(ph, 2L, usize, l)
  l <- .pq_wi32(ph, 3L, csize, l)
  if (type == .pqPData) {
    dp <- .pq_writer()
    m <- .pq_wi32(dp, 1L, n, 0L)
    m <- .pq_wi32(dp, 2L, enc, m)
    m <- .pq_wi32(dp, 3L, .pqERle, m)
    m <- .pq_wi32(dp, 4L, .pqERle, m)
    l <- .pq_wstruct(ph, 5L, .pq_wstop(dp), l)
  } else if (type == .pqPDict) {
    dh <- .pq_writer()
    m <- .pq_wi32(dh, 1L, n, 0L)
    m <- .pq_wi32(dh, 2L, .pqEPlain, m)
    l <- .pq_wstruct(ph, 7L, .pq_wstop(dh), l)
  }
  .pq_wstop(ph)
}

# A snappy file of one optional INT32 column `x` holding 7: the pages in
# `before` (headers and their bytes), then the data page, whose header says it
# inflates to `usize` bytes (its true size when NULL).
pq_one_int <- function(before = raw(0), usize = NULL) {
  body <- c(.pq_encode_levels(1L, 1L), .pq_encode_plain(7L, .pqInt32, "x"))
  pay <- .pq_snappy_compress(body)
  blob <- c(before, pq_hdr(.pqPData, usize %||% length(body), length(pay)), pay)
  cmd <- .pq_writer()
  l <- .pq_wi32(cmd, 1L, .pqInt32, 0L)
  l <- .pq_wlisti32(cmd, 2L, c(.pqERle, .pqEPlain), l)
  l <- .pq_wlistbin(cmd, 3L, "x", l)
  l <- .pq_wi32(cmd, 4L, .pqCSnappy, l)
  l <- .pq_wi64(cmd, 5L, 1, l)
  l <- .pq_wi64(cmd, 6L, length(blob), l)
  l <- .pq_wi64(cmd, 7L, length(blob), l)
  l <- .pq_wi64(cmd, 9L, 4, l)
  cc <- .pq_writer()
  l <- .pq_wi64(cc, 2L, 4, 0L)
  l <- .pq_wstruct(cc, 3L, .pq_wstop(cmd), l)
  root <- .pq_writer()
  l <- .pq_wbytes(root, 4L, "schema", 0L)
  l <- .pq_wi32(root, 5L, 1L, l)
  se <- .pq_writer()
  l <- .pq_wi32(se, 1L, .pqInt32, 0L)
  l <- .pq_wi32(se, 3L, .pqOptional, l)
  l <- .pq_wbytes(se, 4L, "x", l)
  rg <- .pq_writer()
  l <- .pq_wliststruct(rg, 1L, list(.pq_wstop(cc)), 0L)
  l <- .pq_wi64(rg, 2L, length(blob), l)
  l <- .pq_wi64(rg, 3L, 1, l)
  fm <- .pq_writer()
  l <- .pq_wi32(fm, 1L, 1L, 0L)
  l <- .pq_wliststruct(fm, 2L, list(.pq_wstop(root), .pq_wstop(se)), l)
  l <- .pq_wi64(fm, 3L, 1, l)
  l <- .pq_wliststruct(fm, 4L, list(.pq_wstop(rg)), l)
  ft <- .pq_wstop(fm)
  f <- tempfile(fileext = ".parquet")
  writeBin(c(charToRaw("PAR1"), blob, ft,
             writeBin(length(ft), raw(), size = 4L, endian = "little"),
             charToRaw("PAR1")), f)
  f
}

test_that("a page the reader does not use is stepped over, never inflated", {
  expect_identical(morie_read_parquet(pq_one_int())$x, 7L)
  # index pages that say they inflate to 1 GiB, over bytes that are not snappy
  # at all: inflating them would fail (or cost the 1 GiB each); skipped, they
  # cost nothing and the column reads
  junk <- as.raw(rep(0xff, 16L))
  idx <- c(pq_hdr(.pqPIndex, 2^30, length(junk)), junk)
  f <- pq_one_int(before = rep(idx, 3L))
  expect_identical(morie_read_parquet(f)$x, 7L)
})

test_that("a page that says it inflates past what its values take is refused", {
  # one optional INT32: a 4-byte level length, at most 2 bytes per level and 1
  # of padding, and 4 bytes of value make 11 bytes at most
  expect_error(morie_read_parquet(pq_one_int(usize = 12)),
               paste0("^parquet: page of column x says it inflates to 12 ",
                      "bytes; its 1 values take at most 11$"))
  expect_error(morie_read_parquet(pq_one_int(usize = 2^30)), "take at most 11$")
  # a dictionary page of one INT32 holds exactly 4 bytes
  junk <- as.raw(rep(0xff, 16L))
  dict <- c(pq_hdr(.pqPDict, 2^20, length(junk), n = 1L), junk)
  expect_error(morie_read_parquet(pq_one_int(before = dict)), "take at most 4$")
  bad <- c(pq_hdr(.pqPDict, 4, length(junk), n = -1L), junk)
  expect_error(morie_read_parquet(pq_one_int(before = bad)),
               "^parquet: dictionary page of column x gives no valid value")
})

test_that("a column chunk with a second dictionary page is refused", {
  one <- .pq_snappy_compress(.pq_encode_plain(3L, .pqInt32, "x"))
  dict <- c(pq_hdr(.pqPDict, 4, length(one), n = 1L), one)
  expect_identical(morie_read_parquet(pq_one_int(before = dict))$x, 7L)
  expect_error(morie_read_parquet(pq_one_int(before = c(dict, dict))),
               "^parquet: column x has a second dictionary page")
})
