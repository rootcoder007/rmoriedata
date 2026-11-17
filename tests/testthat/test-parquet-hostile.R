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
  # the nearest microsecond: each of these is one, so it reads back as it was
  expect_identical(as.numeric(back), as.numeric(tt))
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
  # one optional INT32: a 4-byte level length, at most 2 bytes per level and
  # the 34 a block of padded levels may take, and 4 bytes of value make 44
  # bytes at most
  expect_error(morie_read_parquet(pq_one_int(usize = 45)),
               paste0("^parquet: page of column x says it inflates to 45 ",
                      "bytes; its 1 values take at most 44$"))
  expect_error(morie_read_parquet(pq_one_int(usize = 2^30)), "take at most 44$")
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

test_that("a Parquet cap option that is not a positive number is refused", {
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = 1:3), f)
  for (opt in c("rmoriedata.parquet_max_rows",
                "rmoriedata.parquet_max_page_bytes")) {
    for (bad in list(NA, "10", 0, -1, c(1, 2), TRUE)) {
      withr::local_options(structure(list(bad), names = opt))
      expect_error(morie_read_parquet(f),
                   paste0("^parquet: option ", opt,
                          " must be one positive number$"),
                   info = deparse(bad))
    }
    withr::local_options(structure(list(NULL), names = opt))
  }
  expect_identical(morie_read_parquet(f)$a, 1:3)
})

test_that("a text page is held to what its codec can inflate it to", {
  # the package's writer puts a column in one page: 5.9 MB of gzip held
  # 115 MB of category labels and was refused at 16 times
  expect_gte(.pq_text_most(5880731, .pqCGzip), 115014338)
  expect_lt(.pq_text_most(33000, .pqCGzip), 2^30)
  expect_identical(.pq_text_most(1e7, .pqCSnappy), 22 * 1e7)
  expect_identical(.pq_text_most(1e7, .pqCZstd), 16 * 1e7)
  expect_identical(.pq_text_most(100, .pqCZstd), 64 * 2^20)
  x <- data.frame(x = rep(strrep("ab", 500), 7e4), stringsAsFactors = FALSE)
  f <- withr::local_tempfile(fileext = ".parquet")
  for (co in c("gzip", "snappy")) {
    morie_write_parquet(x, f, compression = co)
    expect_identical(morie_read_parquet(f)$x, x$x)
  }
})

# A file of one BYTE_ARRAY column `x` of N rows from `pages`, each a list of n
# (values), body (the page as it inflates), and optionally dict = TRUE, enc,
# and usize (what the header claims, the body's size when NULL); `pay` maps a
# body to its stored bytes for `codec`. `ptype`, `typelen` and `prec` make it
# a column of another type (`prec` a DECIMAL of that precision and scale 0).
pq_text_file <- function(pages, N, codec = .pqCGzip, optional = FALSE,
                         ptype = .pqByteArray, typelen = NULL, prec = NULL) {
  pay <- switch(as.character(codec),
                "2" = function(b) .Call(C_rmd_gzip_compress, b),
                "1" = .pq_snappy_compress, function(b) b)
  blob <- raw(0)
  for (pg in pages) {
    p <- if (is.null(pg$stored)) pay(pg$body) else pg$stored
    type <- if (isTRUE(pg$dict)) .pqPDict else .pqPData
    blob <- c(blob, pq_hdr(type, pg$usize %||% length(pg$body), length(p),
                           n = pg$n, enc = pg$enc %||% .pqEPlain), p)
  }
  cmd <- .pq_writer()
  l <- .pq_wi32(cmd, 1L, ptype, 0L)
  l <- .pq_wlisti32(cmd, 2L, c(.pqERle, .pqEPlain, .pqERleDict), l)
  l <- .pq_wlistbin(cmd, 3L, "x", l)
  l <- .pq_wi32(cmd, 4L, codec, l)
  l <- .pq_wi64(cmd, 5L, N, l)
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
  l <- .pq_wi32(se, 1L, ptype, 0L)
  if (!is.null(typelen)) l <- .pq_wi32(se, 2L, typelen, l)
  l <- .pq_wi32(se, 3L, if (optional) .pqOptional else .pqRequired, l)
  l <- .pq_wbytes(se, 4L, "x", l)
  if (!is.null(prec)) {
    l <- .pq_wi32(se, 6L, .pqCtDecimal, l)
    l <- .pq_wi32(se, 7L, 0L, l)
    l <- .pq_wi32(se, 8L, prec, l)
  }
  rg <- .pq_writer()
  l <- .pq_wliststruct(rg, 1L, list(.pq_wstop(cc)), 0L)
  l <- .pq_wi64(rg, 2L, length(blob), l)
  l <- .pq_wi64(rg, 3L, N, l)
  fm <- .pq_writer()
  l <- .pq_wi32(fm, 1L, 1L, 0L)
  l <- .pq_wliststruct(fm, 2L, list(.pq_wstop(root), .pq_wstop(se)), l)
  l <- .pq_wi64(fm, 3L, N, l)
  l <- .pq_wliststruct(fm, 4L, list(.pq_wstop(rg)), l)
  ft <- .pq_wstop(fm)
  f <- tempfile(fileext = ".parquet")
  writeBin(c(charToRaw("PAR1"), blob, ft,
             writeBin(length(ft), raw(), size = 4L, endian = "little"),
             charToRaw("PAR1")), f)
  f
}

