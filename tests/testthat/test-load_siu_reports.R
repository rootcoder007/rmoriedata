
test_that("the csv bundle is the corpus and the parquet copy matches it", {
  d <- load_siu_reports()
  cat <- utils::read.csv(system.file("extdata", "_catalog.csv", package = "rmoriedata"))
  expect_equal(nrow(d), cat$n_rows[cat$slug == "siu_directors_reports"])
  expect_identical(d, load_siu_reports(format = "csv"))
  expect_identical(load_siu_reports(format = "parquet"), d)
})

test_that("each report names its subject officials' service, once per language", {
  d <- load_siu_reports()
  expect_true(all(nzchar(d$police_service)))
  expect_false(anyDuplicated(paste(d$drid, d[["_language"]])) > 0L)
  expect_setequal(unique(d[["_language"]]), c("en", "fr"))
})
