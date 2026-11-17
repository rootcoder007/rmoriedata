# SPDX-License-Identifier: AGPL-3.0-or-later

#' Ask a language model about the bundled datasets
#'
#' Sends a question through \code{rmoriebricklayer::llmask()},
#' to a language model you bring: an OpenAI-compatible endpoint of your own,
#' a provider whose key is set (OpenAI, Anthropic, Google Gemini, OpenRouter,
#' Groq, Mistral and more: \code{rmoriebricklayer::llmprvd()}),
#' or an Ollama server. Nothing is sent anywhere you did not set up. An
#' Ollama server is asked only when you chose one: \code{route = "ollama"},
#' an \code{OLLAMA_HOST}, \code{OLLAMA_BASE_URL}, \code{OLLAMA_MODEL} or
#' \code{OLLAMA_API_KEY} environment variable, or an \code{ollama.*} setting
#' or \code{route = "ollama"} saved with \code{\link{mdllmconf}()}. Without
#' any of these, an Ollama server that happens to run on this machine (at
#' \code{localhost:11434}) is neither probed nor sent the question.
#' The model is given every function of rmoriedata and rmoriebricklayer and
#' tools to read their help, and this package's catalogue of datasets, so it
#' can name the tables and write the code that loads them.
#' \code{rmoriebricklayer::llmstat()} shows which route would
#' answer; \code{\link{mdllmconf}()} (or \code{rmbl config setup}
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
#' mdask("which bundled datasets cover Toronto police use-of-force?")
#' mdask("summarise the SIU director's-report corpus", route = "ollama",
#'     model = "qwen3:8b")
#' }
#'
#' # With no route set up the call returns a setup hint, not an error, and
#' # reaches no network:
#' if ("llmstat" %in% getNamespaceExports("rmoriebricklayer")) {
#'   old <- Sys.getenv(c("OLLAMA_HOST", "MORIE_LLM_BASE_URL"), unset = NA)
#'   Sys.setenv(OLLAMA_HOST = "off", MORIE_LLM_BASE_URL = "off")
#'   if (!nrow(subset(rmoriebricklayer::llmstat(),
#'                    status %in% c("key set", "configured")))) {
#'     cat(mdask("hello"))
#'   }
#'   for (v in names(old)) {
#'     if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v]))
#'   }
#' }
#' @export
mdask <- function(question, model = NULL, route = NULL) {
  .rmd_bounds()
  .rmoriedata_scalar(question, "question")
  if (!is.null(model)) .rmoriedata_scalar(model, "model")
  if (!is.null(route)) .rmoriedata_scalar(route, "route")
  # the catalogue itself, so the model can name tables rather than guess
  cat_tbl <- tryCatch(mdcat(), error = function(e) NULL)
  rows <- if (is.null(cat_tbl)) character() else
    ifelse(is.na(cat_tbl$n_rows), "-", .rmd_count_txt(cat_tbl$n_rows))
  listing <- if (is.null(cat_tbl) || !nrow(cat_tbl)) "" else paste0(
    " The bundled catalogue (slug: kind, rows): ",
    paste(sprintf("%s: %s, %s", cat_tbl$slug, cat_tbl$kind, rows), collapse = "; "),
    ". Load one with mdload(\"<slug>\"); hostcat() ",
    "lists the tables at data.rmorie.com and hostload(\"db/table\") ",
    "opens one (no sign-in).")
  system_prompt <- paste0(
    "You are helping explore the datasets bundled in rmoriedata. Name the tables ",
    "from the catalogue that answer the question, and only those.",
    listing
  )
  f <- .rmd_bl("llmask")
  # rmoriebricklayer's automatic route probes localhost:11434 and sends the question
  # to any Ollama found there; it is left out unless the user chose Ollama
  if ((is.null(route) || identical(route, "auto")) && !.rmd_ollama_chosen()) {
    old <- Sys.getenv("OLLAMA_HOST", unset = NA)
    Sys.setenv(OLLAMA_HOST = "off")
    on.exit(if (is.na(old)) {
      Sys.unsetenv("OLLAMA_HOST")
    } else {
      Sys.setenv(OLLAMA_HOST = old)
    }, add = TRUE)
  }
  args <- list(question, model = model, syspro = system_prompt)
  have <- names(formals(f))
  if ("route" %in% have) args$route <- route
  if ("docs" %in% have) {
    # rmoriebricklayer 0.5.12 and later: the model reads both packages' help
    args$docs <- TRUE
    args$pkgs <- c("rmoriedata", "rmoriebricklayer")
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

# Whether the user chose an Ollama server: an OLLAMA_* variable, or an ollama
# setting (or the route "ollama") saved through llmcfg(). The variables are read
# here as rmoriebricklayer reads them.
.rmd_ollama_chosen <- function() {
  env <- Sys.getenv(c("OLLAMA_HOST", "OLLAMA_BASE_URL", "OLLAMA_MODEL", "OLLAMA_API_KEY"))
  if (any(nzchar(trimws(env)))) return(TRUE)
  if (!"llmcfg" %in% .rmd_bl_exports()) return(FALSE)
  cfg <- tryCatch(.rmd_bl_get("llmcfg")(), error = function(e) NULL)
  if (!is.data.frame(cfg) || !all(c("key", "value", "source") %in% names(cfg))) {
    return(FALSE)
  }
  set <- cfg$source != "default"
  any(set & (startsWith(cfg$key, "ollama.") |
               (cfg$key == "route" & .rmd_lower(cfg$value) == "ollama")))
}

# Whole counts with a comma every three digits, "1,234,567", whatever
# options(OutDec = ) says: format(big.mark = ",") warned, and under warn = 2 stopped,
# when OutDec was "," too.
.rmd_count_txt <- function(n) {
  formatC(as.integer(n), format = "d", big.mark = ",", decimal.mark = ".")
}

# A non-NA, non-blank character scalar, or an error naming the argument.
.rmoriedata_scalar <- function(x, what) {
  if (!is.character(x) || length(x) != 1L || is.na(x)) {
    stop(sprintf("`%s` must be a single non-empty string.", what),
         call. = FALSE)
  }
  .rmd_nobytes(x, what)
  if (!nzchar(trimws(x))) {
    stop(sprintf("`%s` must be a single non-empty string.", what),
         call. = FALSE)
  }
  invisible(TRUE)
}

# Strings marked "bytes" (Encoding()) cannot be compared with names or titles:
# base R stops with "translating strings with \"bytes\" encoding is not allowed".
# Refused here in words, naming the argument.
.rmd_nobytes <- function(x, what) {
  if (is.character(x) && any(Encoding(x) == "bytes")) {
    stop(sprintf(paste0("`%s` holds a string marked as \"bytes\", which cannot be ",
                        "compared with names; mark its encoding first, for example ",
                        "Encoding(x) <- \"UTF-8\" or iconv(x, \"latin1\", \"UTF-8\")"),
                 what), call. = FALSE)
  }
  # bytes that are not text in the session's encoding failed in sub() or
  # grepl() in base R's words ("input string 1 is invalid")
  if (is.character(x) && !all(validEnc(x[!is.na(x)]))) {
    stop(sprintf("`%s` holds text that is not valid in this session's encoding",
                 what), call. = FALSE)
  }
  invisible(TRUE)
}

# One of an argument's choices, as match.arg() gives it (the default vector
# or NULL picks the first; a unique prefix matches), refused in words:
# match.arg() said "'arg' must be of length 1" for character(0) and "'arg'
# must be NULL or a character vector" for NA.
.rmd_arg <- function(arg, what) {
  p <- sys.parent()
  choices <- eval(formals(sys.function(p))[[what]], envir = sys.frame(p))
  if (is.null(arg) || identical(arg, choices)) {
    return(choices[[1L]])
  }
  k <- if (is.character(arg) && length(arg) == 1L && !is.na(arg) &&
             validEnc(arg)) pmatch(arg, choices) else NA_integer_
  if (is.na(k)) {
    stop(sprintf("`%s` must be one of %s.", what,
                 paste0("\"", choices, "\"", collapse = ", ")),
         call. = FALSE)
  }
  choices[[k]]
}

#' Show or save the language-model settings
#'
#' The route \code{\link{mdask}()} takes and the address, key and model of each
#' route (your own OpenAI-compatible server, each provider such as Anthropic or
#' OpenAI, a local or LAN Ollama server), shared with \pkg{rmoriebricklayer}
#' and the packages built on it. A thin front to
#' \code{rmoriebricklayer::llmcfg()}, which saves them in
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
#' if ("llmcfg" %in% getNamespaceExports("rmoriebricklayer")) {
#'   mdllmconf()   # reading writes nothing
#' }
#' \dontrun{
#' mdllmconf(route = "anthropic", anthropic.model = "claude-opus-5-5")
#' mdllmconf(route = NULL)   # back to the automatic order
#' }
#' @export
mdllmconf <- function(...) {
  .rmd_bounds()
  if (!"llmcfg" %in% getNamespaceExports("rmoriebricklayer")) {
    stop("saving language-model settings needs rmoriebricklayer 0.5.11 or later: ",
         "install.packages(\"rmoriebricklayer\", repos = ",
         "c(\"https://rootcoder007.r-universe.dev\", \"https://cloud.r-project.org\"))",
         call. = FALSE)
  }
  f <- getExportedValue("rmoriebricklayer", "llmcfg")
  f(...)
}
