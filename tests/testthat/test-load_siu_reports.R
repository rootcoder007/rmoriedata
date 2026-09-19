
test_that("the csv bundle is the corpus and the parquet copy matches it", {
  d <- load_siu_reports()
  expect_equal(nrow(d), 5157L)
  expect_identical(d, load_siu_reports(format = "csv"))
  expect_identical(load_siu_reports(format = "parquet"), d)
})