test_that("a GZIP page of several members is read; bytes after the last are not", {
  body <- writeBin(1:3000, raw(), size = 4L, endian = "little")
  gz <- function(b) .Call(C_rmd_gzip_compress, b)
  one <- function(stored) {
    pq_text_file(list(list(n = 3000L, body = body, stored = stored)), 3000L,
                 ptype = .pqInt32)
  }
  expect_identical(morie_read_parquet(one(c(gz(body[1:6000]), gz(body[6001:12000]))))$x,
                   1:3000)
  expect_identical(morie_read_parquet(one(c(gz(body[1:5]), gz(raw(0)),
                                            gz(body[-(1:5)]))))$x, 1:3000)
  for (tail in list(raw(4), as.raw(1:9), memCompress(as.raw(1:9), "gzip"))) {
    expect_error(morie_read_parquet(one(c(gz(body), tail))),
                 "^parquet: gzip: page holds data after its stated 12000 bytes")
  }
  # members that inflate to more than the page states: refused at that size
  expect_error(morie_read_parquet(one(c(gz(body), gz(body)))),
               "^parquet: gzip: page holds data after its stated 12000 bytes")
  expect_error(morie_read_parquet(one(gz(body[-1]))),
               "^parquet: gzip: page did not decompress to its stated 12000 bytes")
})

# an RLE run of `n` copies of `v` at bit width `w` (w <= 8)
pq_run <- function(n, v = 0L, w = 1L) {
  h <- n * 2
  out <- raw(0)
  repeat {
    if (h < 128) {
      out <- c(out, as.raw(h))
      break
    }
    out <- c(out, as.raw(h %% 128 + 128))
    h <- h %/% 128
  }
  c(out, as.raw(v))
}

test_that("the text budget is summed in doubles and holds at its limit", {
  expect_identical(.pq_max_text(), 2^32)
  ok <- c(x = 2^31, y = 2^31)
  expect_invisible(.pq_text_budget(ok, c(x = 1, y = 1)))
  expect_error(.pq_text_budget(ok + c(0, 1), c(x = 10, y = 20)),
               paste0("^parquet: the compressed pages of text and fixed-length ",
                      "bytes in this file say they inflate to 4294967297 bytes ",
                      "in all, 2147483649 of them in column y from 20 stored ",
                      "bytes; such pages are inflated up to 4294967296 bytes a ",
                      "file \\(option ",
                      "rmoriedata.parquet_max_text_bytes\\)$"))
  withr::local_options(rmoriedata.parquet_max_text_bytes = 5)
  expect_invisible(.pq_text_budget(c(x = 2, y = 3), c(1, 1)))
  expect_error(.pq_text_budget(c(x = 2, y = 4), c(1, 1)), "6 bytes in all")
  for (bad in list(NA, "10", 0, -1, c(1, 2), TRUE)) {
    withr::local_options(rmoriedata.parquet_max_text_bytes = bad)
    expect_error(.pq_max_text(), paste0("^parquet: option rmoriedata.parquet_",
                                        "max_text_bytes must be one positive ",
                                        "number$"))
  }
})

