# ask() forwards to the CLI through system2(), which hands its
# arguments to a shell. A stub binary on PATH records what arrived and
# `f(log)` runs with the stub first on PATH.

with_stub_bin <- function(f) {
  testthat::skip_on_os("windows")
  dir <- tempfile("stubbin")
  dir.create(dir)
  log <- file.path(dir, "argv.txt")
  bin <- file.path(dir, "rmorie")
  writeLines(c("#!/bin/sh", paste0("printf '%s\\n' \"$@\" > '", log, "'"),
               "echo ok"), bin)
  Sys.chmod(bin, "0755")
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)
  Sys.setenv(PATH = paste(dir, old, sep = .Platform$path.sep))
  withr::local_envvar(MORIE_HOSTED_BASE_URL = "off")
  f(log)
}

test_that("ask() delivers the whole question as one argument, parentheses and all", {
  with_stub_bin(function(log) {
    marker <- tempfile("never")
    q <- sprintf("mean of (1:10); touch %s", marker)
    expect_identical(ask(q), "ok")
    argv <- readLines(log)
    expect_identical(argv[1], "agent")
    expect_length(argv, 2L)
    expect_match(argv[2], "(rmoriedata)", fixed = TRUE)
    expect_match(argv[2], q, fixed = TRUE)
    expect_match(argv[2], "Question: ", fixed = TRUE)
    expect_false(file.exists(marker))
  })
})

test_that("ask() passes the model through quoted, and no backend flag the agent lacks", {
  with_stub_bin(function(log) {
    ask("hello world", model = "gpt-4o mini", backend = "cli")
    argv <- readLines(log)
    expect_identical(argv[1:3], c("agent", "--model", "gpt-4o mini"))
    expect_length(argv, 4L)
    expect_false("--backend" %in% argv)
  })
})

test_that("ask() rejects bad model and backend before touching the shell", {
  expect_error(ask("q", backend = NA_character_), "backend")
  expect_error(ask("q", backend = c("a", "b")), "backend")
  expect_error(ask("q", backend = "cloud"),
               "\"auto\", \"hosted\", \"ollama\", \"own\" or \"cli\"")
  expect_error(ask("q", model = ""), "model")
  expect_error(ask("   "), "question")
})

test_that("a dictionary slug is redirected to morie_data_dictionary()", {
  cat <- morie_data_catalog()
  d <- cat$slug[cat$kind == "dictionary"]
  skip_if(length(d) == 0L)
  expect_error(morie_data_load(d[1]), "morie_data_dictionary", fixed = TRUE)
  expect_error(morie_data_load("no-such-slug-xyz"), "valid slugs", fixed = TRUE)
})

test_that("ask() uses the hosted MORIE tier when a key is stored, and names the model", {
  seen <- NULL
  testthat::local_mocked_bindings(
    bricklayer_llm_status = function() {
      data.frame(
        route = c("hosted MORIE tier", "rmorie-cli agent"),
        status = c("key stored", "absent"), detail = c("", ""),
        stringsAsFactors = FALSE
      )
    },
    bricklayer_llm_ask = function(prompt, model = NULL, timeout = 120,
                                  system_prompt = NULL) {
      seen <<- list(prompt = prompt, model = model, system_prompt = system_prompt)
      "pong"
    },
    .package = "rmoriebricklayer"
  )
  a <- ask("which datasets cover Toronto?", model = "gpt-oss-120b:cf")
  expect_identical(a, "pong")
  expect_identical(seen$model, "gpt-oss-120b:cf")
  expect_identical(seen$prompt, "which datasets cover Toronto?")
  expect_match(seen$system_prompt, "rmoriedata", fixed = TRUE)
  # the catalogue itself goes with the question, so the model can name tables
  expect_match(seen$system_prompt, "siu_directors_reports: table", fixed = TRUE)
  expect_match(seen$system_prompt, "morie_data_load(", fixed = TRUE)
  # backend = "hosted" with no key says how to sign in
  testthat::local_mocked_bindings(
    bricklayer_llm_status = function() {
      data.frame(
        route = "hosted MORIE tier", status = "not logged in", detail = "",
        stringsAsFactors = FALSE
      )
    },
    .package = "rmoriebricklayer"
  )
  expect_match(ask("hello", backend = "hosted"), "morie_data_hosted_login", fixed = TRUE)
})

test_that("ask() says how to sign in when neither a key nor the rmorie binary is there", {
  withr::local_envvar(MORIE_HOSTED_BASE_URL = "off", PATH = tempdir())
  expect_match(ask("hello"), "morie_data_hosted_login", fixed = TRUE)
})

test_that("ask() turns a hosted-tier failure into a sentence, not an error", {
  testthat::local_mocked_bindings(
    bricklayer_llm_status = function() {
      data.frame(
        route = "hosted MORIE tier", status = "key stored", detail = "",
        stringsAsFactors = FALSE
      )
    },
    bricklayer_llm_ask = function(prompt, model = NULL, timeout = 120,
                                  system_prompt = NULL) {
      stop("the hosted MORIE LLM tier answered 401: Authentication Error")
    },
    .package = "rmoriebricklayer"
  )
  out <- ask("hello")
  expect_match(out, "could not answer", fixed = TRUE)
  expect_match(out, "401", fixed = TRUE)
  expect_match(out, "morie_data_hosted_login", fixed = TRUE)
})

test_that("ask() reaches a stored hosted key past a running Ollama with no model", {
  seen <- NULL
  testthat::local_mocked_bindings(
    bricklayer_llm_status = function() {
      data.frame(
        route = c("own endpoint", "local Ollama", "hosted MORIE tier"),
        status = c("not set", "no models", "key stored"), detail = "",
        stringsAsFactors = FALSE
      )
    },
    bricklayer_llm_ask = function(prompt, model = NULL, timeout = 120,
                                  system_prompt = NULL, route = NULL) {
      seen <<- list(route = route)
      "pong"
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(ask("hello"), "pong")
  expect_identical(seen$route, "hosted")
  expect_identical(ask("hello", backend = "hosted"), "pong")
  expect_identical(seen$route, "hosted")
  # a route that is not there says what to set up, and reaches nothing
  seen <- NULL
  expect_match(ask("hello", backend = "ollama"), "ollama pull")
  expect_match(ask("hello", backend = "own"), "morie_data_llm_config")
  expect_null(seen)
  # with a model pulled, auto leaves the choice to rmoriebricklayer
  testthat::local_mocked_bindings(
    bricklayer_llm_status = function() {
      data.frame(
        route = c("own endpoint", "local Ollama", "hosted MORIE tier"),
        status = c("not set", "available", "key stored"), detail = "",
        stringsAsFactors = FALSE
      )
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(ask("hello"), "pong")
  expect_null(seen$route)
  expect_identical(ask("hello", backend = "ollama"), "pong")
  expect_identical(seen$route, "ollama")
})

test_that("morie_data_llm_config() forwards to rmoriebricklayer when it can", {
  if ("bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
    withr::local_envvar(XDG_CONFIG_HOME = withr::local_tempdir(), MORIE_LLM_ROUTE = NA)
    morie_data_llm_config(route = "hosted")
    tab <- morie_data_llm_config()
    expect_identical(tab$value[tab$key == "route"], "hosted")
  } else {
    expect_error(morie_data_llm_config(), "0.5.11 or later")
  }
})
