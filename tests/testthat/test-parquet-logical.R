# SPDX-License-Identifier: AGPL-3.0-or-later
# The Parquet reader on what other writers mark their columns as: a DECIMAL, an
# unsigned whole number or a time comes back as its value, or the column is
# refused by name. Never the unscaled or wrapped number without a word.

# A one-column file, built byte by byte: `ptype` the physical type, `page` the
# PLAIN body of its one data page, `n` the rows; `prec` the precision and `lt`
# the bytes of a LogicalType struct.
pq_lone <- function(ptype, page, n, conv = NULL, scale = NULL, typelen = NULL,
                    off = 4, usize = length(page), prec = NULL, lt = NULL) {
  ph <- .pq_writer()
  m <- .pq_wi32(ph, 1L, n, 0L)
  m <- .pq_wi32(ph, 2L, .pqEPlain, m)
  m <- .pq_wi32(ph, 3L, .pqERle, m)
  m <- .pq_wi32(ph, 4L, .pqERle, m)
  hd <- .pq_writer()
  l <- .pq_wi32(hd, 1L, .pqPData, 0L)
  l <- .pq_wi32(hd, 2L, usize, l)
  l <- .pq_wi32(hd, 3L, length(page), l)
  l <- .pq_wstruct(hd, 5L, .pq_wstop(ph), l)
  blob <- c(.pq_wstop(hd), page)
  cmd <- .pq_writer()
  l <- .pq_wi32(cmd, 1L, ptype, 0L)
  l <- .pq_wlisti32(cmd, 2L, c(.pqERle, .pqEPlain), l)
  l <- .pq_wlistbin(cmd, 3L, "x", l)
  l <- .pq_wi32(cmd, 4L, .pqCUncompressed, l)
  l <- .pq_wi64(cmd, 5L, n, l)
  l <- .pq_wi64(cmd, 6L, length(blob), l)
  l <- .pq_wi64(cmd, 7L, length(blob), l)
  l <- .pq_wi64(cmd, 9L, off, l)
  cc <- .pq_writer()
  l <- .pq_wi64(cc, 2L, off, 0L)
  l <- .pq_wstruct(cc, 3L, .pq_wstop(cmd), l)
  root <- .pq_writer()
  l <- .pq_wbytes(root, 4L, "schema", 0L)
  l <- .pq_wi32(root, 5L, 1L, l)
  se <- .pq_writer()
  l <- .pq_wi32(se, 1L, ptype, 0L)
  if (!is.null(typelen)) l <- .pq_wi32(se, 2L, typelen, l)
  l <- .pq_wi32(se, 3L, .pqRequired, l)
  l <- .pq_wbytes(se, 4L, "x", l)
  if (!is.null(conv)) l <- .pq_wi32(se, 6L, conv, l)
  if (!is.null(scale)) l <- .pq_wi32(se, 7L, scale, l)
  if (!is.null(prec)) l <- .pq_wi32(se, 8L, prec, l)
  if (!is.null(lt)) l <- .pq_wstruct(se, 10L, lt, l)
  rg <- .pq_writer()
  l <- .pq_wliststruct(rg, 1L, list(.pq_wstop(cc)), 0L)
  l <- .pq_wi64(rg, 2L, length(blob), l)
  l <- .pq_wi64(rg, 3L, n, l)
  fm <- .pq_writer()
  l <- .pq_wi32(fm, 1L, 1L, 0L)
  l <- .pq_wliststruct(fm, 2L, list(.pq_wstop(root), .pq_wstop(se)), l)
  l <- .pq_wi64(fm, 3L, n, l)
  l <- .pq_wliststruct(fm, 4L, list(.pq_wstop(rg)), l)
  ft <- .pq_wstop(fm)
  f <- tempfile(fileext = ".parquet")
  writeBin(c(charToRaw("PAR1"), blob, ft,
             writeBin(length(ft), raw(), size = 4L, endian = "little"),
             charToRaw("PAR1")), f)
  f
}
i32 <- function(x) writeBin(as.integer(x), raw(), size = 4L, endian = "little")

