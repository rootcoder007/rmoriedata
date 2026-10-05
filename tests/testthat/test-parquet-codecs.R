# The Parquet page codecs (src/snappy.c, src/gzip.c): every codec round-trips,
# the store is written with GZIP, and real compression happens.

test_that("snappy compresses, round-trips, and handles runs and incompressible bytes", {
  comp <- rmoriedata:::.pq_snappy_compress
  dec <- rmoriedata:::.pq_snappy_decompress
  set.seed(1)
  text <- charToRaw(paste(rep("the quick brown fox jumps over the lazy dog. ", 2000),
                          collapse = ""))
  cases <- list(raw(0), as.raw(7), as.raw(rep(65, 70000)),
                as.raw(sample(0:255, 50000, TRUE)), text)
  for (x in cases) expect_identical(dec(comp(x)), x)
  expect_lt(length(comp(text)), length(text) / 10)
  expect_lt(length(comp(as.raw(rep(65, 70000)))), 5000)
  # a literal-only stream (what the writer produced before) still reads
  lit <- c(as.raw(c(5L, bitwShiftL(4L, 2L))), charToRaw("hello"))
  expect_identical(rawToChar(dec(lit)), "hello")
  expect_error(dec(as.raw(c(10L, 2L, 1L, 0L))), "copy offset|bad")
})

test_that("every codec writes a file that reads back identically", {
  df <- data.frame(a = c(1.5, NA, 3), b = c("x", "y", NA), c = c(TRUE, FALSE, TRUE),
                   d = c(1L, 2L, 3L), stringsAsFactors = FALSE)
  for (cmp in list("gzip", "snappy", NULL)) {
    f <- tempfile(fileext = ".parquet")
    rmoriedata:::morie_write_parquet(df, f, compression = cmp)
    expect_equal(rmoriedata:::morie_read_parquet(f), df, ignore_attr = TRUE)
  }
  expect_error(rmoriedata:::morie_write_parquet(df, tempfile(), compression = "zstd"),
               "gzip")
})

test_that("the shipped store is GZIP and much smaller than its raw pages", {
  p <- morie_data_path("siu_directors_reports")
  d <- morie_data_load("siu_directors_reports", format = "parquet")
  expect_identical(nrow(d), 4613L)
  # the SIU table's pages hold ~10.6 MB of text; GZIP stores it in ~2 MB
  expect_lt(file.size(p), 3e6)
})
