# Non-ASCII text must round-trip through the Parquet codec byte for byte
# in every locale, including C, where enc2utf8() on an unmarked string
# would replace each byte with its "<c3><a9>" display form.

utf8_bytes <- as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9, 0x20, 0xe4, 0xb8, 0xad,
                       0xe6, 0x96, 0x87)) # "café 中文"

test_that("the writer keeps UTF-8 bytes whether or not the string is marked", {
  marked <- rawToChar(utf8_bytes)
  Encoding(marked) <- "UTF-8"
  unmarked <- rawToChar(utf8_bytes) # Encoding "unknown", as read.csv gives
  f <- tempfile(fileext = ".parquet")
  rmoriedata:::morie_write_parquet(data.frame(a = c(marked, unmarked, NA),
                                              stringsAsFactors = FALSE), f)
  back <- rmoriedata:::morie_read_parquet(f)$a
  expect_identical(charToRaw(back[1]), utf8_bytes)
  expect_identical(charToRaw(back[2]), utf8_bytes)
  expect_true(is.na(back[3]))
  expect_identical(Encoding(back[1:2]), c("UTF-8", "UTF-8"))
  expect_true(all(validUTF8(back[1:2])))
  expect_identical(nchar(back[1]), 7L)
  expect_true(all(validUTF8(back[1:2])))
  expect_identical(nchar(back[1]), 7L)
})

test_that("the SIU corpus carries the same bytes from CSV and Parquet", {
  a <- siuload()
  b <- siuload(format = "parquet")
  hit <- NULL
  for (col in names(a)) {
    i <- which(vapply(a[[col]], function(z) any(charToRaw(z) > 0x7f), TRUE))
    if (length(i)) {
      hit <- c(col, i[1])
      break
    }
  }
  expect_false(is.null(hit)) # the corpus has non-ASCII cells; the scan must find one
  expect_identical(charToRaw(a[[hit[1]]][as.integer(hit[2])]),
                   charToRaw(b[[hit[1]]][as.integer(hit[2])]))
})

test_that("unmarked non-UTF-8 bytes are refused by name; marked latin1 is transcoded", {
  latin1 <- rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9))) # "caf\xe9", Encoding unknown
  f <- tempfile(fileext = ".parquet")
  expect_error(
    rmoriedata:::morie_write_parquet(data.frame(a = latin1, stringsAsFactors = FALSE), f),
    "column .a. holds a string that is not valid UTF-8")
  marked <- latin1
  Encoding(marked) <- "latin1"
  rmoriedata:::morie_write_parquet(data.frame(a = marked, stringsAsFactors = FALSE), f)
  expect_identical(charToRaw(rmoriedata:::morie_read_parquet(f)$a), utf8_bytes[1:5])
})

test_that("a data page v2 is reported as such before any decompression", {
  f <- tempfile(fileext = ".parquet")
  rmoriedata:::morie_write_parquet(data.frame(a = c("x", "y", "z"),
                                              stringsAsFactors = FALSE), f)
  raw <- readBin(f, "raw", file.size(f))
  # the first page header follows the 4-byte magic: field 1 (i32, page
  # type) is 0x15 then the zigzag value; DATA_PAGE = 0, DATA_PAGE_V2 = 3
  skip_if_not(identical(raw[5:6], as.raw(c(0x15, 0x00))),
              "writer page-header layout changed; fixture needs updating")
  raw[6] <- as.raw(0x06)
  writeBin(raw, f)
  expect_error(rmoriedata:::morie_read_parquet(f), "data page v2")
})

test_that("duplicate column names are refused on write and kept as they are on read", {
  f <- tempfile(fileext = ".parquet")
  dup <- setNames(data.frame(1:3, 4:6), c("x", "x"))
  expect_error(rmoriedata:::morie_write_parquet(dup, f), "duplicate column names: .x.")
  # a file that really holds two columns named x: write x and y
  # uncompressed, then rename y to x in the footer (the only 0x79 bytes)
  rmoriedata:::morie_write_parquet(data.frame(x = 1:3, y = 4:6), f,
                                   compression = NULL)
  raw <- readBin(f, "raw", file.size(f))
  skip_if_not(sum(raw == as.raw(0x79)) == 2L, "fixture layout changed")
  raw[raw == as.raw(0x79)] <- as.raw(0x78)
  writeBin(raw, f)
  expect_no_warning(d <- rmoriedata:::morie_read_parquet(f))
  expect_identical(names(d), c("x", "x"))
  expect_identical(d[[1L]], 1:3)
  expect_identical(d[[2L]], 4:6)
  # `columns` names the first of them
  expect_identical(rmoriedata:::morie_read_parquet(f, columns = "x")[[1L]], 1:3)
})

