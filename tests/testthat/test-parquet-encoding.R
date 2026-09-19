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
})

test_that("the SIU corpus carries the same bytes from CSV and Parquet", {
  a <- load_siu_reports()
  b <- load_siu_reports(format = "parquet")
  i <- which(vapply(a[[1]], function(z) any(charToRaw(z) > 0x7f), TRUE))[1]
  skip_if(is.na(i))
  expect_identical(charToRaw(a[[1]][i]), charToRaw(b[[1]][i]))
})
