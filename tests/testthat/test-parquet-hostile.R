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
