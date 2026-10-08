# zutoml

zutoml reads [TOML](https://toml.io) documents into ordinary R values
and writes R values as TOML. Its parser and writer are written in C,
with no system library and no runtime dependencies. Both pass every case
of the [toml-test](https://github.com/toml-lang/toml-test) conformance
suite, for TOML 1.0.0 and 1.1.0.

- **Types come from the document.** `2024-01-01` is a `Date`;
  `"2024-01-01"` is a string. zutoml never guesses from a string’s
  content.
- **Strict.** An invalid document is refused, with the line and column
  at fault and a condition class you can catch. Size, depth, item and
  string limits bound untrusted input.
- **Deterministic output.** The same R value gives the same bytes on
  every platform, and the text reads back.

## Installation

Install zutoml from CRAN:

``` r

install.packages("zutoml")
```

or the development version from GitHub:

``` r

# install.packages("pak")
pak::pak("pedrobtz/zutoml")
```

## Example

``` r

library(zutoml)

x <- toml_parse('
title = "TOML Example"

[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00

[database]
ports = [8000, 8001, 8002]
enabled = true
')

x$owner$dob
#> [1] "1979-05-27 15:32:00 UTC"
x$database$ports
#> [1] 8000 8001 8002

cat(toml_emit(list(name = "zutoml", version = 1L, tags = c("toml", "config"))))
#> name = "zutoml"
#> version = 1
#> tags = ["toml", "config"]
```

See
[`vignette("zutoml")`](https://pedrobtz.github.io/zutoml/articles/zutoml.md)
for reading `pyproject.toml` and `Cargo.toml` and writing configuration
files.
