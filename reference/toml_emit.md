# Write R values as TOML

`toml_emit()` turns a named list into the text of a TOML document;
`toml_write()` writes that text to a file or connection. The output is
deterministic (the same value gives the same bytes on every platform)
and is always text
[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
reads back.

## Usage

``` r
toml_emit(
  x,
  indent = 2L,
  inline = 0L,
  width = 80L,
  na = c("error", "omit"),
  strings = c("basic", "literal"),
  max_depth = 128L
)

toml_write(x, file, ...)
```

## Arguments

- x:

  A named list: the document's top-level table.

- indent:

  Spaces before each element of an array written one element per line.

- inline:

  A nested named list with at most this many keys, none of them a list,
  is written as an inline table (`{ x = 1, y = 2 }`) rather than under
  its own header. `0`, the default, never does.

- width:

  An array whose line would pass this column is written one element per
  line. `0` never wraps.

- na:

  `"error"` (the default) refuses `NA` and `NULL`; `"omit"` leaves out a
  key whose value is `NA` or `NULL`, and drops such elements from arrays
  with a warning.

- strings:

  `"basic"` (the default) writes double-quoted strings; `"literal"`
  writes single-quoted strings where that needs no escapes.

- max_depth:

  The deepest nesting of tables and arrays written, counted as
  [`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
  counts it; at most 1023.

- file:

  For `toml_write()`, a path or a connection.

- ...:

  For `toml_write()`, passed to `toml_emit()`.

## Value

`toml_emit()`: a single string, UTF-8, with `\n` line endings and a
final newline. `toml_write()`: `file`, invisibly.

## R to TOML

|  |  |
|----|----|
| R | TOML |
| `character` | basic string, or literal with `strings = "literal"` |
| `integer` | integer |
| `double`, whole, within 64-bit range, not `-0` | integer |
| any other `double` | float, in the shortest digits that read back exactly |
| `logical` | boolean |
| `POSIXct` with a time zone | offset date-time, in UTC (`Z`) |
| `POSIXct` with no time zone (`tzone = ""`) | local date-time |
| `Date` | local date |
| `difftime` in seconds, from 0 to a day | local time |
| [`toml_bigint()`](https://pedrobtz.github.io/zutoml/reference/toml_bigint.md) | integer |
| `factor` | its labels, as strings |
| a vector of length one | the value; [`I()`](https://rdrr.io/r/base/AsIs.html) makes it an array of one |
| a longer vector | array |
| named `list` | table, or an inline table inside an array |
| unnamed `list` of named lists | array of tables (`[[key]]`) |
| other unnamed `list` | array |
| `data.frame` | array of tables, one per row; `NA` cells are left out |

A table's own keys are written first, in the list's order, then its
sub-tables: TOML has no other way to say which keys belong to which
table. A sub-table that holds only sub-tables gets no header of its own.
A string with a newline is written as a multi-line string.

Refused with `zutoml_unsupported_type`: complex and raw vectors,
functions, environments, `POSIXlt`, matrices and arrays with `dim`, and
atomic vectors of other classes. `NA` and `NULL`, which TOML has no form
for, raise `zutoml_na_error` unless `na = "omit"`. Each condition
carries `path`, the key path of the value at fault, as `a.b[3].c`.

## Examples

``` r
cfg <- list(
  title = "Example",
  port = 8080,
  tags = c("a", "b"),
  owner = list(name = "Tom", since = as.Date("1979-05-27")),
  servers = list(
    list(name = "alpha", ip = "10.0.0.1"),
    list(name = "beta", ip = "10.0.0.2")
  )
)
cat(toml_emit(cfg))
#> title = "Example"
#> port = 8080
#> tags = ["a", "b"]
#> 
#> [owner]
#> name = "Tom"
#> since = 1979-05-27
#> 
#> [[servers]]
#> name = "alpha"
#> ip = "10.0.0.1"
#> 
#> [[servers]]
#> name = "beta"
#> ip = "10.0.0.2"

identical(toml_parse(toml_emit(cfg))$port, 8080L)
#> [1] TRUE

path <- tempfile(fileext = ".toml")
toml_write(cfg, path)
toml_parse(readLines(path) |> paste(collapse = "\n"))$owner$name
#> [1] "Tom"
```
