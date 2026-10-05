# Ask the hosted MORIE tier about the bundled datasets

Sends a dataset-focused question to the hosted MORIE language-model tier
at <https://llm.rmorie.com> through rmoriebricklayer, using the key that
[`morie_data_hosted_login()`](https://rootcoder007.github.io/rmoriedata/reference/morie_data_hosted_catalog.md)
stores (the same key opens data.rmorie.com). The tier serves ollama.com
cloud models and additional AI models (`kimi-k2.6:cf`,
`kimi-k2.7-code:cf`, `deepseek-v4-pro:cf`, `deepseek-v4-flash:cf`,
`glm-5.2:cf`, `glm-5.3:cf`, `glm-5.3-flash:cf`, `gpt-oss-120b:cf`,
`gpt-oss-20b:cf`, `llama-4-scout:cf`, `qwen3.8-27b:cf`,
`nemotron-3-120b:cf`, `gemma-4-26b:cf`);
[`rmoriebricklayer::bricklayer_llm_models()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_models.html)
lists what your key may use. With `backend = "ollama"` (or any value
other than `"auto"` and `"hosted"`) the question goes to the optional
`rmorie` command-line agent instead, as before.

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

  `"auto"` (the hosted tier when a key is stored, else the `rmorie`
  binary), `"hosted"` (the hosted tier only), or `"cli"` (the `rmorie`
  binary's agent, with its own fallback chain: the hosted tier, then a
  local Ollama).

## Value

Character scalar: the answer, or a sentence saying how to sign in when
neither a key nor the `rmorie` binary is available.

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

# With no key stored and no rmorie binary on PATH the call returns a
# sign-in hint, not an error (no network); an empty config directory
# stands in for a machine that has never signed in:
old <- Sys.getenv(c("XDG_CONFIG_HOME", "MORIE_HOSTED_KEY"))
Sys.setenv(XDG_CONFIG_HOME = tempfile(), MORIE_HOSTED_KEY = "")
if (!nzchar(Sys.which("rmorie"))) ask("hello")
#> [1] "No key for the hosted MORIE tier and no rmorie CLI on PATH: run morie_data_hosted_login() once, or install rmorie-cli."
do.call(Sys.setenv, as.list(old))
```