test_that("compressed text past the budget is refused before any of it is inflated", {
  # 160 pages of 16 bytes that are not gzip at all, each saying it inflates to
  # 60 MiB (under the bound of a single page): 9.4 GiB in all, refused from
  # the headers alone, so no page is inflated and the gzip error never comes
  junk <- list(n = 1L, body = raw(0), stored = as.raw(rep(0xff, 16L)),
               usize = 60 * 2^20)
  f <- pq_text_file(rep(list(junk), 160L), 160)
  t0 <- proc.time()[["elapsed"]]
  expect_error(morie_read_parquet(f),
               paste0("^parquet: the compressed pages of text and fixed-length ",
                      "bytes in this file say they inflate to 10066329600 bytes ",
                      "in all, 10066329600 of them in column x from 2560 stored ",
                      "bytes; such pages are inflated up to 4294967296 bytes a ",
                      "file \\(option ",
                      "rmoriedata.parquet_max_text_bytes\\)$"))
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  # the same file under a larger budget gets as far as inflating
  withr::local_options(rmoriedata.parquet_max_text_bytes = 2^34)
  expect_error(morie_read_parquet(f), "^parquet: ")
  expect_error(morie_read_parquet(f), "gzip", fixed = TRUE)
})

test_that("the text budget reads a file at its limit and refuses one byte more", {
  s <- strrep("abcdefgh", 128)
  body <- rep(c(writeBin(1024L, raw(), size = 4L, endian = "little"),
                charToRaw(s)), 1000L)
  pg <- list(n = 1000L, body = body)
  each <- length(body)
  for (codec in c(.pqCGzip, .pqCSnappy)) {
    f <- pq_text_file(rep(list(pg), 4L), 4000, codec = codec)
    withr::local_options(rmoriedata.parquet_max_text_bytes = 4 * each)
    expect_identical(morie_read_parquet(f)$x, rep(s, 4000))
    withr::local_options(rmoriedata.parquet_max_text_bytes = 4 * each - 1)
    expect_error(morie_read_parquet(f), paste0("inflate to ", sprintf("%d", 4L * each),
                                               " bytes in all"))
  }
  # pages stored as they are cost what the file holds, and are not counted
  f <- pq_text_file(rep(list(pg), 4L), 4000, codec = .pqCUncompressed)
  withr::local_options(rmoriedata.parquet_max_text_bytes = 1)
  expect_identical(morie_read_parquet(f)$x, rep(s, 4000))
})

test_that("a dictionary column costs about its result, not copies of it", {
  s <- strrep("abcdefgh", 128)
  n <- 2e6
  dict <- list(n = 1L, dict = TRUE,
               body = c(writeBin(1024L, raw(), size = 4L, endian = "little"),
                        charToRaw(s)))
  # one run of n indices at bit width 1, as a 184-byte file held 5e7 of them
  run <- list(n = n, enc = .pqERleDict, body = c(as.raw(1L), pq_run(n)))
  f <- pq_text_file(list(dict, run), n)
  invisible(gc())
  # the megabytes beside "max used": its column is not the same on every
  # platform (macOS has a "limit (Mb)" column before it)
  before <- gc(reset = TRUE)[2L, 2L]
  r <- morie_read_parquet(f)
  g <- gc()
  peak <- g[2L, which(colnames(g) == "max used") + 1L] - before
  expect_identical(r$x, rep(s, n))
  size <- as.numeric(object.size(r$x)) / 2^20
  # the result is 8 bytes a row; expanding the indices in R cost four times it
  expect_lt(peak, 1.5 * size)
})