test_that("a DECIMAL kept as whole numbers is read with its scale", {
  f <- pq_lone(.pqInt32, i32(c(1234, -150, 1)), 3L, conv = .pqCtDecimal, scale = 2L)
  expect_equal(morie_read_parquet(f)$x, c(12.34, -1.5, 0.01), tolerance = 1e-15)
  # 64-bit: low half, high half
  f <- pq_lone(.pqInt64, i32(c(1234, 0, -150, -1)), 2L, conv = .pqCtDecimal,
               scale = 3L)
  expect_equal(morie_read_parquet(f)$x, c(1.234, -0.15), tolerance = 1e-15)
})

test_that("a DECIMAL kept as fixed-length bytes is read; other bytes are refused", {
  page <- as.raw(c(0x04, 0xd2, 0xff, 0x6a, 0x00, 0x00))
  f <- pq_lone(.pqFlba, page, 3L, conv = .pqCtDecimal, scale = 2L, typelen = 2L)
  expect_equal(morie_read_parquet(f)$x, c(12.34, -1.5, 0), tolerance = 1e-15)
  # sixteen bytes, as arrow's decimal128: a small negative stays exact
  page <- c(rep(as.raw(0xff), 15L), as.raw(0x85), raw(15L), as.raw(0x7b))
  f <- pq_lone(.pqFlba, page, 2L, conv = .pqCtDecimal, scale = 0L, typelen = 16L)
  expect_identical(morie_read_parquet(f)$x, c(-123, 123))
  f <- pq_lone(.pqFlba, raw(4L), 2L, typelen = 2L)
  expect_error(morie_read_parquet(f), "column .x. holds fixed-length bytes")
  f <- pq_lone(.pqByteArray, c(i32(1), as.raw(0x05)), 1L, conv = .pqCtDecimal,
               scale = 0L)
  expect_error(morie_read_parquet(f), "DECIMAL stored as bytes of varying length")
  expect_identical(.Call(C_rmd_pq_flba, as.raw(c(9, 0, 7)), 2, 1, 2, 1L), 7)
  expect_error(.Call(C_rmd_pq_flba, as.raw(c(0, 7)), 2, 1, 2, 1L), "internal")
})

# `w` bytes, big-endian, of the whole number with the bits `bits` set, negated
# in two's complement when `neg`
pq_be <- function(w, bits = integer(), neg = FALSE) {
  b <- integer(w)
  for (k in bits) b[w - k %/% 8] <- b[w - k %/% 8] + 2^(k %% 8)
  if (neg) {
    b <- 255 - b
    i <- w
    while ((b[i] <- b[i] + 1) == 256) {
      b[i] <- 0
      i <- i - 1L
    }
  }
  as.raw(b)
}
# a LogicalType of member `id`, its own struct `inner` (empty by default)
pq_lt <- function(id, inner = as.raw(0)) {
  w <- .pq_writer()
  .pq_wstruct(w, id, inner, 0L)
  .pq_wstop(w)
}
dec <- function(w, vals, scale = 0L, ...) {
  morie_read_parquet(pq_lone(.pqFlba, unlist(vals), length(vals),
                             conv = .pqCtDecimal, scale = scale, typelen = w,
                             ...))$x
}

test_that("a DECIMAL in fixed bytes reads exactly at every length", {
  small <- c(0, 1, -1, 123, -123)
  for (w in c(1, 2, 7, 8, 9, 16, 17, 32, 33, 128, 129, 200, 4096)) {
    vals <- list(pq_be(w), pq_be(w, 0), pq_be(w, 0, TRUE),
                 pq_be(w, c(0, 1, 3:6)), pq_be(w, c(0, 1, 3:6), TRUE))
    # a length of 200 read 0 and 1 as NaN (0 * 256^199)
    expect_identical(dec(w, vals), small, info = w)
    # no precision given: the most the length holds, so a scale of 2 is allowed
    expect_identical(dec(w, vals, 2L), small / 100, info = w)
  }
  # the format's digits for each length (Parquet's own table)
  most <- vapply(1:32, function(n) {
    floor((8 * n - 1) * log10(2))
  }, numeric(1))
  expect_identical(most[c(1:9, 16, 32)], c(2, 4, 6, 9, 11, 14, 16, 18, 21, 38, 76))
})

