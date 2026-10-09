# Show or save the language-model settings

The route
[`ask()`](https://rootcoder007.github.io/rmoriedata/reference/ask.md)
takes and the address, key and model of each route (your own
OpenAI-compatible server, a local or LAN Ollama server, the hosted MORIE
tier), shared with rmoriebricklayer, rmorie and the Python package
morie. A thin front to
[`rmoriebricklayer::bricklayer_llm_config()`](https://rootcoder007.github.io/rmorie-bricklayer/reference/bricklayer_llm_config.html),
which saves them in `~/.config/morie/llm.json` only when you pass a
setting; from the shell, `rmbl config` and `rmbl config setup` do the
same.

## Usage

``` r
morie_data_llm_config(...)
```

## Arguments

- ...:

  Settings as `key = value`, e.g. `route = "hosted"`,
  `hosted.model = "gpt-oss-120b:cf"`,
  `ollama.url = "http://192.168.1.20:11434"`,
  `own.url = "http://localhost:1234/v1"`; `NULL` removes one. With no
  arguments nothing is written.

## Value

A data frame with one row per setting (`key`, `value`, `source`, `env`,
`help`).

## Examples

``` r
if ("bricklayer_llm_config" %in% getNamespaceExports("rmoriebricklayer")) {
  morie_data_llm_config()   # reading writes nothing
}
#>             key                  value  source                   env
#> 1         route                   auto default       MORIE_LLM_ROUTE
#> 2       own.url              (not set) default    MORIE_LLM_BASE_URL
#> 3       own.key              (not set) default     MORIE_LLM_API_KEY
#> 4     own.model   (the server's first) default       MORIE_LLM_MODEL
#> 5    ollama.url http://localhost:11434 default           OLLAMA_HOST
#> 6  ollama.model (the first one pulled) default          OLLAMA_MODEL
#> 7    ollama.key              (not set) default        OLLAMA_API_KEY
#> 8    hosted.url https://llm.rmorie.com default MORIE_HOSTED_BASE_URL
#> 9  hosted.model       minimax-m3:cloud default    MORIE_HOSTED_MODEL
#> 10   hosted.key              (not set) default      MORIE_HOSTED_KEY
#>                                                                                                                                                                       help
#> 1                                                                             which route `ask` uses: auto (own endpoint, then Ollama, then hosted), own, ollama or hosted
#> 2  your own OpenAI-compatible server, e.g. http://localhost:1234/v1 (LM Studio), http://localhost:8080/v1 (llama-server -m /path/model.gguf) or https://api.example.org/v1
#> 3                                                                                                                     API key for your own server (sent as a Bearer token)
#> 4                                                                                                                                            model name on your own server
#> 5                                                                                your Ollama server, e.g. http://localhost:11434 or 192.168.1.20:11434; off to skip Ollama
#> 6                                                                                                                      Ollama model to use (default: the first one pulled)
#> 7                                                                                                                              API key for an Ollama server that wants one
#> 8                                                                                   hosted MORIE tier address (default: from the signed services document); off to skip it
#> 9                                                                                                     hosted model (default: the tier's default; `rmbl models` lists them)
#> 10                                                                                    your MORIE key (stored by `rmbl login`; checked with the gateway before it is saved)
if (FALSE) { # \dontrun{
morie_data_llm_config(route = "hosted", hosted.model = "gpt-oss-120b:cf")
morie_data_llm_config(route = NULL)   # back to the automatic order
} # }
```
