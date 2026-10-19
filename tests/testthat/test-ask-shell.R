# ask() hands the question to rmoriebricklayer::llmask(), which
# takes a language model the user brings (a provider's key, Ollama, an
# endpoint of their own). The model call is replaced here; nothing leaves the
# machine.

test_that("mdask() rejects a bad question, model or route before asking anything", {
  expect_error(mdask("q", route = NA_character_), "route")
  expect_error(mdask("q", route = c("a", "b")), "route")
  expect_error(mdask("q", model = ""), "model")
  expect_error(mdask("   "), "question")
})

test_that("mdask() sends the catalogue and both packages' help, on the route asked for", {
  seen <- NULL
  testthat::local_mocked_bindings(
    llmask = function(prompt, model = NULL, tmout = 120,
                                  syspro = NULL, route = NULL, docs = TRUE,
                                  pkgs = NULL) {
      seen <<- list(prompt = prompt, model = model, syspro = syspro,
                    route = route, docs = docs, packages = pkgs)
      "pong"
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(mdask("which datasets cover Toronto?", model = "qwen3:8b",
                       route = "ollama"), "pong")
  expect_identical(seen$prompt, "which datasets cover Toronto?")
  expect_identical(seen$model, "qwen3:8b")
  expect_identical(seen$route, "ollama")
  expect_true(seen$docs)
  expect_identical(seen$packages, c("rmoriedata", "rmoriebricklayer"))
  # the catalogue itself goes with the question, so the model can name tables
  expect_match(seen$syspro, "siu_directors_reports: table", fixed = TRUE)
  expect_match(seen$syspro, "mdload(", fixed = TRUE)
  mdask("hello")
  expect_null(seen$route)
  expect_null(seen$model)
})

test_that("mdask() works with an older rmoriebricklayer that has no help tools", {
  seen <- NULL
  testthat::local_mocked_bindings(
    llmask = function(prompt, model = NULL, tmout = 120,
                                  syspro = NULL) {
      seen <<- list(prompt = prompt, syspro = syspro)
      "old pong"
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(mdask("hello", route = "ollama"), "old pong")
  expect_match(seen$syspro, "rmoriedata", fixed = TRUE)
})

test_that("mdask() turns a failure into a sentence, not an error", {
  testthat::local_mocked_bindings(
    llmask = function(...) stop("Anthropic rejected your key (HTTP 401)"),
    .package = "rmoriebricklayer"
  )
  out <- mdask("hello")
  expect_match(out, "^The language model could not answer: ")
  expect_match(out, "rejected your key (HTTP 401)", fixed = TRUE)
})

test_that("with no route set up, mdask() says what to set up and reaches nothing", {
  skip_if_not("docs" %in% names(formals(rmoriebricklayer::llmask)))
  ps <- rmoriebricklayer::llmprvd()
  vars <- c(ps$key_env, "MORIE_LLM_BASE_URL", "MORIE_LLM_ROUTE")
  withr::local_envvar(c(stats::setNames(rep(NA_character_, length(vars)), vars),
                        OLLAMA_HOST = "off", XDG_CONFIG_HOME = withr::local_tempdir()))
  out <- mdask("hello")
  expect_match(out, "No language-model route is set up", fixed = TRUE)
  expect_match(out, "ANTHROPIC_API_KEY", fixed = TRUE)
})

test_that("a dictionary slug is redirected to mddict()", {
  cat <- mdcat()
  d <- cat$slug[cat$kind == "dictionary"]
  skip_if(length(d) == 0L)
  expect_error(mdload(d[1]), "mddict", fixed = TRUE)
  expect_error(mdload("no-such-slug-xyz"), "valid slugs", fixed = TRUE)
})

test_that("mdllmconf() forwards to rmoriebricklayer when it can", {
  if ("llmcfg" %in% getNamespaceExports("rmoriebricklayer")) {
    withr::local_envvar(XDG_CONFIG_HOME = withr::local_tempdir(), MORIE_LLM_ROUTE = NA)
    mdllmconf(route = "ollama")
    tab <- mdllmconf()
    expect_identical(tab$value[tab$key == "route"], "ollama")
  } else {
    expect_error(mdllmconf(), "0.5.11 or later")
  }
})
