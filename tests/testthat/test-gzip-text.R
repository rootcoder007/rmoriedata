# SPDX-License-Identifier: AGPL-3.0-or-later
# The text of a .gz file is exactly its gzip members, every one of them, inflated by
# the package's own routine (src/gzip.c). NUL bytes after the last member are
# ignored, as gzip -d ignores them; any other bytes after it are refused, naming them,
# and are never read as text. A damaged member is a damaged file.

gz_of <- function(x) .Call(C_rmd_gzip_compress, if (is.raw(x)) x else charToRaw(x))

test_that("every member of a .gz file is inflated, as gzfile() reads them", {
  set.seed(11)
  for (i in 1:40) {
    parts <- lapply(seq_len(sample(1:4, 1L)), function(j) {
      as.raw(sample(c(0:255, rep(97:101, 20)), sample(c(0:5, 1e3, 7e4), 1L), TRUE))
    })
    b <- do.call(c, lapply(parts, gz_of))
    f <- withr::local_tempfile(fileext = ".gz")
    writeBin(b, f)
    con <- gzfile(f, "rb")
    want <- readBin(con, "raw", 1e6)
    close(con)
    expect_identical(.rmd_gunzip(b), want)
    expect_identical(.rmd_gunzip(b), do.call(c, c(list(raw(0)), parts)))
  }
})

test_that("NUL padding after the last member is ignored; anything else is refused", {
  b <- c(gz_of("a,b\n1,2\n"), gz_of("3,4\n"))
  expect_identical(rawToChar(.rmd_gunzip(c(b, raw(512)))), "a,b\n1,2\n3,4\n")
  for (tail in list(charToRaw("garbage"), as.raw(c(0, 0, 1)), as.raw(c(0x1f, 0, 0)),
                    c(raw(3), gz_of("5,6\n")))) {
    re <- paste0("^%d bytes after the last gzip member \\(from byte %d\\) are ",
                 "not gzip data$")
    e <- expect_error(.rmd_gunzip(c(b, tail)), sprintf(re, length(tail), length(b) + 1L))
    expect_false(inherits(e, "rmd_damage"))
  }
  # a member cut short, or damaged inside, is damage
  expect_error(.rmd_gunzip(b[-length(b)]), "ends inside a gzip member",
               class = "rmd_damage")
  bad <- b
  bad[12] <- as.raw(0xff)
  expect_error(.rmd_gunzip(bad), "gzip data is damaged", class = "rmd_damage")
  bad <- b
  bad[length(gz_of("a,b\n1,2\n")) - 5L] <- as.raw(0x00)
  expect_error(.rmd_gunzip(bad), "damaged", class = "rmd_damage")
})

test_that("every gzip text path takes the same rule", {
  b <- c(gz_of("a,b\n1,2\n"), raw(4))
  junk <- c(gz_of("a\n1\n"), charToRaw("garbage"))
  expect_identical(.rmd_lines(b), c("a,b", "1,2"))
  expect_identical(.rmd_csv_bytes(b), data.frame(a = 1L, b = 2L))
  expect_error(.rmd_lines(junk), "after the last gzip member")
  expect_error(.rmd_csv_bytes(junk), "after the last gzip member")
  expect_error(.rmd_read_hosted(junk), "after the last gzip member")
  # text that itself starts as gzip does is read once, as text
  x <- c(as.raw(c(0x1f, 0x8b)), charToRaw(",b\n1,2\n"))
  con <- .rmd_textcon(gz_of(x))
  got <- readLines(con)
  close(con)
  expect_identical(got[1:2], c(rawToChar(x[1:4]), "1,2"))
})

test_that("a hosted table with bytes after its gzip data is never read as data", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  served <- NULL
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    if (path == "/manifest.json") {
      writeLines(sprintf('{"datasets":[{"key":"db/t","sha256_gz":"%s"}]}',
                         .Call(C_morie_core_sha256, served)), dest)
    } else {
      writeBin(served, dest)
    }
    invisible(dest)
  })
  dest <- .rmd_host_file("db/t")
  # padded with zeros: the table, and the copy stays
  served <- c(gz_of("a\nx\ny\n"), raw(16))
  expect_identical(hostload("db/t")$a, c("x", "y"))
  expect_true(file.exists(dest))
  # text after it: refused, not a row; the verified copy is not deleted for it
  served <- c(gz_of("a\nx\ny\n"), charToRaw("garbage"))
  expect_error(hostload("db/t", refresh = TRUE),
               "7 bytes after the last gzip member .* the copy was left in place")
  expect_true(file.exists(dest))
})