test_that("dictionary and plain pages fill their rows, missing values in place", {
  lv <- function(d) .pq_encode_levels(d, 1L)
  dict <- list(n = 2L, dict = TRUE, body = .pq_encode_plain(c("a", "bc"),
                                                            .pqByteArray, "x"))
  # page 1: rows a, NA, bc, a; indices 0 1 0 bit-packed at width 1 (0b010)
  p1 <- list(n = 4L, enc = .pqERleDict,
             body = c(lv(c(1L, 0L, 1L, 1L)), as.raw(1L), as.raw(c(3L, 2L))))
  # page 2: PLAIN rows NA, "z"
  p2 <- list(n = 2L, body = c(lv(c(0L, 1L)), .pq_encode_plain("z", .pqByteArray,
                                                              "x")))
  # page 3: no rows
  p3 <- list(n = 0L, body = lv(integer(0)))
  f <- pq_text_file(list(dict, p1, p3, p2), 6, optional = TRUE)
  expect_identical(morie_read_parquet(f)$x, c("a", NA, "bc", "a", NA, "z"))
  # a bit width of 0: every index is 0
  p0 <- list(n = 3L, enc = .pqERleDict, body = c(lv(c(1L, 1L, 0L)), as.raw(0L)))
  f <- pq_text_file(list(dict, p0), 3, optional = TRUE)
  expect_identical(morie_read_parquet(f)$x, c("a", "a", NA))
  # an index past the dictionary, and indices that run out
  bad <- list(n = 1L, enc = .pqERleDict, body = c(as.raw(2L), pq_run(1L, 2L)))
  expect_error(morie_read_parquet(pq_text_file(list(dict, bad), 1)),
               "^parquet: dictionary index out of range in column x$")
  short <- list(n = 3L, enc = .pqERleDict, body = c(as.raw(1L), pq_run(2L)))
  expect_error(morie_read_parquet(pq_text_file(list(dict, short), 3)),
               "^parquet: RLE data ran out after 2 of 3 values$")
  wide <- list(n = 1L, enc = .pqERleDict, body = c(as.raw(33L), raw(8)))
  expect_error(morie_read_parquet(pq_text_file(list(dict, wide), 1)),
               "^parquet: RLE bit width 33 above 32$")
  expect_error(.Call(C_rmd_pq_rows, raw(4), 0, 0, 0, 0L, c("a", "b"), 1, "x"),
               "^parquet: page of column x holds 2 values for 1 present rows$")
  expect_error(.Call(C_rmd_pq_rows, raw(4), 0, 0, 9, 1L, "a", 1, "x"),
               "bad position")
})

test_that("the package's own writer reads back a text column past 64 MiB", {
  cats <- c("THEFT", "BATTERY", "CRIMINAL DAMAGE", "ASSAULT",
            "DECEPTIVE PRACTICE", "OTHER OFFENSE", "NARCOTICS", "BURGLARY")
  set.seed(7)
  x <- data.frame(x = sample(cats, 5e6, TRUE), stringsAsFactors = FALSE)
  # 14 bytes a value: 71 MB of text in one gzip page, past the 64 MiB floor
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(x, f)
  expect_identical(morie_read_parquet(f)$x, x$x)
})

test_that("fixed-length bytes count toward the budget, before any is inflated", {
  # values of 65536 bytes (a DECIMAL of 38 digits): a 65 KB file of 1024 of
  # them inflated to 64 MiB, and cost 1.1 GB to read
  tl <- 65536
  n <- 256L
  pg <- list(n = n, body = raw(tl * n))
  f <- pq_text_file(list(pg), n, ptype = .pqFlba, typelen = tl, prec = 38L)
  withr::local_options(rmoriedata.parquet_max_text_bytes = tl * n - 1)
  t0 <- proc.time()[["elapsed"]]
  expect_error(morie_read_parquet(f),
               paste0("^parquet: the compressed pages of text and fixed-length ",
                      "bytes in this file say they inflate to 16777216 bytes in ",
                      "all, 16777216 of them in column x from [0-9]+ stored ",
                      "bytes; such pages are inflated up to 16777215 bytes a ",
                      "file \\(option rmoriedata.parquet_max_text_bytes\\)$"))
  expect_lt(proc.time()[["elapsed"]] - t0, 2)
  withr::local_options(rmoriedata.parquet_max_text_bytes = tl * n)
  invisible(gc())
  before <- gc(reset = TRUE)
  before <- sum(before[, which(colnames(before) == "max used") + 1L])
  expect_identical(morie_read_parquet(f)$x, numeric(n))
  g <- gc()
  peak <- sum(g[, which(colnames(g) == "max used") + 1L]) - before
  # the page itself, and little more: no raw vector a value, no copy of the block
  expect_lt(peak, 2.5 * tl * n / 2^20)
  # stored as they are, they cost what the file holds and are not counted
  f <- pq_text_file(list(list(n = 4L, body = raw(4 * tl))), 4, ptype = .pqFlba,
                    typelen = tl, prec = 38L, codec = .pqCUncompressed)
  withr::local_options(rmoriedata.parquet_max_text_bytes = 1)
  expect_identical(morie_read_parquet(f)$x, numeric(4))
})

