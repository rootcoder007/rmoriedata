# Ask a language model about the bundled datasets

Sends a dataset-focused question through
[`rmoriebricklayer::bricklayer_llm_ask()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_ask.html),
which takes the first language-model route that answers: an
OpenAI-compatible endpoint of your own (`MORIE_LLM_BASE_URL`), a local
Ollama server, then the hosted MORIE tier as a last resort, with the key
that
[`morie_data_hosted_login()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_hosted_catalog.md)
stores (the same key opens the curated tables; keys are issued on
request at <https://www.rmorie.com/access/>).
[`rmoriebricklayer::bricklayer_llm_status()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_status.html)
shows which route would answer and
[`rmoriebricklayer::bricklayer_llm_models()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_models.html)
what the hosted key may use. With `backend = "cli"` the question goes to
the optional `rmorie` command-line agent instead, as before.

## Usage

``` r
ask(question, model = NULL, backend = "auto")
```

## Arguments

- question:

  Character scalar.

- model:

  Optional model id, e.g. `"gpt-oss-120b:cf"`; the tier's default when
  `NULL`.

- backend:

  `"auto"` (the first route rmoriebricklayer finds, else the `rmorie`
  binary), `"hosted"` (the hosted tier only), or `"cli"` (the `rmorie`
  binary's agent, with its own fallback chain).

## Value

Character scalar: the answer, or a sentence saying what to set up when
no route answers and the `rmorie` binary is not available.

## Examples

``` r
if (FALSE) { # \dontrun{
# These need a stored key (morie_data_hosted_login()) or the rmorie binary.
# After morie_data_hosted_login(): the hosted tier answers.
ask("which bundled datasets cover Toronto police use-of-force?")

# Pin one of the additional AI models.
ask("summarise the SIU director's-report corpus", model = "gpt-oss-120b:cf")

# Ask through the rmorie command-line agent.
ask("list the Chicago datasets", backend = "cli")
} # }

# With every route switched off and no rmorie binary on PATH the call
# returns a setup hint, not an error, and reaches no network whatever
# key this machine has stored:
routes <- c("MORIE_HOSTED_BASE_URL", "OLLAMA_HOST", "MORIE_LLM_BASE_URL")
old <- Sys.getenv(routes, unset = NA)
Sys.setenv(MORIE_HOSTED_BASE_URL = "off", OLLAMA_HOST = "off",
           MORIE_LLM_BASE_URL = "off")
if (!nzchar(Sys.which("rmorie"))) ask("hello")
#> [1] "No language-model route is set up (no endpoint of your own, no local Ollama, no hosted key) and no rmorie CLI on PATH: start a local model, set MORIE_LLM_BASE_URL, or run morie_data_hosted_login(token = ) once; keys are personal and issued on request at https://rmorie.com/access."
for (v in routes) {
  if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v]))
}
```
