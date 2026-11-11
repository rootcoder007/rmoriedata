# hostlogin() hands the terms and who-is-asking arguments to
# rmoriebricklayer, which asks for whatever is not given before a new key is issued.
test_that("hostlogin passes the terms and profile arguments through", {
  skip_if_old_bricklayer()
  seen <- NULL
  # the argument names dlogin() really has, read before it is mocked
  real <- names(formals(rmoriebricklayer::dlogin))
  testthat::local_mocked_bindings(
    dlogin = function(...) {
      seen <<- list(...)
      invisible("sk-k")
    },
    .package = "rmoriebricklayer")
  key <- hostlogin(
    openbro = FALSE, accter = TRUE, name = "Ada Lovelace",
    purp = "Course project on court delays in Ontario.", restr = TRUE,
    supnm = "Dr B", suprole = "chair",
    supemail = "b@uni.example")
  expect_identical(key, "sk-k")
  expect_true(seen$accter)
  expect_identical(seen[c("name", "suprole", "supemail")],
                   list(name = "Ada Lovelace", suprole = "chair",
                        supemail = "b@uni.example"))
  # every name passed on, and every name the help page lists, is one dlogin() takes
  expect_identical(setdiff(names(seen), real), character())
  expect_identical(
    setdiff(c("accter", "name", "affil", "purp", "restr", "supnm", "suprole", "supemail"),
            real),
    character())
})
