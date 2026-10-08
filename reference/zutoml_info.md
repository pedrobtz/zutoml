# Information about the zutoml build

Information about the zutoml build

## Usage

``` r
zutoml_info()
```

## Value

A list: `version`, the package version; `zufast`, the version of the
'zufast' headers it was compiled against; `toml_test`, the version of
the `toml-test` conformance suite it passes; `toml_versions`, the TOML
versions
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
reads; `max_depth_cap`, the largest `max_depth` accepted; and `ndebug`,
whether the C code was compiled without assertions.

## Examples

``` r
zutoml_info()$toml_test
#> [1] "v2.2.0"
```
