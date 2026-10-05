# SPDX-License-Identifier: AGPL-3.0-or-later

#' Ask the hosted MORIE tier about the bundled datasets
#'
#' Sends a dataset-focused question to the hosted MORIE language-model tier
#' at \url{https://llm.rmorie.com} through \pkg{rmoriebricklayer}, using the
#' key that \code{\link{morie_data_hosted_login}()} stores (the same key
#' opens data.rmorie.com). The tier serves ollama.com cloud models and
#' additional AI models (\code{kimi-k2.6:cf},
#' \code{kimi-k2.7-code:cf}, \code{deepseek-v4-pro:cf},
#' \code{deepseek-v4-flash:cf}, \code{glm-5.2:cf}, \code{glm-5.3:cf},
#' \code{glm-5.3-flash:cf}, \code{gpt-oss-120b:cf}, \code{gpt-oss-20b:cf},
#' \code{llama-4-scout:cf}, \code{qwen3.8-27b:cf}, \code{nemotron-3-120b:cf},
#' \code{gemma-4-26b:cf});
#' \code{rmoriebricklayer::bricklayer_llm_models()} lists what your key may
#' use. With \code{backend = "ollama"} (or any value other than
#' \code{"auto"} and \code{"hosted"}) the question goes to the optional
#' \code{rmorie} command-line agent instead, as before.
#'
#' @param question Character scalar.
#' @param model Optional model id, e.g. \code{"gpt-oss-120b:cf"}; the tier's
#'   default when \code{NULL}.
#' @param backend \code{"auto"} (the hosted tier when a key is stored, else
#'   the \code{rmorie} binary), \code{"hosted"}, or a backend name for the
#'   \code{rmorie} agent such as \code{"ollama"}.
#' @return Character scalar: the answer, or a sentence saying how to sign in
#'   when neither a key nor the \code{rmorie} binary is available.
#' @examples
#' \donttest{
#' # After morie_data_hosted_login(): the hosted tier answers.
#' ask("which bundled datasets cover Toronto police use-of-force?")
#'
#' # Pin one of the additional AI models.
#' ask("summarise the SIU director's-report corpus", model = "gpt-oss-120b:cf")
#'
#' # Force the rmorie command-line agent with a local Ollama.
#' ask("list the Chicago datasets", backend = "ollama")
#' }
#'
#' # With no key stored and no rmorie binary on PATH the call returns a
#' # sign-in hint, not an error -- safe to run anywhere:
#' if (!nzchar(Sys.which("rmorie"))) ask("hello")
#' @export
ask <- function(question, model = NULL, backend = "auto") {
  .rmoriedata_scalar(question, "question")
  .rmoriedata_scalar(backend, "backend")
  if (!is.null(model)) .rmoriedata_scalar(model, "model")
  system_prompt <- paste0(
    "You are helping explore the datasets bundled in the MORIE packages ",
    "(rmoriedata). Prefer the bundled catalog."
  )
  if (backend %in% c("auto", "hosted")) {
    st <- rmoriebricklayer::bricklayer_llm_status()
    if (identical(st$status[1L], "key stored")) {
      # a rejected key, a model nobody serves or no network must read as a
      # sentence, never as an error: an example or a script keeps going
      return(tryCatch(
        rmoriebricklayer::bricklayer_llm_ask(
          question, model = model, system_prompt = system_prompt
        ),
        error = function(e) {
          paste0(
            "The hosted MORIE tier could not answer (", conditionMessage(e),
            "). If the key was rejected, run morie_data_hosted_login() again."
          )
        }
      ))
    }
    if (identical(backend, "hosted")) {
      return(paste0(
        "No key for the hosted MORIE tier: run morie_data_hosted_login() ",
        "once (GitHub, email, or token)."
      ))
    }
  }
  bin <- Sys.which("rmorie")
  if (!nzchar(bin)) {
    return(paste0(
      "No key for the hosted MORIE tier and no rmorie CLI on PATH: run ",
      "morie_data_hosted_login() once, or install rmorie-cli."
    ))
  }
  preamble <- paste0(system_prompt, " Question: ", question)
  # system2() hands `args` to a shell: quote every value, or the first
  # parenthesis in the request is a shell syntax error (and a ";" in the
  # question would run as a command).
  args <- c("agent", "--backend", shQuote(backend))
  if (!is.null(model)) args <- c(args, "-m", shQuote(model))
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
