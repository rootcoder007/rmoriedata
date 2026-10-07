# SPDX-License-Identifier: AGPL-3.0-or-later
# Malformed input for the hand-written decoders: every input either decodes or raises an R
# error, never crashes, hangs or reads out of bounds. The sanitizer job runs this file
# under ASAN + UBSAN, which turns any out-of-bounds read into a failure.

snappy_dec <- function(x) .Call(rmoriedata:::C_rmd_snappy_decompress, x)
gzip_dec <- function(x, n) .Call(rmoriedata:::C_rmd_gzip_decompress, x, n)

test_that("snappy rejects truncated, flipped and random inputs with an R error", {
  plain <- charToRaw(strrep("the quick brown fox jumps over the lazy dog ", 40))
  good <- .Call(rmoriedata:::C_rmd_snappy_compress, plain)
  expect_identical(snappy_dec(good), plain)
  rng <- function(n) as.raw(sample.int(256L, n, replace = TRUE) - 1L)
  outcomes <- character()
  for (i in seq_len(1500L)) {
    x <- switch(i %% 3L + 1L,
      good[seq_len(sample.int(length(good), 1L))],             # truncation
      { y <- good; j <- sample.int(length(y), 1L); y[j] <- xor(y[j], as.raw(1L)); y },  # bit flip
      rng(sample.int(64L, 1L))                                  # noise
    )
    r <- tryCatch({ snappy_dec(x); "ok" }, error = function(e) "error")
    outcomes <- c(outcomes, r)
  }
  expect_true(all(outcomes %in% c("ok", "error")))
  expect_true(any(outcomes == "error"))
  expect_error(snappy_dec(as.raw(c(0xff, 0xff, 0xff, 0xff, 0x0f))), "expected")
  expect_error(snappy_dec(raw(0)), "length header")
})

test_that("gzip rejects truncated, flipped and random inputs with an R error", {
  plain <- charToRaw(strrep("rmoriedata ", 300))
  good <- .Call(rmoriedata:::C_rmd_gzip_compress, plain)
  expect_identical(gzip_dec(good, length(plain)), plain)
  for (i in seq_len(600L)) {
    x <- if (i %% 2L) good[seq_len(sample.int(length(good), 1L))] else {
      y <- good; j <- sample.int(length(y), 1L); y[j] <- xor(y[j], as.raw(4L)); y
    }
    r <- tryCatch({ gzip_dec(x, length(plain)); "ok" }, error = function(e) "error")
    expect_true(r %in% c("ok", "error"))
  }
  # a size the stream does not deliver is an error, not a padded result
  expect_error(gzip_dec(good, length(plain) + 10L))
})

test_that("the page CRC helper is zlib's crc32", {
  expect_identical(.Call(rmoriedata:::C_rmd_crc32, charToRaw("123456789")), 3421780262)
  expect_identical(.Call(rmoriedata:::C_rmd_crc32, raw(0)), 0)
})
