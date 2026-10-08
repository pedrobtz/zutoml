# Configuration files in TOML

TOML is the configuration format of Cargo, Python packaging
(`pyproject.toml`), Hugo and many tools. zutoml reads it into ordinary R
values and writes R values back as TOML.

``` r

library(zutoml)
```

## Reading a `pyproject.toml`

``` r

pyproject <- '
[project]
name = "spam-eggs"
version = "2020.0.0"
dependencies = ["httpx", "gidgethub[httpx]>4.0.0"]
requires-python = ">= 3.8"
authors = [
  {name = "Pradyun Gedam", email = "pradyun@example.com"},
  {name = "Tzu-Ping Chung", email = "tzu-ping@example.com"},
]

[project.optional-dependencies]
cli = ["rich", "click"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
'
p <- toml_parse(pyproject)
p$project$name
#> [1] "spam-eggs"
p$project$dependencies
#> [1] "httpx"                  "gidgethub[httpx]>4.0.0"
p$`build-system`$requires
#> [1] "hatchling"
```

Tables become named lists, with their keys in the order the file gives
them. An array becomes a vector when its elements share a type. A
one-element array, such as `requires` above, is marked with
[`I()`](https://rdrr.io/r/base/AsIs.html) so that writing it back gives
an array again.

To read only part of a document, give a path. The whole file is still
checked, but only that part becomes R values:

``` r

toml_parse(pyproject, select = "project.optional-dependencies.cli")
#> [1] "rich"  "click"
toml_parse(pyproject, select = "project.authors[2].email")
#> [1] "tzu-ping@example.com"
```

An array of tables, like `authors`, is a list of named lists, or a data
frame on request:

``` r

toml_parse(pyproject, data_frame = TRUE)$project$authors
#>             name                email
#> 1  Pradyun Gedam  pradyun@example.com
#> 2 Tzu-Ping Chung tzu-ping@example.com
```

## Types come from the document

TOML types every value by its syntax, so zutoml never has to guess:

``` r

x <- toml_parse('
released = 1979-05-27
built = 1979-05-27T07:32:00Z
local = 1979-05-27T07:32:00
alarm = 07:30:00
quoted = "1979-05-27"
')
str(x)
#> List of 5
#>  $ released: Date[1:1], format: "1979-05-27"
#>  $ built   : POSIXct[1:1], format: "1979-05-27 07:32:00"
#>  $ local   : POSIXct[1:1], format: "1979-05-27 07:32:00"
#>  $ alarm   : chr "07:30:00"
#>  $ quoted  : chr "1979-05-27"
```

`released` is a `Date`, `built` a `POSIXct` in UTC, `local` a `POSIXct`
in your session’s time zone, and `quoted` stays a string. Use
`datetimes = "keep"` to get date-times as text, and
`local_time = "difftime"` for times of day as seconds since midnight.

Integers beyond 2^53, which a double cannot hold exactly, are kept as
exact decimal text:

``` r

toml_parse("id = 9223372036854775807")$id
#> <toml_bigint[1]>
#> [1] 9223372036854775807
```

## Reading `Cargo.toml` from a file

``` r

cargo <- tempfile(fileext = ".toml")
writeLines(c(
  "[package]",
  'name = "hello"',
  'version = "0.1.0"',
  'edition = "2021"',
  "",
  "[dependencies]",
  'serde = { version = "1.0", features = ["derive"] }',
  'rand = "0.8"'
), cargo)
deps <- toml_read(cargo)$dependencies
deps$serde$features
#> [1] "derive"
```

## Writing a configuration

[`toml_emit()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
writes a named list as TOML text, and
[`toml_write()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
writes it to a file:

``` r

config <- list(
  title = "My service",
  port = 8080,
  debug = FALSE,
  started = as.Date("2026-10-08"),
  database = list(host = "localhost", ports = c(5432L, 5433L)),
  servers = list(
    list(name = "alpha", ip = "10.0.0.1"),
    list(name = "beta", ip = "10.0.0.2")
  )
)
cat(toml_emit(config))
#> title = "My service"
#> port = 8080
#> debug = false
#> started = 2026-10-08
#> 
#> [database]
#> host = "localhost"
#> ports = [5432, 5433]
#> 
#> [[servers]]
#> name = "alpha"
#> ip = "10.0.0.1"
#> 
#> [[servers]]
#> name = "beta"
#> ip = "10.0.0.2"
```

`port = 8080` is a double in R, since R has no integer literal, but it
is written as the integer a TOML reader expects. A list of named lists
becomes an array of tables. The output is the same on every platform,
and reads back:

``` r

identical(toml_parse(toml_emit(config))$servers, config$servers)
#> [1] TRUE
```

Markers say how one value is written. A `Cargo.toml` dependency, for
example, is usually an inline table:

``` r

cat(toml_emit(list(dependencies = list(
  serde = toml_inline(list(version = "1.0", features = "derive")),
  rand = "0.8"
))))
#> [dependencies]
#> serde = { version = "1.0", features = "derive" }
#> rand = "0.8"
```

[`toml_literal()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
writes strings as literal strings, which need no escapes (Windows paths,
regular expressions), and
[`toml_multiline()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
as multi-line strings.

## Pointing at the value at fault

With `positions = TRUE`, the result records where each key is, so a
check on a configuration can say where the problem is:

``` r

cfg <- toml_parse("[server]\nhost = 'localhost'\nport = 99999\n", positions = TRUE)
pos <- attr(cfg, "toml_positions")
pos
#>          path    type line column offset
#> 1      server   table    1      2      1
#> 2 server.host  string    2      1      9
#> 3 server.port integer    3      1     28
if (cfg$server$port > 65535) {
  at <- pos[pos$path == "server.port", ]
  message("server.port at line ", at$line, ", column ", at$column, " is above 65535")
}
#> server.port at line 3, column 1 is above 65535
```

## When things go wrong

Every error has a class, and parse errors say where:

``` r

err <- tryCatch(
  toml_parse("[server]\nport = 80\nport = 8080\n"),
  zutoml_parse_error = function(e) e
)
conditionMessage(err)
#> [1] "TOML parse error at line 3, column 1: key defined twice"
c(err$line, err$column)
#> [1] 3 1
err$kind
#> [1] "duplicate_key"
```

[`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
checks a document without building it, and untrusted input is bounded by
`max_size`, `max_depth`, `max_items` and `max_string`. See
`?zutoml-conditions` for every class.
