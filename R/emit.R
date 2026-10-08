#' Write R values as TOML
#'
#' `toml_emit()` turns a named list into the text of a TOML document;
#' `toml_write()` writes that text to a file or connection. The output is
#' deterministic (the same value gives the same bytes on every platform) and
#' is always text [toml_parse()] reads back.
#'
#' @section R to TOML:
#'
#' | R | TOML |
#' |---|---|
#' | `character` | basic string, or literal with `strings = "literal"` |
#' | `integer` | integer |
#' | `double`, whole, within 64-bit range, not `-0` | integer |
#' | any other `double` | float, in the shortest digits that read back exactly |
#' | `logical` | boolean |
#' | `POSIXct` with a time zone | offset date-time, in UTC (`Z`) |
#' | `POSIXct` with no time zone (`tzone = ""`) | local date-time |
#' | `Date` | local date |
#' | `difftime` in seconds, from 0 to a day | local time |
#' | [toml_bigint()] | integer |
#' | `factor` | its labels, as strings |
#' | a vector of length one | the value; [I()] makes it an array of one |
#' | a longer vector | array |
#' | named `list` | table, or an inline table inside an array |
#' | unnamed `list` of named lists | array of tables (`[[key]]`) |
#' | other unnamed `list` | array |
#' | `data.frame` | array of tables, one per row; `NA` cells are left out |
#'
#' A table's own keys are written first, in the list's order, then its
#' sub-tables: TOML has no other way to say which keys belong to which
#' table. A sub-table that holds only sub-tables gets no header of its own.
#' A string with a newline is written as a multi-line string.
#'
#' Refused with `zutoml_unsupported_type`: complex and raw vectors,
#' functions, environments, `POSIXlt`, matrices and arrays with `dim`, and
#' atomic vectors of other classes. `NA` and `NULL`, which TOML has no form
#' for, raise `zutoml_na_error` unless `na = "omit"`. Each condition
#' carries `path`, the key path of the value at fault, as `a.b[3].c`.
#'
#' @param x A named list: the document's top-level table.
#' @param file For `toml_write()`, a path or a connection.
#' @param indent Spaces before each element of an array written one element
#'   per line.
#' @param inline A nested named list with at most this many keys, none of
#'   them a list, is written as an inline table (`{ x = 1, y = 2 }`) rather
#'   than under its own header. `0`, the default, never does.
#' @param width An array whose line would pass this column is written one
#'   element per line. `0` never wraps.
#' @param na `"error"` (the default) refuses `NA` and `NULL`; `"omit"` leaves
#'   out a key whose value is `NA` or `NULL`, and drops such elements from
#'   arrays with a warning.
#' @param strings `"basic"` (the default) writes double-quoted strings;
#'   `"literal"` writes single-quoted strings where that needs no escapes.
#' @param max_depth The deepest nesting of tables and arrays written,
#'   counted as [toml_parse()] counts it; at most 1023.
#' @param ... For `toml_write()`, passed to `toml_emit()`.
#'
#' @return `toml_emit()`: a single string, UTF-8, with `\n` line endings and a
#'   final newline. `toml_write()`: `file`, invisibly.
#' @export
#' @examples
#' cfg <- list(
#'   title = "Example",
#'   port = 8080,
#'   tags = c("a", "b"),
#'   owner = list(name = "Tom", since = as.Date("1979-05-27")),
#'   servers = list(
#'     list(name = "alpha", ip = "10.0.0.1"),
#'     list(name = "beta", ip = "10.0.0.2")
#'   )
#' )
#' cat(toml_emit(cfg))
#'
#' identical(toml_parse(toml_emit(cfg))$port, 8080L)
#'
#' path <- tempfile(fileext = ".toml")
#' toml_write(cfg, path)
#' toml_parse(readLines(path) |> paste(collapse = "\n"))$owner$name
toml_emit <- function(
  x,
  indent = 2L,
  inline = 0L,
  width = 80L,
  na = c("error", "omit"),
  strings = c("basic", "literal"),
  max_depth = 128L
) {
  if (!is.list(x) || is.data.frame(x) || (length(x) && is.null(names(x)))) {
    ztm_invalid_argument(
      "x",
      paste(
        "`x` must be a named list: a TOML document is a table.",
        "Put a data frame or an unnamed list under a key, as list(rows = x)."
      )
    )
  }
  if (!length(x)) {
    x <- stats::setNames(list(), character())
  }
  indent <- ztm_check_count(indent, "indent")
  inline <- ztm_check_count(inline, "inline")
  width <- ztm_check_count(width, "width")
  na_omit <- ztm_check_choice(na, c("error", "omit"), "na") == 1L
  literal <- ztm_check_choice(strings, c("basic", "literal"), "strings") == 1L
  max_depth <- ztm_check_depth(max_depth)
  x <- ztm_wallclocks(x)
  out <- .Call(
    zutoml_emit,
    x,
    indent,
    inline,
    width,
    na_omit,
    literal,
    as.integer(max_depth)
  )
  if (out$status != "ok") {
    ztm_raise_emit(out, max_depth)
  }
  if (out$dropped) {
    warning(
      "na = \"omit\" dropped NA or NULL elements from arrays.",
      call. = FALSE
    )
  }
  out$text
}