test_that("a long DECIMAL rounds as its whole number would, or is refused", {
  # 2^100 + 2^47 + 1 is past halfway between two doubles: up, as the +1 says
  up <- pq_be(16, c(100, 47, 0))
  tie <- pq_be(16, c(100, 47))
  expect_warning(x <- dec(16, list(up, pq_be(16, c(100, 47, 0), TRUE), tie)),
                 "2^53", fixed = TRUE)
  expect_identical(x, c(2^100 + 2^48, -(2^100 + 2^48), 2^100))
  # the ends of 128 bytes; one byte more holds a number no double can
  ends <- list(pq_be(128, 1023, TRUE), pq_be(128, 0:1022))
  expect_identical(suppressWarnings(dec(128, ends)), c(-2^1023, 2^1023))
  expect_identical(suppressWarnings(dec(129, list(pq_be(129, 1023)))), 2^1023)
  expect_error(dec(129, list(pq_be(129), pq_be(129, 1024))),
               paste0("^parquet: column .x. holds a DECIMAL whose unscaled value ",
                      "is past the range of a double \\(2\\^1024\\)$"))
  # a scale past 308: 10^s is infinite, and the value is not 0 or NaN
  x <- suppressWarnings(dec(200, list(pq_be(200, 1000)), 310L, prec = 400L))
  expect_equal(x, 2^1000 / 1e300 / 1e10, tolerance = 1e-14)
  expect_identical(dec(200, list(pq_be(200, 0)), 400L, prec = 450L), 0)
})

test_that("a DECIMAL's precision and scale are held to the format", {
  msg <- function(p, s) {
    paste0("^parquet: column .x. is a DECIMAL of precision ", sprintf("%d", p),
           " and scale ", sprintf("%d", s),
           "; Parquet needs a precision of 1 or more and a scale from 0 to ",
           "the precision$")
  }
  one <- list(pq_be(2, 0))
  expect_error(dec(2, one, 0L, prec = 0L), msg(0, 0))
  expect_error(dec(2, one, -1L, prec = 3L), msg(3, -1))
  expect_error(dec(2, one, 3L, prec = 2L), msg(2, 3))
  expect_error(dec(2, one, 0L, prec = 5L),
               paste0("^parquet: column .x. is a DECIMAL of precision 5 in 2 ",
                      "bytes, which hold at most 4 digits$"))
  expect_error(dec(16, list(pq_be(16)), 0L, prec = 1e9),
               "precision 1000000000 in 16 bytes, which hold at most 38 digits$")
  expect_identical(dec(2, one, 4L, prec = 4L), 1e-4)
  f <- pq_lone(.pqInt32, i32(1), 1L, conv = .pqCtDecimal, scale = 0L, prec = 10L)
  expect_error(morie_read_parquet(f), "precision 10 in INT32, which holds at most 9")
  f <- pq_lone(.pqInt64, i32(c(1, 0)), 1L, conv = .pqCtDecimal, scale = 0L,
               prec = 19L)
  expect_error(morie_read_parquet(f), "precision 19 in INT64, which holds at most 18")
  f <- pq_lone(.pqDouble, raw(8), 1L, conv = .pqCtDecimal, scale = 0L)
  expect_error(morie_read_parquet(f), "DECIMAL stored as physical type 5")
  # the newer logical type's scale and precision are the ones read
  w <- .pq_writer()
  l <- .pq_wi32(w, 1L, 3L, 0L)
  l <- .pq_wi32(w, 2L, 4L, l)
  f <- pq_lone(.pqFlba, pq_be(2, 0), 1L, typelen = 2L, lt = pq_lt(5L, .pq_wstop(w)))
  expect_identical(morie_read_parquet(f)$x, 1e-3)
  l <- .pq_wi32(w <- .pq_writer(), 1L, 3L, 0L)
  l <- .pq_wi32(w, 2L, 9L, l)
  f <- pq_lone(.pqFlba, pq_be(2, 0), 1L, typelen = 2L, lt = pq_lt(5L, .pq_wstop(w)))
  expect_error(morie_read_parquet(f), "precision 9 in 2 bytes")
})

test_that("a fixed length the file states is a whole number from 1 up", {
  for (tl in list(0L, -1L, 2^31, NULL)) {
    f <- pq_lone(.pqFlba, raw(2), 1L, conv = .pqCtDecimal, scale = 0L, typelen = tl)
    expect_error(morie_read_parquet(f),
                 paste0("^parquet: column .x. holds fixed-length bytes of length ",
                        if (is.null(tl)) "\\(none\\)" else format(tl, scientific = FALSE),
                        "; Parquet needs a length from 1 to 2147483647$"),
                 info = format(tl))
  }
})

