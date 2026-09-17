
test_that("the retired parquet bundle is refused, the csv bundle is the corpus", {
  expect_error(load_siu_reports(format = "parquet"), "retired")
  d <- load_siu_reports()
  expect_equal(nrow(d), 5157L)
  expect_identical(d, load_siu_reports(format = "csv"))
})
