# SPDX-License-Identifier: AGPL-3.0-or-later
# Whole numbers whose 32-bit words include 0x80000000, which readBin(size = 4)
# reads as NA without a word: every boundary word in the low and the high half,
# in each integer and time type, plain and from a dictionary, required and
# optional, read to the value; and the writer's own POSIXct times.

# The 4 bytes of a word from 0 to 2^32 - 1, little-endian.
le4 <- function(w) as.raw((w %/% 256^(0:3)) %% 256)
words <- c(0, 2^31 - 1, 2^31, 2^32 - 1)
# every pair of boundary words as (low, high)
pairs <- expand.grid(lo = words, hi = words)

# A struct holding one struct field `fid` (by default an empty one).
pq_st <- function(fid, inner = as.raw(0)) {
  w <- .pq_writer()
  .pq_wstruct(w, fid, inner, 0L)
  .pq_wstop(w)
}

# A page: its header (data page, or the dictionary page with `dict`) and body.
pq_page <- function(body, n, enc = .pqEPlain, dict = FALSE) {
  ph <- .pq_writer()
  m <- .pq_wi32(ph, 1L, n, 0L)
  m <- .pq_wi32(ph, 2L, enc, m)
  if (!dict) {
    m <- .pq_wi32(ph, 3L, .pqERle, m)
    m <- .pq_wi32(ph, 4L, .pqERle, m)
  }
  hd <- .pq_writer()
  l <- .pq_wi32(hd, 1L, if (dict) .pqPDict else .pqPData, 0L)
  l <- .pq_wi32(hd, 2L, length(body), l)
  l <- .pq_wi32(hd, 3L, length(body), l)
  l <- .pq_wstruct(hd, if (dict) 7L else 5L, .pq_wstop(ph), l)
  c(.pq_wstop(hd), body)
}

# The data pages of a column: `vals` the PLAIN bytes of its k present values;
# `miss` the rows missing (an optional column), `dict` the values in a dictionary
# page and each row's index (at 8 bits, one run each) in the data page.
pq_pages <- function(vals, k, n, miss, dict) {
  lv <- raw(0)
  if (!is.null(miss)) lv <- .pq_encode_levels(replace(rep(1L, n), miss, 0L), 1L)
  if (!dict) return(list(data = pq_page(c(lv, vals), n), dict = raw(0)))
  idx <- c(as.raw(8L), as.raw(rbind(2L, seq_len(k) - 1L)))
  list(data = pq_page(c(lv, idx), n, .pqERleDict), dict = pq_page(vals, k, dict = TRUE))
}

# The schema element of the column.
pq_elem <- function(ptype, miss, conv, scale, prec, lt) {
  se <- .pq_writer()
  l <- .pq_wi32(se, 1L, ptype, 0L)
  l <- .pq_wi32(se, 3L, if (is.null(miss)) .pqRequired else .pqOptional, l)
  l <- .pq_wbytes(se, 4L, "x", l)
  if (!is.null(conv)) l <- .pq_wi32(se, 6L, conv, l)
  if (!is.null(scale)) l <- .pq_wi32(se, 7L, scale, l)
  if (!is.null(prec)) l <- .pq_wi32(se, 8L, prec, l)
  if (!is.null(lt)) l <- .pq_wstruct(se, 10L, lt, l)
  .pq_wstop(se)
}