test_that("fixed-length pages fill their rows from a dictionary, missing in place", {
  lv <- function(d) .pq_encode_levels(d, 1L)
  be <- function(v) writeBin(as.integer(v), raw(), size = 4L, endian = "big")
  dict <- list(n = 3L, dict = TRUE, body = c(be(-5), be(70000), be(0)))
  p1 <- list(n = 4L, enc = .pqERleDict,
             body = c(lv(c(1L, 0L, 1L, 1L)), as.raw(2L), pq_run(1L, 1L, 2L),
                      pq_run(2L, 0L, 2L)))
  p2 <- list(n = 2L, body = c(lv(c(0L, 1L)), be(-1)))
  f <- pq_text_file(list(dict, p1, p2), 6, optional = TRUE, ptype = .pqFlba,
                    typelen = 4L, prec = 9L)
  expect_identical(morie_read_parquet(f)$x, c(70000, NA, -5, -5, NA, -1))
  # a page with every row missing, alone and after the dictionary
  none <- list(n = 2L, body = lv(c(0L, 0L)))
  for (pages in list(list(none), list(dict, none))) {
    f <- pq_text_file(pages, 2, optional = TRUE, ptype = .pqFlba, typelen = 4L,
                      prec = 9L)
    expect_identical(morie_read_parquet(f)$x, c(NA_real_, NA_real_))
  }
  # a definition level above 1 is refused the same way on either kind of page
  bad <- function(body) {
    pq_text_file(list(dict, list(n = 1L, enc = body$enc, body = body$b)), 1,
                 optional = TRUE, ptype = .pqFlba, typelen = 4L, prec = 9L)
  }
  lv3 <- c(writeBin(2L, raw(), size = 4L, endian = "little"), pq_run(1L, 3L))
  msg <- "^parquet: column x has a definition level of 3, above its maximum of 1$"
  expect_error(morie_read_parquet(bad(list(enc = .pqERleDict,
                                           b = c(lv3, as.raw(0L))))), msg)
  expect_error(morie_read_parquet(bad(list(enc = .pqEPlain, b = c(lv3, be(1))))),
               msg)
})

test_that("each size a column's metadata states is bounded before it is used", {
  # INT96 and fixed-length pages are held to their count times their width
  f <- pq_text_file(list(list(n = 1L, body = raw(12), usize = 13)), 1,
                    ptype = .pqInt96)
  expect_error(morie_read_parquet(f), "its 1 values take at most 12$")
  f <- pq_text_file(list(list(n = 2L, body = raw(8), usize = 9)), 2,
                    ptype = .pqFlba, typelen = 4L, prec = 9L)
  expect_error(morie_read_parquet(f), "its 2 values take at most 8$")
  # a repetition type the format does not define
  f <- pq_text_file(list(list(n = 1L, body = raw(4))), 1, ptype = .pqInt32,
                    codec = .pqCUncompressed)
  expect_identical(morie_read_parquet(f)$x, 0L)
  b <- readBin(f, "raw", file.size(f))
  # the schema element's field 3 (REQUIRED, 0) between its type and its name
  at <- max(grepRaw(as.raw(c(0x25, 0x00, 0x18)), b, fixed = TRUE, all = TRUE))
  b[at + 1L] <- as.raw(10L)
  writeBin(b, f)
  expect_error(morie_read_parquet(f),
               "^parquet: the file is damaged: column x has no valid repetition type$")
})
