# Round-7 stress-test findings (2026-10-04): each test pins one fix.

test_that("chiload caps the bundled sample with limit and fraction", {
  all <- chiload("arrests")
  expect_identical(nrow(chiload("arrests", limit = 10)), 10L)
  expect_identical(chiload("arrests", limit = 10), all[1:10, , drop = FALSE])
  expect_identical(nrow(chiload("arrests", fraction = 0.5)),
                   as.integer(ceiling(nrow(all) * 0.5)))
  expect_identical(nrow(chiload("arrests", limit = 10^9)), nrow(all))
  expect_error(chiload("arrests", limit = 1, fraction = 0.5), "not both")
})

test_that("as = 'tibble' without tibble says it returns a data.frame", {
  local_mocked_bindings(requireNamespace = function(package, ...) package != "tibble",
                        .package = "base")
  expect_message(x <- chiload("arrests", limit = 3, as = "tibble"),
                 "tibble package is not installed")
  expect_identical(class(x), "data.frame")
  expect_message(y <- siuload(as = "tibble"), "tibble package is not installed")
  expect_identical(class(y), "data.frame")
})

test_that("a dictionary slug has a path; the catalogue flags synthetic tables", {
  p <- mdpath("arsau_2020_2022_dictionary")
  expect_true(file.exists(p))
  expect_match(p, "arsau_2020_2022_dictionary\\.json$")
  expect_identical(mdpath("arsau_2020_2022_dictionary", format = "csv"), p)
  cl <- mdcat()
  expect_type(cl$synthetic, "logical")
  expect_true(all(cl$synthetic[cl$kind == "table" & grepl("^arsau_", cl$slug)]))
  expect_false(any(cl$synthetic[cl$kind != "table"]))
  expect_true(cl$synthetic[cl$slug == "nibrs_synthetic"])
  expect_false(cl$synthetic[cl$slug == "chicago_iucr_codes"])
})

test_that("hostcat refuses a refresh that is not TRUE or FALSE", {
  for (bad in list(NULL, "abc", data.frame(), NA, c(TRUE, FALSE))) {
    expect_error(hostcat(bad), "`refresh` must be TRUE or FALSE")
  }
})