# A one-column file of the k values whose PLAIN bytes are `vals`, with rows `miss`
# missing among them; or of the k rows of the required data pages `pages`.
pq_words <- function(ptype, vals, k, miss = NULL, dict = FALSE, conv = NULL,
                     scale = NULL, prec = NULL, lt = NULL, pages = NULL) {
  n <- k + length(miss)
  pg <- if (is.null(pages)) pq_pages(vals, k, n, miss, dict) else
    list(data = pages, dict = raw(0))
  blob <- c(pg$dict, pg$data)
  cmd <- .pq_writer()
  l <- .pq_wi32(cmd, 1L, ptype, 0L)
  l <- .pq_wlisti32(cmd, 2L, c(.pqERle, .pqEPlain, .pqERleDict), l)
  l <- .pq_wlistbin(cmd, 3L, "x", l)
  l <- .pq_wi32(cmd, 4L, .pqCUncompressed, l)
  l <- .pq_wi64(cmd, 5L, n, l)
  l <- .pq_wi64(cmd, 6L, length(blob), l)
  l <- .pq_wi64(cmd, 7L, length(blob), l)
  l <- .pq_wi64(cmd, 9L, 4 + length(pg$dict), l)
  if (dict) l <- .pq_wi64(cmd, 11L, 4, l)
  cc <- .pq_writer()
  l <- .pq_wi64(cc, 2L, 4, 0L)
  l <- .pq_wstruct(cc, 3L, .pq_wstop(cmd), l)
  root <- .pq_writer()
  l <- .pq_wbytes(root, 4L, "schema", 0L)
  l <- .pq_wi32(root, 5L, 1L, l)
  rg <- .pq_writer()
  l <- .pq_wliststruct(rg, 1L, list(.pq_wstop(cc)), 0L)
  l <- .pq_wi64(rg, 2L, length(blob), l)
  l <- .pq_wi64(rg, 3L, n, l)
  fm <- .pq_writer()
  l <- .pq_wi32(fm, 1L, 1L, 0L)
  l <- .pq_wliststruct(fm, 2L, list(.pq_wstop(root),
                                    pq_elem(ptype, miss, conv, scale, prec, lt)), l)
  l <- .pq_wi64(fm, 3L, n, l)
  l <- .pq_wliststruct(fm, 4L, list(.pq_wstop(rg)), l)
  ft <- .pq_wstop(fm)
  f <- tempfile(fileext = ".parquet")
  writeBin(c(charToRaw("PAR1"), blob, ft, le4(length(ft)), charToRaw("PAR1")), f)
  f
}

# The column read, and the warnings it gave.
pq_got <- function(f) {
  w <- character()
  x <- withCallingHandlers(morie_read_parquet(f)$x, warning = function(c) {
    w <<- c(w, conditionMessage(c))
    invokeRestart("muffleWarning")
  })
  unlink(f)
  list(x = x, w = w)
}

# `want` with NA put in at the rows `miss` of the whole column.
pq_fill <- function(want, miss) {
  if (is.null(miss)) return(want)
  out <- rep(want[1L], length(want) + length(miss))
  out[miss] <- NA
  out[-miss] <- want
  out
}

# Read `vals` as each layout (plain or dictionary, required or optional) and
# compare with `want`, the value of each in R, and with the 2^53 warning when
# `big` and only then.
pq_each <- function(ptype, vals, want, big = FALSE, ...) {
  k <- length(want)
  for (dict in c(FALSE, TRUE)) {
    for (miss in list(NULL, c(2L, k + 2L))) {
      got <- pq_got(pq_words(ptype, vals, k, miss, dict, ...))
      lab <- paste("dict", dict, "optional", !is.null(miss))
      expect_identical(got$x, pq_fill(want, miss), label = lab)
      expect_identical(length(got$w), as.integer(big), label = lab)
      if (big) expect_match(got$w, "holds whole numbers of 2^53", fixed = TRUE)
    }
  }
}

i64s <- as.vector(rbind(sapply(pairs$lo, le4), sapply(pairs$hi, le4)))
hi_s <- ifelse(pairs$hi >= 2^31, pairs$hi - 2^32, pairs$hi)
signed64 <- hi_s * 2^32 + pairs$lo # exact product, one rounding of the sum
unsigned64 <- pairs$hi * 2^32 + pairs$lo

test_that("INT32 and UINT_32 read every boundary word", {
  vals <- as.vector(sapply(words, le4))
  pq_each(.pqInt32, vals, c(0, 2^31 - 1, -2^31, -1))
  pq_each(.pqInt32, vals, words, conv = .pqCtUint32)
  int <- pq_st(10L, as.raw(c(0x13, 32, 0x12, 0))) # an IntType of 32 bits, not signed
  pq_each(.pqInt32, vals, words, lt = int)
  # without -2^31 the column is integers, as before
  pq_each(.pqInt32, as.vector(sapply(words[-3], le4)), c(0L, .Machine$integer.max, -1L))
})

test_that("INT64 and UINT_64 read every pair of boundary words, rounded once", {
  pq_each(.pqInt64, i64s, signed64, big = TRUE)
  pq_each(.pqInt64, i64s, unsigned64, big = TRUE, conv = .pqCtUint64)
  # below 2^53 exact, with no warning
  small <- abs(signed64) < 2^53
  pq_each(.pqInt64, as.vector(rbind(sapply(pairs$lo[small], le4),
                                    sapply(pairs$hi[small], le4))),
          signed64[small])
  # a UINT_64 past 2^63 is the nearest double: 3 * 2^62 + 1025 -> 3 * 2^62 + 2048
  pq_each(.pqInt64, c(le4(1025), le4(3 * 2^30)), 3 * 2^62 + 2048, big = TRUE,
          conv = .pqCtUint64)
})

