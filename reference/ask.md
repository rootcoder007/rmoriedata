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
ask("which bundled datasets cover Toronto police use-of-force?")
} # }
```
