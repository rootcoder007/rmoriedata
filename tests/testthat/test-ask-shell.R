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
  f(log)
}

test_that("ask() delivers the whole question as one argument, parentheses and all", {
  with_stub_bin(function(log) {
    marker <- tempfile("never")
    q <- sprintf("mean of (1:10); touch %s", marker)
    expect_identical(ask(q), "ok")
    argv <- readLines(log)
    expect_identical(argv[1:3], c("agent", "--backend", "auto"))
    expect_length(argv, 4L)
    expect_match(argv[4], "(rmoriedata)", fixed = TRUE)
    expect_match(argv[4], q, fixed = TRUE)
    expect_false(file.exists(marker))
  })
})

test_that("ask() passes model and backend through quoted", {
  with_stub_bin(function(log) {
    ask("hello world", model = "gpt-4o mini", backend = "ollama")
    argv <- readLines(log)
    expect_identical(argv[3:5], c("ollama", "-m", "gpt-4o mini"))
    expect_length(argv, 6L)
  })
})

test_that("ask() rejects bad model and backend before touching the shell", {
  expect_error(ask("q", backend = NA_character_), "backend")
  expect_error(ask("q", backend = c("a", "b")), "backend")
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