test_that("timestamps, INT64 decimals and INT96 times read every boundary word", {
  utc <- function(x) as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  pq_each(.pqInt64, i64s, utc(signed64 / 1e3), conv = .pqCtTsMillis)
  pq_each(.pqInt64, i64s, utc(signed64 / 1e6), conv = .pqCtTsMicros)
  for (u in 1:3) {
    pq_each(.pqInt64, i64s, utc(signed64 / 10^(3 * u)),
            lt = pq_st(8L, pq_st(2L, pq_st(u))))
  }
  pq_each(.pqInt64, i64s, .pq_unscale(signed64, 2), big = TRUE,
          conv = .pqCtDecimal, scale = 2L, prec = 18L)
  jday <- c(2440588, 0, 2^31, 2^32 - 1)
  for (j in jday) {
    vals <- as.vector(rbind(sapply(pairs$lo, le4), sapply(pairs$hi, le4),
                            matrix(le4(j), 4L, nrow(pairs))))
    pq_each(.pqInt96, vals, utc(((j - 2440588) * 86400 * 1e9 + signed64) / 1e9))
  }
})

test_that("pages of integers and of -2^31 make one column of doubles", {
  f <- pq_words(.pqInt32, c(le4(7), le4(2^31)), 2L, miss = 1L)
  expect_identical(pq_got(f)$x, c(NA, 7, -2^31))
  two <- c(pq_page(le4(7), 1L), pq_page(le4(2^31), 1L))
  expect_identical(pq_got(pq_words(.pqInt32, NULL, 2L, pages = two))$x, c(7, -2^31))
  two <- c(pq_page(le4(2^31), 1L), pq_page(le4(7), 1L))
  expect_identical(pq_got(pq_words(.pqInt32, NULL, 2L, pages = two))$x, c(-2^31, 7))
  # the dictionary and the values: integers, then a double
  expect_identical(.pq_decode_plain(c(le4(1), le4(2^32 - 2)), 1L, .pqInt32, 2L)$values,
                   c(1L, -2L))
  expect_identical(.pq_decode_plain(c(le4(1), le4(2^31)), 1L, .pqInt32, 2L)$values,
                   c(1, -2^31))
  expect_error(.pq_decode_plain(le4(1)[1:3], 1L, .pqInt32, 1L), "^parquet: ")
  expect_error(.pq_decode_plain(le4(1), 1L, .pqInt64, 1L), "^parquet: ")
  expect_identical(.pq_u32(c(le4(2^31), le4(2^32 - 1))), c(2^31, 2^32 - 1))
})

test_that("the writer keeps the times whose low word is 0x80000000", {
  t <- as.POSIXct(c("1995-07-09 16:12:48", "2012-07-13 11:01:20", "2029-07-18 05:49:52",
                    "2012-07-13 11:01:19", "2012-07-13 11:01:21"), tz = "UTC")
  # 2^29 seconds apart, the same low word: 1961, before 1970, is negative
  t <- c(t, t[2L] - 3 * 2^29)
  f <- tempfile(fileext = ".parquet")
  on.exit(unlink(f))
  expect_no_warning(morie_write_parquet(data.frame(t = t), f))
  back <- morie_read_parquet(f)$t
  expect_identical(as.numeric(back), as.numeric(t))
  expect_identical(.pq_encode_i64(c(2^31, -2^31, 2^31 + 2^32, -2^63 + 2048, 2^63 - 1024)),
                   c(le4(2^31), le4(0), le4(2^31), le4(2^32 - 1), le4(2^31), le4(1),
                     le4(2048), le4(2^31), le4(2^32 - 1024), le4(2^31 - 1)))
  expect_error(.pq_encode_i64(2^63), "^parquet: ")
  expect_error(.pq_encode_i64(0.5), "^parquet: ")
  # whole numbers in a double column, at 2^31 and 2^53
  d <- c(2^31, -2^31, 2^31 - 1, -2^31 + 1, 2^53 - 1, -2^53 + 1, 2^53, -2^53, 2^53 + 2)
  morie_write_parquet(data.frame(d = d), f)
  expect_identical(morie_read_parquet(f)$d, d)
})
