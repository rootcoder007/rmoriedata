# Ask the rmorie agent about the bundled datasets

Convenience wrapper that forwards a dataset-focused question to the
`rmorie` command-line agent (optional binary from rmorie-cli). See
`rmorie::agent` for the full interface and requirements.

## Usage

``` r
ask(question, model = NULL, backend = "auto")
```

## Arguments

- question:

  Character scalar.

- model:

  Optional model id (see `rmorie::agent`).

- backend:

  Optional backend override (see `rmorie::agent`).

## Value

Character scalar: the agent's output, or a message if the `rmorie`
binary is not installed.

## Examples

``` r
if (FALSE) { # \dontrun{
# Plain question -> routed to the rmorie CLI agent (auto backend).
ask("which bundled datasets cover Toronto police use-of-force?")

# Pin a specific model.
ask("summarise the SIU director's-report corpus", model = "gpt-4o-mini")

# Force a backend (see rmorie::agent for the available values).
ask("list the Chicago datasets", backend = "ollama")
} # }

# With no rmorie binary on PATH the call returns an install hint, not an
# error -- safe to run anywhere:
if (!nzchar(Sys.which("rmorie"))) ask("hello")
#> [1] "rmorie CLI not found on PATH. Install rmorie-cli to use ask()."
```
