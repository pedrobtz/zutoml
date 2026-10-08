# Usage guide

This guide shows zutoml’s main tasks, one section each. For a tour built
around real configuration files, see
[`vignette("zutoml")`](https://pedrobtz.github.io/zutoml/articles/zutoml.md).

``` r

library(zutoml)
```

## Read a document

[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
reads TOML text;
[`toml_read()`](https://pedrobtz.github.io/zutoml/reference/toml_read.md)
reads a file, a URL or a connection. Both return a named list, with keys
in the order the document gives them.

``` r

doc <- '
title = "Example"

[server]
host = "localhost"
port = 8080
tags = ["web", "api"]

[[users]]
name = "ana"
admin = true

[[users]]
name = "bo"
'
x <- toml_parse(doc)
str(x)
#> List of 3
#>  $ title : chr "Example"
#>  $ server:List of 3
#>   ..$ host: chr "localhost"
#>   ..$ port: int 8080
#>   ..$ tags: chr [1:2] "web" "api"
#>  $ users :List of 2
#>   ..$ :List of 2
#>   .. ..$ name : chr "ana"
#>   .. ..$ admin: logi TRUE
#>   ..$ :List of 1
#>   .. ..$ name: chr "bo"
```

``` r

path <- tempfile(fileext = ".toml")
writeLines(doc, path)
toml_read(path)$server$port
#> [1] 8080
```

## Read only part of a document

`select` returns the value at a path, written as the TOML key syntax:
dots between keys, quotes around keys that need them, and `[i]` for
array elements, counting from 1.

``` r

toml_parse(doc, select = "server")
#> $host
#> [1] "localhost"
#> 
#> $port
#> [1] 8080
#> 
#> $tags
#> [1] "web" "api"
toml_parse(doc, select = "users[2].name")
#> [1] "bo"
toml_read(path, select = c("server", "tags"))
#> [1] "web" "api"
```

The whole document is still checked, since TOML lets a table be added to
anywhere in it, but only the selected part becomes R values. A path the
document does not have is an error, never `NULL`:

``` r

try(toml_parse(doc, select = "server.timeout"))
#> Error : TOML document has no `server.timeout`: `server` has no `timeout`
```

## Types

Every TOML type maps to one R type, chosen by the document’s syntax,
never by what a string looks like:

| TOML | R |
|----|----|
| string | `character` |
| integer | `integer`; `double` past R’s integer range; `toml_bigint` past 2^53 |
| float | `double` (`inf`, `nan` as `Inf`, `NaN`) |
| boolean | `logical` |
| offset date-time | `POSIXct` in UTC |
| local date-time | `POSIXct` in the session’s time zone |
| local date | `Date` |
| local time | `character`, or `difftime` |
| table | named `list` |
| array | a vector when its elements share a type, else a `list` |

``` r

str(toml_parse('
when  = 1979-05-27T07:32:00-08:00
day   = 1979-05-27
alarm = 07:30:00
text  = "1979-05-27"
big   = 9223372036854775807
'))
#> List of 5
#>  $ when : POSIXct[1:1], format: "1979-05-27 15:32:00"
#>  $ day  : Date[1:1], format: "1979-05-27"
#>  $ alarm: chr "07:30:00"
#>  $ text : chr "1979-05-27"
#>  $ big  : 'toml_bigint' chr "9223372036854775807"
```

`datetimes = "keep"` returns date-times as RFC 3339 text, and
`local_time = "difftime"` returns times of day as seconds since
midnight. `big_integers` decides what happens past 2^53: a `toml_bigint`
(exact text, the default), the nearest double, or an error.

## Arrays

An array whose elements share a type becomes a vector; integers and
floats together become a `double` vector. Booleans never join the
numbers. Anything else is a list.

``` r

str(toml_parse("a = [1, 2]\nb = [1, 2.5]\nc = [true, 1]\nd = []\ne = [3]"))
#> List of 5
#>  $ a: int [1:2] 1 2
#>  $ b: num [1:2] 1 2.5
#>  $ c:List of 2
#>   ..$ : logi TRUE
#>   ..$ : int 1
#>  $ d: logi(0) 
#>  $ e: 'AsIs' int 3
```

A one-element array is marked with
[`I()`](https://rdrr.io/r/base/AsIs.html) so that writing it back gives
an array again, as `e` shows. `simplify = "none"` makes every array a
list.

## Data frames

`data_frame = TRUE` turns an array of tables into a data frame: one row
per table, columns in first-seen key order, `NA` where a table lacks a
key.

``` r

toml_parse(doc, data_frame = TRUE)$users
#>   name admin
#> 1  ana  TRUE
#> 2   bo    NA
```

## Write a document

[`toml_emit()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
writes a named list as TOML text;
[`toml_write()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
writes it to a file or connection.

``` r

cfg <- list(
  title = "Example",
  port = 8080,
  ratio = 0.75,
  started = as.Date("2026-10-08"),
  server = list(host = "localhost", tags = c("web", "api")),
  users = list(list(name = "ana"), list(name = "bo"))
)
cat(toml_emit(cfg))
#> title = "Example"
#> port = 8080
#> ratio = 0.75
#> started = 2026-10-08
#> 
#> [server]
#> host = "localhost"
#> tags = ["web", "api"]
#> 
#> [[users]]
#> name = "ana"
#> 
#> [[users]]
#> name = "bo"
```

- A table’s own values come first, then its sub-tables, as TOML
  requires.
- `port = 8080` is a double in R but is written as the integer a TOML
  reader expects; non-whole doubles are written in the shortest digits
  that read back exactly.
- A list of named lists, or a data frame, becomes an array of tables.
- The output is the same on every platform, and reads back:

``` r

identical(toml_parse(toml_emit(cfg))$users, cfg$users)
#> [1] TRUE
```

`NA` and `NULL` have no TOML form, so they are refused unless
`na = "omit"`. Arrays past `width` characters are written one element
per line, and `inline = n` writes small flat tables inline.

## Choose how one value is written

Markers change how a value is written, never what it reads back as:

``` r

cat(toml_emit(list(
  dependencies = list(
    serde = toml_inline(list(version = "1.0", features = "derive")),
    rand = "0.8"
  ),
  pattern = toml_literal("^\\d+\\.\\d+$"),
  motd = toml_multiline("Welcome!")
)))
#> pattern = '^\d+\.\d+$'
#> motd = """
#> Welcome!"""
#> 
#> [dependencies]
#> serde = { version = "1.0", features = "derive" }
#> rand = "0.8"
```

[`toml_inline()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
writes a table inline,
[`toml_literal()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
writes literal strings that need no escapes, and
[`toml_multiline()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
writes multi-line strings.

## Point at a value in the document

`positions = TRUE` records where every key and array element is defined,
so a check on a configuration can say where the problem is:

``` r

cfg <- toml_parse("[server]\nhost = 'localhost'\nport = 99999\n", positions = TRUE)
pos <- attr(cfg, "toml_positions")
pos
#>          path    type line column offset
#> 1      server   table    1      2      1
#> 2 server.host  string    2      1      9
#> 3 server.port integer    3      1     28
at <- pos[pos$path == "server.port", ]
sprintf("server.port (line %d, column %d) must be at most 65535", at$line, at$column)
#> [1] "server.port (line 3, column 1) must be at most 65535"
```

The `path` column uses the same syntax as `select`.

## Check a document

[`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
runs the whole check without building any R value. It returns `TRUE` or
`FALSE`, or with `error = TRUE` raises the reason:

``` r

toml_validate("a = 1\nb = 2")
#> [1] TRUE
toml_validate("a = 1\na = 2")
#> [1] FALSE
try(toml_validate("a = 1\na = 2", error = TRUE))
#> Error : TOML parse error at line 2, column 1: key defined twice
```

## Handle errors

Every error has a class, so it can be caught by kind. Parse errors carry
the `line`, `column`, byte `offset` and `kind` of the fault:

``` r

err <- tryCatch(toml_parse("[t]\nx = 1\n[t]\n"), zutoml_parse_error = function(e) e)
c(err$kind, err$line, err$column)
#> [1] "table_redefined" "3"               "2"
```

| Class | When |
|----|----|
| `zutoml_parse_error` | the document is not TOML |
| `zutoml_limit_error` | a limit was reached (`zutoml_size_limit`, `zutoml_depth_limit`, `zutoml_item_limit`, `zutoml_string_limit`) |
| `zutoml_unrepresentable` | valid TOML that R cannot hold, such as a string with U+0000 |
| `zutoml_missing_key` | `select` names a path the document does not have |
| `zutoml_unsupported_type`, `zutoml_na_error` | an R value with no TOML form, or `NA`/`NULL` |
| `zutoml_invalid_argument`, `zutoml_io_error` | a bad argument; a file that cannot be read or written |

All of them inherit from `zutoml_error`. See
[`?"zutoml-conditions"`](https://pedrobtz.github.io/zutoml/reference/zutoml-conditions.md).

## Untrusted input

Four limits bound what a document can make zutoml do, and are checked
before any R value is built:

``` r

try(toml_parse(paste0("a = ", strrep("[", 200)), max_depth = 64))
#> Error : TOML limit reached at line 1, column 69: the document nests deeper than max_depth = 64
```

| Argument | Default | Bounds |
|----|----|----|
| `max_size` | 64 MiB | the document’s bytes; [`toml_read()`](https://pedrobtz.github.io/zutoml/reference/toml_read.md) never reads past it |
| `max_depth` | 128 | nested tables and arrays (at most 1023) |
| `max_items` | 1e6 | keys plus array elements |
| `max_string` | 2^31 - 1 | one string’s or key’s bytes |

## TOML versions

zutoml reads TOML 1.1.0 by default, which adds `\e` and `\xHH` escapes,
times without seconds, and newlines and trailing commas in inline
tables. `version = "1.0.0"` reads strictly. The emitter always writes
text that TOML 1.0.0 readers accept.

``` r

toml_parse("t = 07:30")$t
#> [1] "07:30:00"
try(toml_parse("t = 07:30", version = "1.0.0"))
#> Error : TOML parse error at line 1, column 5: not a valid TOML date or time
```