test_that("a UUID is read as text and a FLOAT16 as a number", {
  id <- as.raw(c(0:15, 0xf0:0xff))
  f <- pq_lone(.pqFlba, id, 2L, typelen = 16L, lt = pq_lt(14L))
  expect_identical(morie_read_parquet(f)$x,
                   c("00010203-0405-0607-0809-0a0b0c0d0e0f",
                     "f0f1f2f3-f4f5-f6f7-f8f9-fafbfcfdfeff"))
  expect_error(morie_read_parquet(pq_lone(.pqFlba, id[1:15], 1L, typelen = 15L,
                                          lt = pq_lt(14L))),
               "^parquet: column .x. is a UUID of 15 bytes; Parquet's is 16$")
  h <- c(0x3c00, 0xc000, 0x7bff, 0x0001, 0x0400, 0x3555, 0x7c00, 0xfc00, 0x8000,
         0x7e00)
  page <- as.raw(rbind(h %% 256, h %/% 256))
  x <- morie_read_parquet(pq_lone(.pqFlba, page, 10L, typelen = 2L,
                                  lt = pq_lt(15L)))$x
  expect_identical(x[1:9], c(1, -2, 65504, 2^-24, 2^-14, 1365 / 4096, Inf, -Inf, 0))
  expect_identical(1 / x[9], -Inf)
  expect_true(is.nan(x[10]))
  expect_error(morie_read_parquet(pq_lone(.pqFlba, raw(4), 1L, typelen = 4L,
                                          lt = pq_lt(15L))),
               "^parquet: column .x. is a FLOAT16 of 4 bytes; Parquet's is 2$")
})

test_that("unsigned columns are not read as negative numbers", {
  f <- pq_lone(.pqInt32, i32(c(1, -1294967296, -1)), 3L, conv = .pqCtUint32)
  expect_identical(morie_read_parquet(f)$x, c(1, 3000000000, 4294967295))
  f <- pq_lone(.pqInt64, i32(c(1, 0, -1, -1)), 2L, conv = .pqCtUint64)
  expect_warning(x <- morie_read_parquet(f)$x, "whole numbers of 2^53 or more",
                 fixed = TRUE)
  expect_identical(x, c(1, 2^64))
  # the newer logical type says the same: INTEGER, not signed
  int <- list("10" = list("1" = 32L, "2" = FALSE))
  expect_identical(.pq_apply_logical(c(-1L, 2L), .pqInt32, NULL, NULL, int),
                   c(4294967295, 2))
  int[["10"]][["2"]] <- TRUE
  expect_identical(.pq_apply_logical(c(-1L, 2L), .pqInt32, NULL, NULL, int),
                   c(-1L, 2L))
})

test_that("a 64-bit whole number past 2^53 is rounded with a warning", {
  f <- pq_lone(.pqInt64, i32(c(1, 2097152, 5, 0)), 2L)
  expect_warning(x <- morie_read_parquet(f)$x, "column .x. holds whole numbers")
  expect_identical(x, c(2^53, 5))
  f <- pq_lone(.pqInt64, i32(c(7, 0, 5, 0)), 2L)
  expect_no_warning(expect_identical(morie_read_parquet(f)$x, c(7, 5)))
})

