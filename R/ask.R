# SPDX-License-Identifier: AGPL-3.0-or-later

#' Ask a language model about the bundled datasets
#'
#' Sends a dataset-focused question through
#' \code{rmoriebricklayer::bricklayer_llm_ask()}, which takes the first
#' language-model route that answers: an OpenAI-compatible endpoint of your
#' own (\code{MORIE_LLM_BASE_URL}), a local Ollama server, then the hosted
#' MORIE tier as a last resort, with the key that
#' \code{\link{morie_data_hosted_login}()} stores (the same key opens the
#' curated tables; keys are issued on request at
#' \url{https://www.rmorie.com/access/}).
#' \code{rmoriebricklayer::bricklayer_llm_status()} shows which route would
#' answer and \code{rmoriebricklayer::bricklayer_llm_models()} what the hosted
#' key may use. With \code{backend = "cli"} the question goes to the optional
#' \code{rmorie} command-line agent instead, as before.
#'
#' A stored hosted key is used whenever neither your own endpoint nor a local
#' Ollama server with a model pulled is there: a running Ollama with nothing
#' pulled no longer stops the call. To choose the route or the model once and
#' for all, use \code{\link{morie_data_llm_config}()} (or \code{rmbl config}
#' from the shell).
#'
#' @param question Character scalar.
#' @param model Optional model id, e.g. \code{"gpt-oss-120b:cf"}; the tier's
#'   default when \code{NULL}.
#' @param backend \code{"auto"} (the first route \pkg{rmoriebricklayer} finds,
#'   else the \code{rmorie} binary), \code{"hosted"} (the hosted tier only),
#'   \code{"ollama"} or \code{"own"} (that route only), or
#'   \code{"cli"} (the \code{rmorie} binary's agent, with its own fallback
#'   chain).
#' @return Character scalar: the answer, or a sentence saying what to set up
#'   when no route answers and the \code{rmorie} binary is not available.
#' @examples
#' \dontrun{
#' # These need a stored key (morie_data_hosted_login()) or the rmorie binary.
#' # After morie_data_hosted_login(): the hosted tier answers.
#' ask("which bundled datasets cover Toronto police use-of-force?")
#'
#' # Pin one of the additional AI models.
#' ask("summarise the SIU director's-report corpus", model = "gpt-oss-120b:cf")
#'
#' # Ask through the rmorie command-line agent.
#' ask("list the Chicago datasets", backend = "cli")
#' }
#'
#' # With every route switched off and no rmorie binary on PATH the call
#' # returns a setup hint, not an error, and reaches no network whatever
#' # key this machine has stored:
#' routes <- c("MORIE_HOSTED_BASE_URL", "OLLAMA_HOST", "MORIE_LLM_BASE_URL")
#' old <- Sys.getenv(routes, unset = NA)
#' Sys.setenv(MORIE_HOSTED_BASE_URL = "off", OLLAMA_HOST = "off",
#'            MORIE_LLM_BASE_URL = "off")
#' if (!nzchar(Sys.which("rmorie"))) ask("hello")
#' for (v in routes) {
#'   if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v]))
#' }
#' @export
ask <- function(question, model = NULL, backend = "auto") {
  .rmoriedata_scalar(question, "question")
  .rmoriedata_scalar(backend, "backend")
  if (!backend %in% c("auto", "hosted", "ollama", "own", "cli")) {
    stop("`backend` must be one of \"auto\", \"hosted\", \"ollama\", \"own\" or \"cli\"", call. = FALSE)
  }
  if (!is.null(model)) .rmoriedata_scalar(model, "model")
  # the catalogue itself, so the model can name tables rather than guess
  cat_tbl <- tryCatch(morie_data_catalog(), error = function(e) NULL)
  # one line: the shell route hands the prompt to the rmorie binary as one argument
  rows <- if (is.null(cat_tbl)) character() else
    ifelse(is.na(cat_tbl$n_rows), "-",
           format(cat_tbl$n_rows, big.mark = ",", trim = TRUE))
  listing <- if (is.null(cat_tbl) || !nrow(cat_tbl)) "" else paste0(
    " The bundled catalogue (slug: kind, rows): ",
    paste(sprintf("%s: %s, %s", cat_tbl$slug, cat_tbl$kind, rows), collapse = "; "),
    ". Load one with morie_data_load(\"<slug>\"); morie_data_hosted_catalog() ",
    "lists the hosted tables at data.rmorie.com.")
  system_prompt <- paste0(
    "You are helping explore the datasets bundled in the MORIE packages ",
    "(rmoriedata). Name the tables from the catalogue that answer the question.",
    listing
  )
  if (backend %in% c("auto", "hosted", "ollama", "own")) {
    st <- rmoriebricklayer::bricklayer_llm_status()
    # one row per route; an older bricklayer has the hosted row alone
    hosted_ok <- any(st$status[grepl("hosted", st$route)] == "key stored")
    own_ok <- any(st$status[grepl("own", st$route)] == "configured")
    ollama_ok <- any(st$status[grepl("Ollama", st$route)] == "available")
    ok <- switch(backend, hosted = hosted_ok, own = own_ok, ollama = ollama_ok,
                 hosted_ok || own_ok || ollama_ok)
    if (ok) {
      # a rejected key, a model nobody serves or no network must read as a
      # sentence, never as an error: an example or a script keeps going
      args <- list(question, model = model, system_prompt = system_prompt)
      # an older bricklayer has no `route`: there a route is a wish, not a constraint
      has_route <- "route" %in% names(formals(rmoriebricklayer::bricklayer_llm_ask))
      if (has_route && !identical(backend, "auto")) {
        args$route <- backend
      } else if (has_route && hosted_ok && !own_ok && !ollama_ok) {
        # rmoriebricklayer before 0.5.11 stopped at a running Ollama with no model
        # pulled ("local Ollama has no model to use") and never reached a stored
        # hosted key; when the hosted tier is the only route that can answer, say so
        args$route <- "hosted"
      }
      return(tryCatch(
        do.call(rmoriebricklayer::bricklayer_llm_ask, args),
        error = function(e) {
          paste0(
            "The language model could not answer (", conditionMessage(e),
            "). If the hosted key was rejected, run ",
            "morie_data_hosted_login(token = ) again."
          )
        }
      ))
    }
    if (identical(backend, "hosted")) {
      return(paste0(
        "No key for the hosted MORIE tier: run morie_data_hosted_login(token = ) ",
        "once; ", .rmd_access_hint(), "."
      ))
    }
    if (backend %in% c("ollama", "own")) {
      return(paste0(
        if (identical(backend, "ollama")) "No local Ollama with a model pulled (`ollama pull NAME`)"
        else "No endpoint of your own is set",
        ": see morie_data_llm_config() or `rmbl config setup`."
      ))
    }
  }
  bin <- Sys.which("rmorie")
  if (!nzchar(bin)) {
    return(paste0(
      "No language-model route is set up (no endpoint of your own, no local Ollama, ",
      "no hosted key) and no rmorie CLI on PATH: start a local model, ",
      "point at your own server with morie_data_llm_config(own.url = ), ",
      "or run morie_data_hosted_login(token = ) once; ", .rmd_access_hint(), "."
    ))
  }
  preamble <- paste0(system_prompt, " Question: ", question)
  # system2() hands `args` to a shell: quote every value, or the first
  # parenthesis in the request is a shell syntax error (and a ";" in the
  # question would run as a command).
  # the agent picks its own route (hosted tier, then a local Ollama): no backend flag
  args <- "agent"
  if (!is.null(model)) args <- c(args, "--model", shQuote(model))
  args <- c(args, shQuote(preamble))
  paste(suppressWarnings(
    system2(bin, args = args, stdout = TRUE, stderr = TRUE)
  ), collapse = "\n")
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
#' route (your own OpenAI-compatible server, a local or LAN Ollama server, the
#' hosted MORIE tier), shared with \pkg{rmoriebricklayer}, \pkg{rmorie} and
#' the Python package morie. A thin front to
#' \code{rmoriebricklayer::bricklayer_llm_config()}, which saves them in
#' \code{~/.config/morie/llm.json} only when you pass a setting; from the
#' shell, \code{rmbl config} and \code{rmbl config setup} do the same.
#'
#' @param ... Settings as \code{key = value}, e.g. \code{route = "hosted"},
#'   \code{hosted.model = "gpt-oss-120b:cf"},
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
#' morie_data_llm_config(route = "hosted", hosted.model = "gpt-oss-120b:cf")
#' morie_data_llm_config(route = NULL)   # back to the automatic order
#' }
#' @export
morie_data_llm_config <- function(...) {
  if (!"bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
    stop("saving language-model settings needs rmoriebricklayer 0.5.11 or later: ",
         "install.packages(\"rmoriebricklayer\", repos = c(\"https://rootcoder007.r-universe.dev\", ",
         "\"https://cloud.r-project.org\"))", call. = FALSE)
  }
  f <- getExportedValue("rmoriebricklayer", "bricklayer_llm_config")
  f(...)
}
