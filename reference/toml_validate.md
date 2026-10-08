# Check that a document is valid TOML

Runs the whole check phase of
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
(the lexer, the grammar, the rules for defining tables and keys, every
value, and the limits) without building any R value. It is exactly the
check
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
makes, with the same limits: the two disagree only where a document is
valid TOML that R cannot hold, such as a string containing U+0000.

## Usage

``` r
toml_validate(
  x,
  version = c("1.1.0", "1.0.0"),
  max_size = 64 * 1024^2,
  max_depth = 128L,
  max_items = 1e+06,
  max_string = 2^31 - 1,
  error = FALSE
)
```

## Arguments

- x:

  A TOML document: a single string, or a raw vector of UTF-8 bytes.

- version:

  The TOML version to read: `"1.1.0"` (the default) or `"1.0.0"`, which
  refuses the forms 1.1.0 added (`\e` and `\xHH` escapes, times without
  seconds, newlines and a trailing comma in inline tables).

- max_size:

  The largest document accepted, in bytes, or `Inf`.

- max_depth:

  The deepest nesting of tables and arrays, counting both; at most 1023.

- max_items:

  The most keys plus array elements, or `Inf`.

- max_string:

  The longest string or key, in decoded bytes, or `Inf`.

- error:

  If `FALSE` (the default), return `FALSE` for a document that is not
  valid. If `TRUE`, raise the condition instead, so the caller learns
  why and where.

## Value

`TRUE` when `x` is valid TOML within the limits. Otherwise `FALSE`, or
with `error = TRUE` a condition of class `zutoml_parse_error` or
`zutoml_limit_error` (see
[zutoml-conditions](https://pedrobtz.github.io/zutoml/reference/zutoml-conditions.md))
carrying the `line`, `column`, byte `offset` and `kind` of the fault.

## Examples

``` r
toml_validate('title = "TOML"\n[owner]\nname = "Tom"\n')
#> [1] TRUE
toml_validate("a = 1\na = 2\n")
#> [1] FALSE

# Why not, and where:
tryCatch(
  toml_validate("a = 1\na = 2\n", error = TRUE),
  zutoml_parse_error = function(e) c(e$kind, e$line, e$column)
)
#> [1] "duplicate_key" "2"             "1"            
```