test_that("times and timestamps are read as times, in every unit", {
  utc <- function(x) as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  ts <- function(unit) {
    list("8" = list("1" = TRUE, "2" = stats::setNames(list(list()), unit)))
  }
  # INT64 and INT96 times reach it as seconds (decoded so, rounded once, by
  # .pq_decode_plain()); every unit, by logical or by converted type, is a time
  for (u in c("1", "2", "3")) {
    expect_no_warning(
      expect_identical(.pq_apply_logical(1.5e9, .pqInt64, NULL, NULL, ts(u)), utc(1.5e9))
    )
  }
  expect_identical(.pq_apply_logical(1.5e9, .pqInt64, .pqCtTsMillis), utc(1.5e9))
  expect_identical(.pq_apply_logical(1.5e9, .pqInt64, .pqCtTsMicros), utc(1.5e9))
  expect_identical(.pq_per(.pqCtTsMicros, NULL), c(ts = 1e6))
  expect_identical(.pq_per(NULL, ts("3")), c(ts = 1e9))
  # the legacy 96-bit timestamp
  expect_identical(.pq_apply_logical(1.5e9, .pqInt96, NULL), utc(1.5e9))
  expect_identical(.pq_decode_plain(c(rep(as.raw(0), 8), as.raw(c(0x8c, 0x3d, 0x25, 0))),
                                    1L, .pqInt96, 1L)$values, 0)
  hour <- as.difftime(3600, units = "secs")
  expect_identical(.pq_apply_logical(3600000L, .pqInt32, .pqCtTimeMillis), hour)
  expect_identical(.pq_apply_logical(3600, .pqInt64, .pqCtTimeMicros), hour)
  tm <- list("7" = list("1" = TRUE, "2" = list("3" = list())))
  expect_identical(.pq_apply_logical(3600, .pqInt64, NULL, NULL, tm), hour)
  expect_identical(.pq_per(NULL, tm), c(time = 1e9))
  day <- structure(18262, class = "Date")
  dt <- list("6" = list())
  expect_identical(.pq_apply_logical(18262L, .pqInt32, NULL, NULL, dt), day)
  expect_identical(.pq_apply_logical(18262L, .pqInt32, .pqCtDate), day)
  # a unit the file does not name leaves the numbers as they are
  nounit <- list("8" = list("1" = TRUE))
  expect_identical(.pq_apply_logical(5, .pqInt64, NULL, NULL, nounit), 5)
  f <- pq_lone(.pqInt32, i32(c(3600000, 1500)), 2L, conv = .pqCtTimeMillis)
  expect_identical(morie_read_parquet(f)$x, as.difftime(c(3600, 1.5), units = "secs"))
})

test_that("a row group of no rows is read as no rows, wherever it says it starts", {
  f <- pq_lone(.pqInt32, raw(0), 0L, off = 0)
  x <- morie_read_parquet(f)
  expect_identical(dim(x), c(0L, 1L))
  expect_identical(x$x, integer())
})

test_that("the run decoder reads runs and bit-packed groups, and refuses short data", {
  r <- .pq_read_rle(as.raw(c(0x06, 0x05)), 1L, 3L, 3L, 2L)
  expect_identical(r, list(values = c(5L, 5L, 5L), pos = 3L))
  # one bit-packed group of eight one-bit values, least significant first
  r <- .pq_read_rle(as.raw(c(0x03, 0xaa)), 1L, 1L, 8L, 2L)
  expect_identical(r$values, rep(0:1, 4L))
  # three-bit values 0..7 packed in three bytes, then a run that is cut to the count
  r <- .pq_read_rle(as.raw(c(0x03, 0x88, 0xc6, 0xfa, 0x08, 0x02)), 1L, 3L, 10L, 6L)
  expect_identical(r$values, c(0:7, 2L, 2L))
  expect_identical(r$pos, 7L)
  # a two-byte value, a width of nothing
  expect_identical(.pq_read_rle(as.raw(c(0x02, 0x01, 0x01)), 1L, 9L, 1L, 3L)$values, 257L)
  expect_identical(.pq_read_rle(raw(0), 1L, 0L, 4L, 0L),
                   list(values = integer(4L), pos = 1L))
  rle <- function(b, width, count) .pq_read_rle(as.raw(b), 1L, width, count, length(b))
  expect_error(rle(c(0x02, 0x01), 3L, 4L), "ran out after 1 of 4")
  expect_error(.pq_read_rle(as.raw(0x80), 1L, 3L, 1L, 1L), "run header runs past")
  expect_error(.pq_read_rle(as.raw(c(0x02)), 1L, 3L, 1L, 1L), "run value runs past")
  expect_error(rle(c(0x05, 0x01), 3L, 9L), "bit-packed run of 2 groups")
  expect_error(rle(rep(0x80, 11L), 3L, 1L), "longer than 10 bytes")
  expect_error(rle(c(0x02, rep(0xff, 4L)), 32L, 1L), "above 2\\^31")
  expect_error(rle(c(0x03, rep(0xff, 32L)), 32L, 8L), "above 2\\^31")
  expect_error(.pq_read_rle(raw(2L), 1L, 33L, 1L, 2L), "above 32")
  expect_error(.Call(C_rmd_pq_rle, "x", 1, 1L, 1, 1), "must be raw")
  expect_error(.Call(C_rmd_pq_rle, raw(1L), 0, 1L, 1, 1), "bad position")
})

