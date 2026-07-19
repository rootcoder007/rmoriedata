# SPDX-License-Identifier: AGPL-3.0-or-later

#' Ask the rmorie agent about the bundled datasets
#'
#' Convenience wrapper that forwards a dataset-focused question to the
#' \code{rmorie} command-line agent (optional binary from rmorie-cli). See
#' \code{rmorie::agent} for the full interface and requirements.
#'
#' @param question Character scalar.
#' @param model Optional model id (see \code{rmorie::agent}).
#' @param backend Optional backend override (see \code{rmorie::agent}).
#' @return Character scalar: the agent's output, or a message if the
#'   \code{rmorie} binary is not installed.
#' @examples
#' \donttest{
#' # Routed to the optional rmorie CLI agent when it is installed; with no
#' # binary on PATH each call returns an install hint instantly (no error,
#' # no network), so this is safe to execute anywhere.
#' # Plain question -> routed to the rmorie CLI agent (auto backend).
#' ask("which bundled datasets cover Toronto police use-of-force?")
#'
#' # Pin a specific model.
#' ask("summarise the SIU director's-report corpus", model = "gpt-4o-mini")
#'
#' # Force a backend (see rmorie::agent for the available values).
#' ask("list the Chicago datasets", backend = "ollama")
#' }
#'
#' # With no rmorie binary on PATH the call returns an install hint, not an
#' # error -- safe to run anywhere:
#' if (!nzchar(Sys.which("rmorie"))) ask("hello")
#' @export
ask <- function(question, model = NULL, backend = "auto") {
  stopifnot(is.character(question), length(question) == 1L, nzchar(question))
  bin <- Sys.which("rmorie")
  if (!nzchar(bin)) {
    return("rmorie CLI not found on PATH. Install rmorie-cli to use ask().")
  }
  preamble <- paste0(
    "You are helping explore the datasets bundled in the MORIE packages ",
    "(rmoriedata). Prefer the bundled catalog. Question: ", question)
  args <- c("agent", "--backend", backend)
  if (!is.null(model)) args <- c(args, "-m", model)
  args <- c(args, preamble)
  paste(suppressWarnings(
    system2(bin, args = args, stdout = TRUE, stderr = TRUE)), collapse = "\n")
}
