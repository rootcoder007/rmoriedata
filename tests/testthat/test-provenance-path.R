test_that("mdsums paths resolve and are unique", {
  ck <- mdsums()
  skip_if(nrow(ck) == 0L)
  ed <- system.file("extdata", package = "rmoriedata")
  expect_true(all(file.exists(file.path(ed, ck$path))))
  expect_false(anyDuplicated(ck$path) > 0L)
  expect_identical(ck$file, basename(ck$path))
  v <- mdverify()
  expect_true(all(v$path %in% ck$path))
})

test_that("ask rejects NA like it rejects empty and NULL", {
  expect_error(mdask(NA_character_))
  expect_error(mdask(""))
  expect_error(mdask(NULL))
})
