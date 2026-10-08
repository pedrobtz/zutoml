#' Parse a TOML document
#'
#' Reads a TOML document into ordinary R values: each table becomes a named
#' list with its keys in document order, each array a vector or a list, and
#' each value the R type below. Types come from the document's syntax:
#' `"2024-01-01"` stays a string and `2024-01-01` becomes a `Date`. The whole
#' document is checked, as by [toml_validate()], before any R value is
#' built.
#'
#' @section TOML to R:
#'
#' | TOML | R |
#' |---|---|
#' | string | `character` (UTF-8) |
#' | integer | `integer`; `double` beyond R's integer range (and for -2^31); beyond 2^53, see `big_integers` |
#' | float | `double`; `inf` and `nan` as `Inf` and `NaN` |
#' | boolean | `logical` |
#' | offset date-time | `POSIXct` in UTC |
#' | local date-time | `POSIXct` in the session's time zone (`tzone = ""`) |
#' | local date | `Date` |
#' | local time | `character` (`"07:32:00"`), or `difftime` in seconds |
#' | table, inline table | named `list` |
#' | array of tables | unnamed `list` of named lists, or a `data.frame` |
#' | array | a vector when its elements share a type, else a `list` |
#'
#' An array becomes a vector when all its elements are strings, all
#' booleans, all numbers, all dates, or all date-times of one kind. Numbers
#' widen: integers with floats give a `double` vector. Booleans never join
#' the numbers. An empty array is `logical(0)`. A one-element array that
#' becomes a vector is marked with [I()], so that writing it back gives an
#' array again. Anything else is a list. `simplify = "none"` makes every
#' array a list.
#'
#' With `datetimes = "keep"`, date-times are returned as RFC 3339 text
#' instead (`"1979-05-27T07:32:00Z"`, a zero offset written `Z`, the fraction
#' in 0, 3, 6 or 9 digits). Fractions past nanoseconds are truncated, as
#' TOML requires; a `POSIXct` holds microseconds.
#'
#' Valid TOML that R cannot hold raises `zutoml_unrepresentable`: a string or
#' key containing U+0000, a float beyond the range of a double, or an
#' integer beyond 2^53 with `big_integers = "error"`.
#'
#' @inheritParams toml_validate
#' @param select `NULL` (the default) returns the whole document. A path
#'   returns only the value there: a string in TOML key syntax, as the
#'   positions table writes it (`"tool.poetry"`; `'"a.b".c'` for a key with a
#'   dot; `"products[2].name"` into arrays, counting from 1), or a vector of
#'   two or more keys taken as they are (`c("tool", "poetry")`). The whole
#'   document is still read and checked, since TOML lets a table be added to
#'   anywhere in it, but only the selected part becomes R values. A path the
#'   document does not have raises `zutoml_missing_key`, with `path` and
#'   `found`, the part of the path that does exist.
#' @param simplify `"preserve"` (the default) turns arrays whose elements
#'   share a type into vectors; `"none"` makes every array a list.
#' @param data_frame If `TRUE`, an array whose elements are all tables becomes
#'   a data frame: one row per table, columns in first-seen key order,
#'   missing keys `NA`. Columns whose values do not share a type are lists.
#'   More than `getOption("zutoml.max_df_cells", 1e7)` cells raises
#'   `zutoml_limit_error`, since rows that share no keys make the frame
#'   quadratic in size.
#' @param big_integers For integers beyond 2^53, which a double cannot hold
#'   exactly: `"bigint"` (the default) returns a [toml_bigint()] vector of
#'   exact decimal text; `"double"` the nearest double; `"error"` raises
#'   `zutoml_unrepresentable`.
#' @param datetimes `"convert"` (the default) returns `POSIXct` and `Date`;
#'   `"keep"` returns the date-times as text.
#' @param local_time `"character"` (the default) returns a local time as its
#'   text; `"difftime"` as seconds since midnight.
#' @param positions If `TRUE`, the result carries an attribute
#'   `"toml_positions"`: a data frame with one row per key and array element,
#'   in the order of the parsed value, giving its `path` in TOML key syntax
#'   (`servers[2].ip`, with keys quoted where TOML needs it, and array
#'   elements numbered from 1), its `type` (`"table"`, `"inline_table"`,
#'   `"array_of_tables"`, `"array"`, `"string"`, `"integer"`, `"float"`,
#'   `"bool"`, `"datetime"`, `"datetime-local"`, `"date-local"` or
#'   `"time-local"`), and the `line`, `column` (1-based, in characters) and
#'   byte `offset` (0-based) where it is defined: a key's position for a
#'   keyed value, the `[[header]]` for each table of an array of tables.
#'   Code that checks a configuration can then say where a value is wrong.
#'
#' @return A named list, one element per top-level key; with `select`, the
#'   value at that path.
#' @seealso [toml_validate()] to check a document without building it;
#'   [zutoml-conditions] for the errors.
#' @export
#' @examples
#' doc <- '
#' title = "TOML Example"
#' ports = [8000, 8001, 8002]
#'
#' [owner]
#' name = "Tom Preston-Werner"
#' dob = 1979-05-27T07:32:00-08:00
#'
#' [[products]]
#' name = "Hammer"
#' sku = 738594937
#'
#' [[products]]
#' name = "Nail"
#' sku = 284758393
#' color = "gray"
#' '
#' x <- toml_parse(doc)
#' x$owner$dob
#' x$ports
#'
#' toml_parse(doc, data_frame = TRUE)$products
#'
#' # Only part of it:
#' toml_parse(doc, select = "owner")
#' toml_parse(doc, select = "products[2].color")
#'
#' # Where each value is, for messages about the document:
#' pos <- attr(toml_parse(doc, positions = TRUE), "toml_positions")
#' pos[pos$path == "owner.dob", ]
toml_parse <- function(
  x,
  select = NULL,
  version = c("1.1.0", "1.0.0"),
  simplify = c("preserve", "none"),
  data_frame = FALSE,
  big_integers = c("bigint", "double", "error"),
  datetimes = c("convert", "keep"),
  local_time = c("character", "difftime"),
  positions = FALSE,
  max_size = 64 * 1024^2,
  max_depth = 128L,
  max_items = 1e6,
  max_string = 2^31 - 1
) {
  bytes <- ztm_input_bytes(x)
  steps <- ztm_select_steps(select)
  simplify <- ztm_check_choice(simplify, c("preserve", "none"), "simplify") ==
    0L
  positions <- ztm_check_flag(positions, "positions")
  data_frame <- ztm_check_flag(data_frame, "data_frame")
  datetimes <- ztm_check_choice(datetimes, c("convert", "keep"), "datetimes")
  out <- .Call(
    zutoml_parse,
    bytes,
    ztm_check_version(version),
    ztm_check_limit(max_size, "max_size"),
    ztm_check_depth(max_depth),
    ztm_check_limit(max_items, "max_items"),
    ztm_check_limit(max_string, "max_string"),
    simplify,
    ztm_check_choice(
      big_integers,
      c("bigint", "double", "error"),
      "big_integers"
    ),
    datetimes,
    ztm_check_choice(local_time, c("character", "difftime"), "local_time"),
    positions,
    steps
  )
  if (!is.null(out$fault)) {
    ztm_raise_fault(out$fault)
  }
  if (!is.null(out$missing)) {
    ztm_raise_missing(steps, out$missing)
  }
  value <- out$value
  if (out$has_local) {
    # rapply() walks lists; a selected scalar is wrapped for it.
    value <- if (is.list(value)) ztm_localise(value) else ztm_localise(list(value))[[1L]]
  }
  if (data_frame) {
    value <- ztm_data_frames(value)
  }
  if (positions) {
    pos <- out$positions
    attr(value, "toml_positions") <- structure(
      pos,
      class = "data.frame",
      row.names = .set_row_names(length(pos$path))
    )
  }
  value
}

# Local date-times arrive as wall-clock seconds read as if UTC, with tzone
# "<local>" (src/ztm_build.c): R has no C API for the session's time zone.
# Here they become the same wall-clock time in the session's zone, tzone "".
ztm_localise <- function(x) {
  rapply(
    x,
    function(v) {
      if (!identical(attr(v, "tzone"), "<local>")) {
        return(v)
      }
      asis <- inherits(v, "AsIs")
      lt <- as.POSIXlt(structure(
        unclass(v),
        class = c("POSIXct", "POSIXt"),
        tzone = "UTC"
      ))
      attr(lt, "tzone") <- ""
      lt$isdst <- -1L
      lt$zone <- NULL
      lt$gmtoff <- NULL
      out <- as.POSIXct(lt, tz = "")
      attr(out, "tzone") <- ""
      if (asis) {
        out <- I(out)
      }
      out
    },
    classes = "POSIXct",
    how = "replace"
  )
}
