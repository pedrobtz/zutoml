# Parse a TOML document

Reads a TOML document into ordinary R values: each table becomes a named
list with its keys in document order, each array a vector or a list, and
each value the R type below. Types come from the document's syntax:
`"2024-01-01"` stays a string and `2024-01-01` becomes a `Date`. The
whole document is checked, as by
[`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md),
before any R value is built.

## Usage

``` r
toml_parse(
  x,
  version = c("1.1.0", "1.0.0"),
  simplify = c("preserve", "none"),
  data_frame = FALSE,
  big_integers = c("bigint", "double", "error"),
  datetimes = c("convert", "keep"),
  local_time = c("character", "difftime"),
  positions = FALSE,
  max_size = 64 * 1024^2,
  max_depth = 128L,
  max_items = 1e+06,
  max_string = 2^31 - 1
)
```

## Arguments

- x:

  A TOML document: a single string, or a raw vector of UTF-8 bytes.

- version:

  The TOML version to read: `"1.1.0"` (the default) or `"1.0.0"`, which
  refuses the forms 1.1.0 added (`\e` and `\xHH` escapes, times without
  seconds, newlines and a trailing comma in inline tables).

- simplify:

  `"preserve"` (the default) turns arrays whose elements share a type
  into vectors; `"none"` makes every array a list.

- data_frame:

  If `TRUE`, an array whose elements are all tables becomes a data
  frame: one row per table, columns in first-seen key order, missing
  keys `NA`. Columns whose values do not share a type are lists. More
  than `getOption("zutoml.max_df_cells", 1e7)` cells raises
  `zutoml_limit_error`, since rows that share no keys make the frame
  quadratic in size.

- big_integers:

  For integers beyond 2^53, which a double cannot hold exactly:
  `"bigint"` (the default) returns a
  [`toml_bigint()`](https://pedrobtz.github.io/zutoml/reference/toml_bigint.md)
  vector of exact decimal text; `"double"` the nearest double; `"error"`
  raises `zutoml_unrepresentable`.

- datetimes:

  `"convert"` (the default) returns `POSIXct` and `Date`; `"keep"`
  returns the date-times as text.

- local_time:

  `"character"` (the default) returns a local time as its text;
  `"difftime"` as seconds since midnight.

- positions:

  If `TRUE`, the result carries an attribute `"toml_positions"`: a data
  frame with one row per key and array element, in the order of the
  parsed value, giving its `path` in TOML key syntax (`servers[2].ip`,
  with keys quoted where TOML needs it, and array elements numbered from
  1), its `type` (`"table"`, `"inline_table"`, `"array_of_tables"`,
  `"array"`, `"string"`, `"integer"`, `"float"`, `"bool"`, `"datetime"`,
  `"datetime-local"`, `"date-local"` or `"time-local"`), and the `line`,
  `column` (1-based, in characters) and byte `offset` (0-based) where it
  is defined: a key's position for a keyed value, the `[[header]]` for
  each table of an array of tables. Code that checks a configuration can
  then say where a value is wrong.

- max_size:

  The largest document accepted, in bytes, or `Inf`.

- max_depth:

  The deepest nesting of tables and arrays, counting both; at most 1023.

- max_items:

  The most keys plus array elements, or `Inf`.

- max_string:

  The longest string or key, in decoded bytes, or `Inf`.

## Value

A named list, one element per top-level key.

## TOML to R

|  |  |
|----|----|
| TOML | R |
| string | `character` (UTF-8) |
| integer | `integer`; `double` beyond R's integer range (and for -2^31); beyond 2^53, see `big_integers` |
| float | `double`; `inf` and `nan` as `Inf` and `NaN` |
| boolean | `logical` |
| offset date-time | `POSIXct` in UTC |
| local date-time | `POSIXct` in the session's time zone (`tzone = ""`) |
| local date | `Date` |
| local time | `character` (`"07:32:00"`), or `difftime` in seconds |
| table, inline table | named `list` |
| array of tables | unnamed `list` of named lists, or a `data.frame` |
| array | a vector when its elements share a type, else a `list` |

An array becomes a vector when all its elements are strings, all
booleans, all numbers, all dates, or all date-times of one kind. Numbers
widen: integers with floats give a `double` vector. Booleans never join
the numbers. An empty array is `logical(0)`. A one-element array that
becomes a vector is marked with
[`I()`](https://rdrr.io/r/base/AsIs.html), so that writing it back gives
an array again. Anything else is a list. `simplify = "none"` makes every
array a list.

With `datetimes = "keep"`, date-times are returned as RFC 3339 text
instead (`"1979-05-27T07:32:00Z"`, a zero offset written `Z`, the
fraction in 0, 3, 6 or 9 digits). Fractions past nanoseconds are
truncated, as TOML requires; a `POSIXct` holds microseconds.

Valid TOML that R cannot hold raises `zutoml_unrepresentable`: a string
or key containing U+0000, a float beyond the range of a double, or an
integer beyond 2^53 with `big_integers = "error"`.

## See also

[`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
to check a document without building it;
[zutoml-conditions](https://pedrobtz.github.io/zutoml/reference/zutoml-conditions.md)
for the errors.

## Examples

``` r
doc <- '
title = "TOML Example"
ports = [8000, 8001, 8002]

[owner]
name = "Tom Preston-Werner"
dob = 1979-05-27T07:32:00-08:00

[[products]]
name = "Hammer"
sku = 738594937

[[products]]
name = "Nail"
sku = 284758393
color = "gray"
'
x <- toml_parse(doc)
x$owner$dob
#> [1] "1979-05-27 15:32:00 UTC"
x$ports
#> [1] 8000 8001 8002

toml_parse(doc, data_frame = TRUE)$products
#>     name       sku color
#> 1 Hammer 738594937  <NA>
#> 2   Nail 284758393  gray

# Where each value is, for messages about the document:
pos <- attr(toml_parse(doc, positions = TRUE), "toml_positions")
pos[pos$path == "owner.dob", ]
#>        path     type line column offset
#> 8 owner.dob datetime    7      1     88
```
