# morie_data_hosted_login() hands the terms and who-is-asking arguments to
# rmoriebricklayer, which asks for whatever is not given before a new key is issued.
test_that("morie_data_hosted_login passes the terms and profile arguments through", {
  seen <- NULL
  testthat::local_mocked_bindings(
    bricklayer_llm_login = function(...) {
      seen <<- list(...)
      invisible("sk-k")
    },
    .package = "rmoriebricklayer")
  key <- morie_data_hosted_login(
    open_browser = FALSE, accept_terms = TRUE, name = "Ada Lovelace",
    purpose = "Course project on court delays in Ontario.", restricted = TRUE,
    supervisor_name = "Dr B", supervisor_role = "chair",
    supervisor_email = "b@uni.example")
  expect_identical(key, "sk-k")
  expect_true(seen$accept_terms)
  expect_identical(seen[c("name", "supervisor_role", "supervisor_email")],
                   list(name = "Ada Lovelace", supervisor_role = "chair",
                        supervisor_email = "b@uni.example"))
})
