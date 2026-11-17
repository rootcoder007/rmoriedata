# Extracted from test-parquet-hostile.R:285

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "rmoriedata", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
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

# test -------------------------------------------------------------------------
expect_error(morie_read_parquet(pq_one_int(usize = 12)),
               paste0("^parquet: page of column x says it inflates to 12 ",
                      "bytes; its 1 values take at most 11$"))
