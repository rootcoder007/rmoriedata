# ask() hands the question to rmoriebricklayer::bricklayer_llm_ask(), which
# takes a language model the user brings (a provider's key, Ollama, an
# endpoint of their own). The model call is replaced here; nothing leaves the
# machine.

test_that("ask() rejects a bad question, model or route before asking anything", {
  expect_error(ask("q", route = NA_character_), "route")
  expect_error(ask("q", route = c("a", "b")), "route")
  expect_error(ask("q", model = ""), "model")
  expect_error(ask("   "), "question")
})

test_that("ask() sends the catalogue and both packages' help, on the route asked for", {
  seen <- NULL
  testthat::local_mocked_bindings(
    bricklayer_llm_ask = function(prompt, model = NULL, timeout = 120,
                                  system_prompt = NULL, route = NULL, docs = TRUE,
                                  packages = NULL) {
      seen <<- list(prompt = prompt, model = model, system_prompt = system_prompt,
                    route = route, docs = docs, packages = packages)
      "pong"
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(ask("which datasets cover Toronto?", model = "qwen3:8b",
                       route = "ollama"), "pong")
  expect_identical(seen$prompt, "which datasets cover Toronto?")
  expect_identical(seen$model, "qwen3:8b")
  expect_identical(seen$route, "ollama")
  expect_true(seen$docs)
  expect_identical(seen$packages, c("rmoriedata", "rmoriebricklayer"))
  # the catalogue itself goes with the question, so the model can name tables
  expect_match(seen$system_prompt, "siu_directors_reports: table", fixed = TRUE)
  expect_match(seen$system_prompt, "morie_data_load(", fixed = TRUE)
  ask("hello")
  expect_null(seen$route)
  expect_null(seen$model)
})

test_that("ask() works with an older rmoriebricklayer that has no help tools", {
  seen <- NULL
  testthat::local_mocked_bindings(
    bricklayer_llm_ask = function(prompt, model = NULL, timeout = 120,
                                  system_prompt = NULL) {
      seen <<- list(prompt = prompt, system_prompt = system_prompt)
      "old pong"
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(ask("hello", route = "ollama"), "old pong")
  expect_match(seen$system_prompt, "rmoriedata", fixed = TRUE)
})

test_that("ask() turns a failure into a sentence, not an error", {
  testthat::local_mocked_bindings(
    bricklayer_llm_ask = function(...) stop("Anthropic rejected your key (HTTP 401)"),
    .package = "rmoriebricklayer"
  )
  out <- ask("hello")
  expect_match(out, "^The language model could not answer: ")
  expect_match(out, "rejected your key (HTTP 401)", fixed = TRUE)
})

test_that("with no route set up, ask() says what to set up and reaches nothing", {
  skip_if_not("docs" %in% names(formals(rmoriebricklayer::bricklayer_llm_ask)))
  ps <- rmoriebricklayer::bricklayer_llm_providers()
  vars <- c(ps$key_env, "MORIE_LLM_BASE_URL", "MORIE_LLM_ROUTE")
  withr::local_envvar(c(stats::setNames(rep(NA_character_, length(vars)), vars),
                        OLLAMA_HOST = "off", XDG_CONFIG_HOME = withr::local_tempdir()))
  out <- ask("hello")
  expect_match(out, "No language-model route is set up", fixed = TRUE)
  expect_match(out, "ANTHROPIC_API_KEY", fixed = TRUE)
})

test_that("a dictionary slug is redirected to morie_data_dictionary()", {
  cat <- morie_data_catalog()
  d <- cat$slug[cat$kind == "dictionary"]
  skip_if(length(d) == 0L)
  expect_error(morie_data_load(d[1]), "morie_data_dictionary", fixed = TRUE)
  expect_error(morie_data_load("no-such-slug-xyz"), "valid slugs", fixed = TRUE)
})

test_that("morie_data_llm_config() forwards to rmoriebricklayer when it can", {
  if ("bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
    withr::local_envvar(XDG_CONFIG_HOME = withr::local_tempdir(), MORIE_LLM_ROUTE = NA)
    morie_data_llm_config(route = "ollama")
    tab <- morie_data_llm_config()
    expect_identical(tab$value[tab$key == "route"], "ollama")
  } else {
    expect_error(morie_data_llm_config(), "0.5.11 or later")
  }
})