#' @rdname toml_emit
#' @export
toml_write <- function(x, file, ...) {
  text <- toml_emit(x, ...)
  bytes <- charToRaw(enc2utf8(text))
  if (inherits(file, "connection")) {
    ok <- tryCatch(
      {
        if (summary(file)$text == "binary") {
          writeBin(bytes, file)
        } else {
          writeLines(text, file, sep = "", useBytes = TRUE)
        }
        TRUE
      },
      error = function(e) conditionMessage(e)
    )
  } else if (is.character(file) && length(file) == 1L && !is.na(file)) {
    ok <- tryCatch(
      {
        con <- file(file, "wb")
        on.exit(close(con))
        writeBin(bytes, con)
        TRUE
      },
      error = function(e) conditionMessage(e),
      warning = function(w) conditionMessage(w)
    )
  } else {
    ztm_invalid_argument("file", "`file` must be a path or a connection.")
  }
  if (!isTRUE(ok)) {
    ztm_abort("zutoml_io_error", paste0("cannot write the TOML document: ", ok))
  }
  invisible(file)
}

ztm_check_count <- function(x, arg) {
  if (
    !is.numeric(x) ||
      length(x) != 1L ||
      is.na(x) ||
      x < 0 ||
      x != floor(x) ||
      x > 1e6
  ) {
    ztm_invalid_argument(
      arg,
      paste0("`", arg, "` must be a whole number from 0.")
    )
  }
  as.integer(x)
}

# A POSIXct with no time zone is a local date-time: its wall-clock time in
# the session's zone, which only R knows. It reaches C as canonical text of
# class ztm_wallclock (src/ztm_emit.c writes it as it is).
ztm_wallclocks <- function(x) {
  rapply(
    x,
    function(v) {
      tz <- attr(v, "tzone")
      if (!is.null(tz) && !identical(tz, "")) {
        return(v)
      }
      asis <- inherits(v, "AsIs")
      lt <- as.POSIXlt(v)
      year <- lt$year + 1900L
      if (any(!is.na(year) & (year < 0 | year > 9999))) {
        ztm_invalid_argument("x", "a date-time outside the years 0000 to 9999")
      }
      whole <- floor(lt$sec)
      micro <- round((lt$sec - whole) * 1e6)
      carry <- micro >= 1e6
      micro[carry] <- 0
      whole[carry] <- whole[carry] + 1
      frac <- ifelse(
        micro == 0,
        "",
        ifelse(
          micro %% 1000 == 0,
          sprintf(".%03d", micro %/% 1000),
          sprintf(".%06d", micro)
        )
      )
      text <- sprintf(
        "%04d-%02d-%02dT%02d:%02d:%02d%s",
        year,
        lt$mon + 1L,
        lt$mday,
        lt$hour,
        lt$min,
        as.integer(whole),
        frac
      )
      text[is.na(v)] <- NA_character_
      out <- structure(text, class = "ztm_wallclock")
      if (asis) {
        out <- I(out)
      }
      out
    },
    classes = "POSIXct",
    how = "replace"
  )
}

ztm_raise_emit <- function(out, max_depth) {
  path <- if (is.na(out$path)) "" else out$path
  where <- if (nzchar(path)) paste0(" at `", path, "`") else ""
  detail <- if (is.na(out$detail)) NULL else out$detail
  switch(
    out$status,
    unsupported_type = ztm_abort(
      "zutoml_unsupported_type",
      paste0(
        "cannot write as TOML",
        where,
        if (is.null(detail)) {
          ": no TOML form for this R value"
        } else {
          paste0(": ", detail)
        }
      ),
      path = path
    ),
    na = ztm_abort(
      "zutoml_na_error",
      paste0(
        "TOML has no NA or NULL",
        where,
        "; use na = \"omit\" to leave such values out"
      ),
      path = path
    ),
    invalid = ztm_abort(
      "zutoml_invalid_argument",
      paste0("cannot write as TOML", where, ": ", detail),
      arg = "x",
      path = path
    ),
    depth_limit = ztm_abort(
      c("zutoml_depth_limit", "zutoml_limit_error"),
      paste0(
        "TOML limit reached",
        where,
        ": the value nests deeper than max_depth = ",
        max_depth
      ),
      path = path,
      kind = "depth_limit",
      limit = "max_depth",
      limit_value = max_depth
    )
  )
}
