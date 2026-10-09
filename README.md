
# zutoml

<!-- badges: start -->
[![R-CMD-check](https://github.com/pedrobtz/zutoml/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pedrobtz/zutoml/actions/workflows/R-CMD-check.yaml)
[![coverage](https://raw.githubusercontent.com/pedrobtz/zutoml/main/.github/badges/coverage.svg)](https://github.com/pedrobtz/zutoml/actions/workflows/coverage.yaml)
<!-- badges: end -->

zutoml reads [TOML](https://toml.io) documents into ordinary R values and
writes R values as TOML. Its parser and writer are written in C, with no
system library and no runtime dependencies. Both pass every case of the
[toml-test](https://github.com/toml-lang/toml-test) conformance suite, for
TOML 1.0.0 and 1.1.0.

- **Types come from the document.** `2024-01-01` is a `Date`;
  `"2024-01-01"` is a string. zutoml never guesses from a string's content.
- **Strict.** An invalid document is refused, with the line and column at
  fault and a condition class you can catch. Size, depth, item and string
  limits bound untrusted input.
- **Deterministic output.** The same R value gives the same bytes on every
  platform, and the text reads back.

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

Read a TOML file straight from a URL, here the `pyproject.toml` of pandas:

``` r
library(zutoml)

pyproject <- "https://raw.githubusercontent.com/pandas-dev/pandas/v3.0.6/pyproject.toml"

x <- toml_read(pyproject)
names(x)
#> [1] "build-system" "project"      "tool"
x$project$name
#> [1] "pandas"
x$project$`requires-python`
#> [1] ">=3.11"
x$project$dependencies
#> [1] "numpy>=1.26.0; python_version < '3.14'"
#> [2] "numpy>=2.3.3; python_version >= '3.14'"
#> [3] "python-dateutil>=2.8.2"
#> [4] "tzdata; sys_platform == 'win32'"
#> [5] "tzdata; sys_platform == 'emscripten'"
```

Read only the part you need with a path:

``` r
toml_read(pyproject, select = "project.optional-dependencies.excel")
#> [1] "odfpy>=1.4.1"           "openpyxl>=3.1.5"        "python-calamine>=0.3.0"
#> [4] "pyxlsb>=1.0.10"         "xlrd>=2.0.1"            "xlsxwriter>=3.2.0"
```

`toml_read()` also takes a file path or a connection, and `toml_parse()` a
string. Write R values as TOML with `toml_emit()`:

``` r
cat(toml_emit(list(name = "zutoml", version = 1L, tags = c("toml", "config"))))
#> name = "zutoml"
#> version = 1
#> tags = ["toml", "config"]
```

See `vignette("zutoml")` for a tour with `pyproject.toml` and `Cargo.toml`,
and the [usage guide](https://pedrobtz.github.io/zutoml/articles/usage.html)
for every task.
