# Every table ships twice, CSV and Parquet; the two copies must be the
# same typed frame, and the Parquet path is what Python reads.

test_that("the Parquet copy of every table equals the CSV copy", {
  cat <- mdcat()
  t <- cat[cat$kind == "table", ]
  expect_true(all(nzchar(t$parquet_path)))
  for (slug in t$slug) {
    a <- mdload(slug, refresh = TRUE)
    b <- mdload(slug, refresh = TRUE, format = "parquet")
    expect_identical(dim(b), dim(a), label = slug)
    expect_identical(names(b), names(a), label = slug)
    expect_identical(vapply(b, function(z) class(z)[1L], ""),
                     vapply(a, function(z) class(z)[1L], ""), label = slug)
    expect_equal(b, a, ignore_attr = TRUE, label = slug)
  }
})

test_that("mdpath resolves both copies through the signed manifest", {
  slug <- mdcat()$slug[mdcat()$kind == "table"][1]
  p <- mdpath(slug)
  expect_true(file.exists(p))
  expect_match(p, "\\.parquet$")
  expect_true(file.exists(mdpath(slug, "csv")))
  m <- mdverify()
  expect_true(all(mdcat()$parquet_path[
    mdcat()$kind == "table"] %in% m$path))
  expect_error(mdpath("no-such-slug"), "valid slugs")
  expect_error(mdpath(NA_character_), "slug")
})

test_that("the SIU corpus reads the same from Parquet and CSV", {
  a <- siuload()
  b <- siuload(format = "parquet")
  expect_identical(b, a)
  expect_identical(nrow(siuload("en", format = "parquet")),
                   nrow(siuload("en")))
})
