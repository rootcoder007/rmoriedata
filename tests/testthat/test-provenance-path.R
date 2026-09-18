test_that("morie_data_checksums paths resolve and are unique", {
  ck <- morie_data_checksums()
  skip_if(nrow(ck) == 0L)
  ed <- system.file("extdata", package = "rmoriedata")
  expect_true(all(file.exists(file.path(ed, ck$path))))
  expect_false(anyDuplicated(ck$path) > 0L)
  expect_identical(ck$file, basename(ck$path))
  v <- morie_data_verify()
  expect_true(all(v$path %in% ck$path))
})

test_that("ask rejects NA like it rejects empty and NULL", {
  expect_error(ask(NA_character_))
  expect_error(ask(""))
  expect_error(ask(NULL))
})