test_that("runs of one value each are read at once, not a run at a time in R", {
  n <- 300000L
  buf <- as.raw(rep(c(0x02, 0x01), n))
  t0 <- proc.time()[["elapsed"]]
  r <- .pq_read_rle(buf, 1L, 1L, n, length(buf))
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_identical(r$values, rep(1L, n))
})

test_that("a mirror's timestamp or date column keeps its instants", {
  t <- as.POSIXct(c("2020-01-01 00:00:00", "2020-01-01 13:30:00", NA), tz = "UTC")
  expect_identical(.rmd_astext(t), c("2020-01-01T00:00:00Z", "2020-01-01T13:30:00Z", NA))
  expect_equal(as.numeric(.rmd_ptime(.rmd_astext(t))), as.numeric(t))
  # a date is midnight on the Chicago clock, as Socrata's floating timestamps are
  d <- .rmd_ptime(.rmd_astext(as.Date("2020-01-01")))
  expect_identical(format(d, "%Y-%m-%d %H:%M", tz = "America/Chicago"),
                   "2020-01-01 00:00")
  expect_identical(.rmd_astext(c(a = 1.5)), "1.5")
})

test_that("mdsha() hashes one string or raw bytes, nothing turned into text", {
  for (x in list(1, 0.1 + 0.2, TRUE, as.Date("2020-01-01"), factor("a"))) {
    expect_error(mdsha(x), "a raw vector or a single string")
  }
  expect_identical(mdsha("1"), mdsha(charToRaw("1")))
})

test_that("a slug no dataset could have is refused in the package's words", {
  expect_error(mdload(strrep("a", 1e5)), "^No dataset 'a{40}\\.\\.\\.'")
  expect_error(mdload(strrep("a", 201L)), "See mdcat\\(\\) for valid slugs")
})

test_that("MORIE_DATA_URL must be an http(s) address", {
  old <- Sys.getenv("MORIE_DATA_URL", unset = NA)
  on.exit(
    if (is.na(old)) Sys.unsetenv("MORIE_DATA_URL") else Sys.setenv(MORIE_DATA_URL = old)
  )
  Sys.setenv(MORIE_DATA_URL = "example.org/data")
  expect_error(.rmd_data_url(), "MORIE_DATA_URL is .example.org/data., which is not")
  Sys.setenv(MORIE_DATA_URL = "https://example.org/data/")
  expect_identical(.rmd_data_url(), "https://example.org/data")
  Sys.setenv(MORIE_DATA_URL = "HTTPS://Example.org")
  expect_identical(.rmd_data_url(), "HTTPS://Example.org")
})

test_that("levels padded to a whole block, as DuckDB writes them, are read", {
  # three values, the middle one missing: the levels are one bit-packed run
  # of 32 groups (256 levels) whatever the count, then the two values
  lev <- c(as.raw(0x41), as.raw(0x05), raw(31L))
  page <- c(i32(length(lev)), lev, i32(c(1, 2)))
  ph <- .pq_writer()
  m <- .pq_wi32(ph, 1L, 3L, 0L)
  m <- .pq_wi32(ph, 2L, .pqEPlain, m)
  m <- .pq_wi32(ph, 3L, .pqERle, m)
  m <- .pq_wi32(ph, 4L, .pqERle, m)
  expect_lte(length(page), .pq_data_most(.pqInt32, 3L, NULL, 1L, .pqEPlain))
  expect_identical(.pq_read_rle(lev, 1L, 1L, 3L, length(lev))$values, c(1L, 0L, 1L))
  # the allowance is a constant: a page of a million values gains nothing
  expect_identical(.pq_hybrid_most(1e6, 1) - .pq_hybrid_most(0, 1), 2e6)
  expect_identical(.pq_hybrid_most(0, 32), 1026)
})

test_that("a page of text is not inflated past what its size on disk allows", {
  expect_identical(.pq_text_most(100, .pqCZstd), 64 * 2^20)
  expect_identical(.pq_text_most(8 * 2^20, .pqCZstd), 128 * 2^20)
  # one string column, one row
  body <- c(i32(1L), as.raw(0x61))
  expect_identical(morie_read_parquet(pq_lone(.pqByteArray, body, 1L))$x, "a")
  # the same page, its header claiming 1 GiB: refused before it is inflated
  f <- pq_lone(.pqByteArray, body, 1L, usize = 2^30)
  t0 <- proc.time()[["elapsed"]]
  expect_error(morie_read_parquet(f), "inflate to 1073741824 bytes of text")
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
})

