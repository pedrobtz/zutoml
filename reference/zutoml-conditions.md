# Conditions raised by zutoml

Every error zutoml raises carries a condition class, so it can be caught
by kind rather than by matching the message, which may change. Every
class below inherits from `zutoml_error`.

## Details

- `zutoml_invalid_argument`:

  An argument was unusable, or a value cannot be written as TOML as
  given, such as a list with partial names or a string that is not valid
  UTF-8. Carries `arg`, the argument at fault.

- `zutoml_parse_error`:

  The document is not TOML. Carries `line` and `column` (1-based, in
  characters), `offset` (0-based, in bytes) and `kind`, the name of the
  rule broken, such as `"bad_escape"` or `"table_redefined"`.

- `zutoml_unrepresentable`:

  The document is valid TOML but holds a value R cannot: a string
  containing U+0000, a string longer than an R string, or an integer
  beyond 2^53 with `big_integers = "error"`.

- `zutoml_unsupported_type`:

  An R value has no TOML form, such as a function, a raw vector or a
  matrix. Carries `path`, the key path of the value, as `a.b[3].c`.

- `zutoml_na_error`:

  An `NA` or `NULL` value with `na = "error"`. Carries `path`.

- `zutoml_limit_error`:

  A limit was reached. The subclasses `zutoml_size_limit`,
  `zutoml_depth_limit`, `zutoml_item_limit` and `zutoml_string_limit`
  name which one. Carries `limit`, the argument's name, such as
  `"max_depth"`, and `limit_value`.

- `zutoml_io_error`:

  A file or connection could not be read or written.

## Examples

``` r
tryCatch(
  stop(structure(
    class = c("zutoml_parse_error", "zutoml_error", "error", "condition"),
    list(message = "TOML parse error", call = NULL)
  )),
  zutoml_error = function(e) class(e)[1]
)
#> [1] "zutoml_parse_error"
```
