# Ask a language model about the bundled datasets

Sends a question through
[`rmoriebricklayer::bricklayer_llm_ask()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_ask.html),
to a language model you bring: an OpenAI-compatible endpoint of your
own, a provider whose key is set (OpenAI, Anthropic, Google Gemini,
OpenRouter, Groq, Mistral and more:
[`rmoriebricklayer::bricklayer_llm_providers()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_providers.html)),
or an Ollama server. Nothing is sent anywhere you did not set up. The
model is given every function of rmoriedata and rmoriebricklayer and
tools to read their help, and this package's catalogue of datasets, so
it can name the tables and write the code that loads them.
[`rmoriebricklayer::bricklayer_llm_status()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_status.html)
shows which route would answer;
[`morie_data_llm_config()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_llm_config.md)
(or `rmbl config setup` from the shell) saves a provider's key, the
route and the model.

## Usage

``` r
ask(question, model = NULL, route = NULL)
```

## Arguments

- question:

  Character scalar.

- model:

  Optional model name; the route's model when `NULL`.

- route:

  `NULL` or `"auto"` (the first route that is set up), `"own"`,
  `"ollama"` or a provider id such as `"anthropic"` (that route only).

## Value

Character scalar: the answer, or a sentence saying what went wrong or
what to set up (never an error, so a script keeps going).

## Examples

``` r
if (FALSE) { # \dontrun{
# These need a language model: a provider's key, Ollama, or your own server.
Sys.setenv(ANTHROPIC_API_KEY = "...")
ask("which bundled datasets cover Toronto police use-of-force?")
ask("summarise the SIU director's-report corpus", route = "ollama",
    model = "qwen3:8b")
} # }

# With no route set up the call returns a setup hint, not an error, and
# reaches no network:
if (requireNamespace("rmoriebricklayer", quietly = TRUE)) {
  old <- Sys.getenv(c("OLLAMA_HOST", "MORIE_LLM_BASE_URL"), unset = NA)
  Sys.setenv(OLLAMA_HOST = "off", MORIE_LLM_BASE_URL = "off")
  if (!nrow(subset(rmoriebricklayer::bricklayer_llm_status(),
                   status %in% c("key set", "configured")))) {
    cat(ask("hello"))
  }
  for (v in names(old)) {
    if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, as.list(old[v]))
  }
}
#> The language model could not answer: No language-model route is set up on this machine: bring your own key, or run a model locally:
#>   a provider's key: set its variable (OPENAI_API_KEY, ANTHROPIC_API_KEY, GEMINI_API_KEY, OPENROUTER_API_KEY, ...) or `rmoriebricklayer config set PROVIDER.key`; providers: openai, anthropic, gemini, openrouter, groq, together, fireworks, deepseek, mistral, xai, cerebras, perplexity, huggingface, opencode, cohere, nvidia
#>   local Ollama: OLLAMA_HOST=off
#>   own endpoint: `rmoriebricklayer config set own.url URL` (and own.model, own.key) for any OpenAI-compatible server (LM Studio, vLLM, llama.cpp, a company gateway)
#> `rmoriebricklayer config setup` walks through it.
```
