# Every table ships twice, CSV and Parquet; the two copies must be the
# same typed frame, and the Parquet path is what Python reads.

test_that("the Parquet copy of every table equals the CSV copy", {
  cat <- morie_data_catalog()
  t <- cat[cat$kind == "table", ]
  expect_true(all(nzchar(t$parquet_path)))
  for (slug in t$slug) {
    a <- morie_data_load(slug, refresh = TRUE)
    b <- morie_data_load(slug, refresh = TRUE, format = "parquet")
    expect_identical(dim(b), dim(a), label = slug)
    expect_identical(names(b), names(a), label = slug)
    expect_identical(vapply(b, function(z) class(z)[1L], ""),
                     vapply(a, function(z) class(z)[1L], ""), label = slug)
    expect_equal(b, a, ignore_attr = TRUE, label = slug)
  }
})

test_that("morie_data_path resolves both copies through the signed manifest", {
  slug <- morie_data_catalog()$slug[morie_data_catalog()$kind == "table"][1]
  p <- morie_data_path(slug)
  expect_true(file.exists(p))
  expect_match(p, "\\.parquet$")
  expect_true(file.exists(morie_data_path(slug, "csv")))
  m <- morie_data_verify()
  expect_true(all(morie_data_catalog()$parquet_path[
    morie_data_catalog()$kind == "table"] %in% m$path))
  expect_error(morie_data_path("no-such-slug"), "valid slugs")
  expect_error(morie_data_path(NA_character_), "slug")
})

test_that("the SIU corpus reads the same from Parquet and CSV", {
  a <- load_siu_reports()
  b <- load_siu_reports(format = "parquet")
  expect_identical(b, a)
  expect_identical(nrow(load_siu_reports("en", format = "parquet")),
                   nrow(load_siu_reports("en")))
})