# 32-bit words, little-endian, from their signed or unsigned values (-2^31 included,
# which as.integer() makes NA with a warning)
w32 <- function(x) {
  x <- ifelse(x < 0, x + 2^32, x)
  as.raw(vapply(x, function(v) (v %/% 256^(0:3)) %% 256, numeric(4)))
}
# an IntType LogicalType of `bw` bits, signed or not
pq_int <- function(bw, signed) {
  pq_lt(10L, as.raw(c(0x13, bw, if (signed) 0x11 else 0x12, 0)))
}

test_that("a value outside an 8- or 16-bit column's width is refused as damage", {
  for (m in list(list(conv = 11L), list(lt = pq_int(8, FALSE)),
                 list(conv = 12L, lt = pq_int(16, FALSE)), list(conv = 15L),
                 list(lt = pq_int(16, TRUE)))) {
    ok <- if (identical(m$conv, 15L)) {
      c(-128, 127)
    } else if (identical(m$lt, pq_int(16, TRUE))) {
      c(-32768, 32767)
    } else if (identical(m$conv, 12L)) {
      c(0, 65535)
    } else {
      c(0, 255)
    }
    f <- do.call(pq_lone, c(list(.pqInt32, i32(ok), 2L), m))
    expect_identical(morie_read_parquet(f)$x, as.integer(ok))
    for (bad in c(ok[1L] - 1, ok[2L] + 1, -1, -2^31)) {
      if (bad >= ok[1L] && bad <= ok[2L]) next
      f <- do.call(pq_lone, c(list(.pqInt32, w32(c(ok[1L], bad)), 2L), m))
      expect_error(morie_read_parquet(f),
                   sprintf(paste0("^parquet: column 'x' is marked as .* holds the ",
                                  "32-bit word %.0f "), bad),
                   info = paste(bad, names(m)))
    }
  }
  # every word is a value of a 32-bit column, signed or not
  f <- pq_lone(.pqInt32, i32(c(-1, -2^31 + 1)), 2L, lt = pq_int(32, TRUE))
  expect_identical(morie_read_parquet(f)$x, c(-1L, -2147483647L))
  # a width the stored type does not have is refused by name
  expect_error(morie_read_parquet(pq_lone(.pqInt32, i32(1), 1L, lt = pq_int(64, FALSE))),
               "marked as a whole number of 64 bits stored as INT32")
  expect_error(morie_read_parquet(pq_lone(.pqInt64, i32(c(1, 0)), 1L, conv = 17L)),
               "marked as a whole number of 32 bits stored as INT64")
  expect_error(morie_read_parquet(pq_lone(.pqInt32, i32(1), 1L, lt = pq_int(12, TRUE))),
               "whole number of 12 bits")
})

test_that("the logical type wins where it and the converted type disagree", {
  w <- i32(c(5, -1))
  expect_identical(morie_read_parquet(pq_lone(.pqInt32, w, 2L, conv = .pqCtUint32,
                                              lt = pq_int(32, TRUE)))$x, c(5L, -1L))
  expect_error(morie_read_parquet(pq_lone(.pqInt32, w, 2L, conv = .pqCtUint32,
                                          lt = pq_int(8, FALSE))),
               "unsigned 8-bit .* word -1 \\(0xFFFFFFFF\\)")
  expect_identical(morie_read_parquet(pq_lone(.pqInt32, i32(c(5, 255)), 2L,
                                              conv = .pqCtUint32,
                                              lt = pq_int(8, FALSE)))$x, c(5L, 255L))
  # a DATE converted type under an integer logical type is the integer
  expect_identical(morie_read_parquet(pq_lone(.pqInt32, i32(3), 1L, conv = .pqCtDate,
                                              lt = pq_int(32, TRUE)))$x, 3L)
  # and with no logical type the converted type is read
  expect_identical(morie_read_parquet(pq_lone(.pqInt32, i32(3), 1L,
                                              conv = .pqCtDate))$x, as.Date(3))
})