test_that("column names come back as the file has them, whatever they are", {
  f <- withr::local_tempfile(fileext = ".parquet")
  nm <- c("20", "", "NA", "NULL", "TRUE", "a b-c\u00e9", "1x", "x.1")
  d <- as.data.frame(lapply(seq_along(nm), function(i) c(i, i + 20L)))
  names(d) <- nm
  rmoriedata:::morie_write_parquet(d, f)
  r <- rmoriedata:::morie_read_parquet(f)
  expect_identical(names(r), nm)
  expect_identical(unname(as.list(r)), unname(as.list(d)))
  expect_identical(attr(r, "row.names"), 1:2)
  expect_identical(names(rmoriedata:::morie_read_parquet(f, columns = c("", "NA"))),
                   c("", "NA"))
  # no rows: the same names and types
  z <- structure(lapply(d, function(x) x[0]), names = nm, class = "data.frame",
                 row.names = integer())
  rmoriedata:::morie_write_parquet(z, f)
  r <- rmoriedata:::morie_read_parquet(f)
  expect_identical(names(r), nm)
  expect_identical(unname(lapply(r, class)), rep(list("integer"), length(nm)))
  expect_identical(nrow(r), 0L)
  # a file of no columns (its schema is the root alone): its rows and no columns
  root <- .pq_writer()
  l <- .pq_wbytes(root, 4L, "schema", 0L)
  l <- .pq_wi32(root, 5L, 0L, l)
  rg <- .pq_writer()
  l <- .pq_wliststruct(rg, 1L, list(), 0L)
  l <- .pq_wi64(rg, 2L, 0, l)
  l <- .pq_wi64(rg, 3L, 3, l)
  fm <- .pq_writer()
  l <- .pq_wi32(fm, 1L, 1L, 0L)
  l <- .pq_wliststruct(fm, 2L, list(.pq_wstop(root)), l)
  l <- .pq_wi64(fm, 3L, 3, l)
  l <- .pq_wliststruct(fm, 4L, list(.pq_wstop(rg)), l)
  ft <- .pq_wstop(fm)
  writeBin(c(charToRaw("PAR1"), ft, writeBin(length(ft), raw(), size = 4L,
                                             endian = "little"), charToRaw("PAR1")), f)
  r <- rmoriedata:::morie_read_parquet(f)
  expect_identical(dim(r), c(3L, 0L))
  expect_s3_class(r, "data.frame")
})

test_that("text the reader returns is UTF-8; text that is not is refused (N11)", {
  # the writer takes marked latin1 and UTF-8 and writes UTF-8; read back, marked UTF-8
  x <- c(rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9))), rawToChar(utf8_bytes), "ascii", NA)
  Encoding(x[1L]) <- "latin1"
  Encoding(x[2L]) <- "UTF-8"
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = x, stringsAsFactors = FALSE), f, compression = NULL)
  back <- morie_read_parquet(f)$a
  expect_identical(Encoding(back), c("UTF-8", "UTF-8", "unknown", "unknown"))
  expect_true(all(validUTF8(back)))
  expect_identical(back, enc2utf8(x))
  # the decoder refuses bytes that are not UTF-8, and a NUL, naming the column
  val <- function(b) c(writeBin(length(b), raw(), size = 4L, endian = "little"), b)
  bad <- val(as.raw(c(0x61, 0x62, 0x63, 0xff, 0xfe)))
  expect_error(.pq_decode_plain(bad, 1L, .pqByteArray, 1L, cname = "s"),
               "parquet: column s holds a value that is not valid UTF-8 (value 1)",
               fixed = TRUE)
  expect_error(.pq_decode_plain(c(val(charToRaw("ok")), val(as.raw(c(0x61, 0)))), 1L,
                                .pqByteArray, 2L, cname = "s"),
               "column s holds a value with a NUL byte (value 2)", fixed = TRUE)
  for (b in list(as.raw(c(0xc0, 0xaf)), as.raw(c(0xed, 0xa0, 0x80)),
                 as.raw(c(0xf4, 0x90, 0x80, 0x80)), as.raw(0xe2))) {
    expect_error(.pq_decode_plain(val(b), 1L, .pqByteArray, 1L), "not valid UTF-8")
  }
  expect_error(.pq_decode_plain(val(charToRaw("abc"))[1:5], 1L, .pqByteArray, 1L),
               "^parquet: a BYTE_ARRAY value runs past the end")
  # a file another writer made, with such a value in it, is refused the same way
  skip_if_not_installed("nanoparquet")
  g <- withr::local_tempfile(fileext = ".parquet")
  nanoparquet::write_parquet(data.frame(s = c("abcde", "ok")), g,
                             compression = "uncompressed", encoding = "PLAIN")
  r <- readBin(g, "raw", file.size(g))
  # the first copy is the value in the data page (the footer's statistics follow)
  at <- grepRaw(charToRaw("abcde"), r)
  skip_if_not(length(at) == 1L, "fixture layout changed")
  r[at + 3:4] <- as.raw(c(0xff, 0xfe))
  writeBin(r, g)
  expect_error(morie_read_parquet(g), "parquet: column s holds a value that is not valid")
})

test_that("columns = character(0) and a damaged footer length are told right (N13)", {
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = 1:3, b = c("x", "y", "z")), f)
  d <- morie_read_parquet(f, columns = character(0))
  expect_identical(dim(d), c(3L, 0L))
  expect_s3_class(d, "data.frame")
  r <- readBin(f, "raw", file.size(f))
  n <- length(r)
  len <- readBin(r[(n - 7L):(n - 4L)], "integer", size = 4L, endian = "little")
  for (k in c(len - 1L, len + 1L, len - 7L)) {
    r2 <- r
    r2[(n - 7L):(n - 4L)] <- writeBin(k, raw(), size = 4L, endian = "little")
    g <- withr::local_tempfile(fileext = ".parquet")
    writeBin(r2, g)
    e <- tryCatch(morie_read_parquet(g), error = conditionMessage)
    expect_match(e, "^parquet: ", info = k)
    expect_no_match(e, "parquet_max_rows", fixed = TRUE, info = k)
  }
})
