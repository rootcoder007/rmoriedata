# SPDX-License-Identifier: AGPL-3.0-or-later

#' Ask a language model about the bundled datasets
#'
#' Sends a question through \code{rmoriebricklayer::bricklayer_llm_ask()},
#' to a language model you bring: an OpenAI-compatible endpoint of your own,
#' a provider whose key is set (OpenAI, Anthropic, Google Gemini, OpenRouter,
#' Groq, Mistral and more: \code{rmoriebricklayer::bricklayer_llm_providers()}),
#' or an Ollama server. Nothing is sent anywhere you did not set up.
#' The model is given every function of rmoriedata and rmoriebricklayer and
#' tools to read their help, and this package's catalogue of datasets, so it
#' can name the tables and write the code that loads them.
#' \code{rmoriebricklayer::bricklayer_llm_status()} shows which route would
#' answer; \code{\link{morie_data_llm_config}()} (or \code{rmbl config setup}
#' from the shell) saves a provider's key, the route and the model.
#'
#' @param question Character scalar.
#' @param model Optional model name; the route's model when \code{NULL}.
#' @param route \code{NULL} or \code{"auto"} (the first route that is set up),
#'   \code{"own"}, \code{"ollama"} or a provider id such as
#'   \code{"anthropic"} (that route only).
#' @return Character scalar: the answer, or a sentence saying what went wrong
#'   or what to set up (never an error, so a script keeps going).
#' @examples
#' \dontrun{
#' # These need a language model: a provider's key, Ollama, or your own server.
#' Sys.setenv(ANTHROPIC_API_KEY = "...")
#' ask("which bundled datasets cover Toronto police use-of-force?")
#' ask("summarise the SIU director's-report corpus", route = "ollama",
#'     model = "qwen3:8b")
#' }
#'
#' # With no route set up the call returns a setup hint, not an error, and
#' # reaches no network:
#' if (requireNamespace("rmoriebricklayer", quietly = TRUE)) {
#'   old <- Sys.getenv(c("OLLAMA_HOST", "MORIE_LLM_BASE_URL"), unset = NA)
#'   Sys.setenv(OLLAMA_HOST = "off", MORIE_LLM_BASE_URL = "off")
#'   if (!nrow(subset(rmoriebricklayer::bricklayer_llm_status(),
#'                    status %in% c("key set", "configured")))) {
#'     cat(ask("hello"))
#'   }
#'   for (v in names(old)) {
#'     if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v]))
#'   }
#' }
#' @export
ask <- function(question, model = NULL, route = NULL) {
  .rmoriedata_scalar(question, "question")
  if (!is.null(model)) .rmoriedata_scalar(model, "model")
  if (!is.null(route)) .rmoriedata_scalar(route, "route")
  # the catalogue itself, so the model can name tables rather than guess
  cat_tbl <- tryCatch(morie_data_catalog(), error = function(e) NULL)
  rows <- if (is.null(cat_tbl)) character() else
    ifelse(is.na(cat_tbl$n_rows), "-",
           format(cat_tbl$n_rows, big.mark = ",", trim = TRUE))
  listing <- if (is.null(cat_tbl) || !nrow(cat_tbl)) "" else paste0(
    " The bundled catalogue (slug: kind, rows): ",
    paste(sprintf("%s: %s, %s", cat_tbl$slug, cat_tbl$kind, rows), collapse = "; "),
    ". Load one with morie_data_load(\"<slug>\"); morie_data_hosted_catalog() ",
    "lists the tables at data.rmorie.com (they need the data key: ",
    "morie_data_hosted_login()).")
  system_prompt <- paste0(
    "You are helping explore the datasets bundled in rmoriedata. Name the tables ",
    "from the catalogue that answer the question, and only those.",
    listing
  )
  f <- rmoriebricklayer::bricklayer_llm_ask
  args <- list(question, model = model, system_prompt = system_prompt)
  have <- names(formals(f))
  if ("route" %in% have) args$route <- route
  if ("docs" %in% have) {
    # rmoriebricklayer 0.5.12 and later: the model reads both packages' help
    args$docs <- TRUE
    args$packages <- c("rmoriedata", "rmoriebricklayer")
  }
  tryCatch(
    do.call(f, args),
    # a refused key, a model the route does not have or no network reads as a
    # sentence, never as an error: an example or a script keeps going
    error = function(e) {
      paste0("The language model could not answer: ", conditionMessage(e))
    }
  )
}

# A non-NA, non-blank character scalar, or an error naming the argument.
.rmoriedata_scalar <- function(x, what) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) {
    stop(sprintf("`%s` must be a single non-empty string.", what),
         call. = FALSE)
  }
  invisible(TRUE)
}

#' Show or save the language-model settings
#'
#' The route \code{\link{ask}()} takes and the address, key and model of each
#' route (your own OpenAI-compatible server, each provider such as Anthropic or
#' OpenAI, a local or LAN Ollama server), shared with \pkg{rmoriebricklayer},
#' \pkg{rmorie} and
#' the Python package morie. A thin front to
#' \code{rmoriebricklayer::bricklayer_llm_config()}, which saves them in
#' \code{~/.config/morie/llm.json} only when you pass a setting; from the
#' shell, \code{rmbl config} and \code{rmbl config setup} do the same.
#'
#' @param ... Settings as \code{key = value}, e.g. \code{route = "anthropic"},
#'   \code{anthropic.key = "..."}, \code{anthropic.model = "claude-opus-5-5"},
#'   \code{ollama.url = "http://192.168.1.20:11434"},
#'   \code{own.url = "http://localhost:1234/v1"}; \code{NULL} removes one.
#'   With no arguments nothing is written.
#' @return A data frame with one row per setting (\code{key}, \code{value},
#'   \code{source}, \code{env}, \code{help}).
#' @examples
#' if ("bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
#'   morie_data_llm_config()   # reading writes nothing
#' }
#' \dontrun{
#' morie_data_llm_config(route = "anthropic", anthropic.model = "claude-opus-5-5")
#' morie_data_llm_config(route = NULL)   # back to the automatic order
#' }
#' @export
morie_data_llm_config <- function(...) {
  if (!"bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
    stop("saving language-model settings needs rmoriebricklayer 0.5.11 or later: ",
         "install.packages(\"rmoriebricklayer\", repos = ",
         "c(\"https://rootcoder007.r-universe.dev\", \"https://cloud.r-project.org\"))",
         call. = FALSE)
  }
  f <- getExportedValue("rmoriebricklayer", "bricklayer_llm_config")
  f(...)
}
