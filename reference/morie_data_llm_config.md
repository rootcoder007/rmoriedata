# Show or save the language-model settings

The route
[`ask()`](https://rootcoder007.github.io/rmoriedata/reference/ask.md)
takes and the address, key and model of each route (your own
OpenAI-compatible server, each provider such as Anthropic or OpenAI, a
local or LAN Ollama server), shared with rmoriebricklayer, rmorie and
the Python package morie. A thin front to
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

  Settings as `key = value`, e.g. `route = "anthropic"`,
  `anthropic.key = "..."`, `anthropic.model = "claude-opus-5-5"`,
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
#>                  key                  value  source                     env
#> 1              route                   auto default         MORIE_LLM_ROUTE
#> 2            own.url              (not set) default      MORIE_LLM_BASE_URL
#> 3            own.key              (not set) default       MORIE_LLM_API_KEY
#> 4          own.model              (not set) default         MORIE_LLM_MODEL
#> 5         ollama.url http://localhost:11434 default             OLLAMA_HOST
#> 6       ollama.model (the first one pulled) default            OLLAMA_MODEL
#> 7         ollama.key              (not set) default          OLLAMA_API_KEY
#> 8         openai.key              (not set) default          OPENAI_API_KEY
#> 9       openai.model           (not chosen) default      MORIE_OPENAI_MODEL
#> 10     anthropic.key              (not set) default       ANTHROPIC_API_KEY
#> 11   anthropic.model        claude-opus-5-5 default   MORIE_ANTHROPIC_MODEL
#> 12        gemini.key              (not set) default          GEMINI_API_KEY
#> 13      gemini.model           (not chosen) default      MORIE_GEMINI_MODEL
#> 14    openrouter.key              (not set) default      OPENROUTER_API_KEY
#> 15  openrouter.model           (not chosen) default  MORIE_OPENROUTER_MODEL
#> 16          groq.key              (not set) default            GROQ_API_KEY
#> 17        groq.model           (not chosen) default        MORIE_GROQ_MODEL
#> 18      together.key              (not set) default        TOGETHER_API_KEY
#> 19    together.model           (not chosen) default    MORIE_TOGETHER_MODEL
#> 20     fireworks.key              (not set) default       FIREWORKS_API_KEY
#> 21   fireworks.model           (not chosen) default   MORIE_FIREWORKS_MODEL
#> 22      deepseek.key              (not set) default        DEEPSEEK_API_KEY
#> 23    deepseek.model           (not chosen) default    MORIE_DEEPSEEK_MODEL
#> 24       mistral.key              (not set) default         MISTRAL_API_KEY
#> 25     mistral.model           (not chosen) default     MORIE_MISTRAL_MODEL
#> 26           xai.key              (not set) default             XAI_API_KEY
#> 27         xai.model           (not chosen) default         MORIE_XAI_MODEL
#> 28      cerebras.key              (not set) default        CEREBRAS_API_KEY
#> 29    cerebras.model           (not chosen) default    MORIE_CEREBRAS_MODEL
#> 30    perplexity.key              (not set) default      PERPLEXITY_API_KEY
#> 31  perplexity.model              sonar-pro default  MORIE_PERPLEXITY_MODEL
#> 32   huggingface.key              (not set) default                HF_TOKEN
#> 33 huggingface.model           (not chosen) default MORIE_HUGGINGFACE_MODEL
#> 34      opencode.key              (not set) default        OPENCODE_API_KEY
#> 35    opencode.model           (not chosen) default    MORIE_OPENCODE_MODEL
#> 36        cohere.key              (not set) default          COHERE_API_KEY
#> 37      cohere.model           (not chosen) default      MORIE_COHERE_MODEL
#> 38        nvidia.key              (not set) default          NVIDIA_API_KEY
#> 39      nvidia.model           (not chosen) default      MORIE_NVIDIA_MODEL
#>                                                                                                                                                                       help
#> 1                                                       which route `ask` uses: auto (own endpoint, then each provider with a key, then Ollama), own, ollama or a provider
#> 2  your own OpenAI-compatible server, e.g. http://localhost:1234/v1 (LM Studio), http://localhost:8080/v1 (llama-server -m /path/model.gguf) or https://api.example.org/v1
#> 3                                                                                                                     API key for your own server (sent as a Bearer token)
#> 4                                                                                                                                            model name on your own server
#> 5                                                                                your Ollama server, e.g. http://localhost:11434 or 192.168.1.20:11434; off to skip Ollama
#> 6                                                                                                                      Ollama model to use (default: the first one pulled)
#> 7                                                                                                                              API key for an Ollama server that wants one
#> 8                                                                                                             your OpenAI API key (sent only to https://api.openai.com/v1)
#> 9                                                                                                            OpenAI model to use (`rmbl models --route openai` lists them)
#> 10                                                                                                         your Anthropic API key (sent only to https://api.anthropic.com)
#> 11                                                                                                                        Anthropic model to use (default claude-opus-5-5)
#> 12                                                                                     your Google Gemini API key (sent only to https://generativelanguage.googleapis.com)
#> 13                                                                                                    Google Gemini model to use (`rmbl models --route gemini` lists them)
#> 14                                                                                                     your OpenRouter API key (sent only to https://openrouter.ai/api/v1)
#> 15                                                                                                   OpenRouter model to use (`rmbl models --route openrouter` lists them)
#> 16                                                                                                         your Groq API key (sent only to https://api.groq.com/openai/v1)
#> 17                                                                                                               Groq model to use (`rmbl models --route groq` lists them)
#> 18                                                                                                     your Together AI API key (sent only to https://api.together.xyz/v1)
#> 19                                                                                                    Together AI model to use (`rmbl models --route together` lists them)
#> 20                                                                                          your Fireworks AI API key (sent only to https://api.fireworks.ai/inference/v1)
#> 21                                                                                                  Fireworks AI model to use (`rmbl models --route fireworks` lists them)
#> 22                                                                                                        your DeepSeek API key (sent only to https://api.deepseek.com/v1)
#> 23                                                                                                       DeepSeek model to use (`rmbl models --route deepseek` lists them)
#> 24                                                                                                           your Mistral API key (sent only to https://api.mistral.ai/v1)
#> 25                                                                                                         Mistral model to use (`rmbl models --route mistral` lists them)
#> 26                                                                                                                     your xAI API key (sent only to https://api.x.ai/v1)
#> 27                                                                                                                 xAI model to use (`rmbl models --route xai` lists them)
#> 28                                                                                                         your Cerebras API key (sent only to https://api.cerebras.ai/v1)
#> 29                                                                                                       Cerebras model to use (`rmbl models --route cerebras` lists them)
#> 30                                                                                                        your Perplexity API key (sent only to https://api.perplexity.ai)
#> 31                                                                                                                             Perplexity model to use (default sonar-pro)
#> 32                                                                                               your Hugging Face API key (sent only to https://router.huggingface.co/v1)
#> 33                                                                                                Hugging Face model to use (`rmbl models --route huggingface` lists them)
#> 34                                                                                                     your OpenCode Zen API key (sent only to https://opencode.ai/zen/v1)
#> 35                                                                                                   OpenCode Zen model to use (`rmbl models --route opencode` lists them)
#> 36                                                                                               your Cohere API key (sent only to https://api.cohere.ai/compatibility/v1)
#> 37                                                                                                           Cohere model to use (`rmbl models --route cohere` lists them)
#> 38                                                                                              your NVIDIA NIM API key (sent only to https://integrate.api.nvidia.com/v1)
#> 39                                                                                                       NVIDIA NIM model to use (`rmbl models --route nvidia` lists them)
if (FALSE) { # \dontrun{
morie_data_llm_config(route = "anthropic", anthropic.model = "claude-opus-5-5")
morie_data_llm_config(route = NULL)   # back to the automatic order
} # }
```
