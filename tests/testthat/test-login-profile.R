# hostlogin() hands the terms and who-is-asking arguments to
# rmoriebricklayer, which asks for whatever is not given before a new key is issued.
test_that("hostlogin passes the terms and profile arguments through", {
  skip_if_old_bricklayer()
  seen <- NULL
  testthat::local_mocked_bindings(
    dlogin = function(...) {
      seen <<- list(...)
      invisible("sk-k")
    },
    .package = "rmoriebricklayer")
  key <- hostlogin(
    openbro = FALSE, accept_terms = TRUE, name = "Ada Lovelace",
    purpose = "Course project on court delays in Ontario.", restricted = TRUE,
    supervisor_name = "Dr B", supervisor_role = "chair",
    supervisor_email = "b@uni.example")
  expect_identical(key, "sk-k")
  expect_true(seen$accept_terms)
  expect_identical(seen[c("name", "supervisor_role", "supervisor_email")],
                   list(name = "Ada Lovelace", supervisor_role = "chair",
                        supervisor_email = "b@uni.example"))
})
