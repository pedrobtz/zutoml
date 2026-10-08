#' Say how one value is written as TOML
#'
#' Markers for [toml_emit()], which otherwise chooses each value's form by
#' fixed rules. They change how a value is written, never what it is:
#' [toml_parse()] reads the text back as the unmarked value.
#'
#' * `toml_inline()` writes a named list as an inline table
#'   (`point = { x = 1, y = 2 }`) rather than under its own `[header]`, and
#'   an unnamed list of named lists as an array of inline tables rather than
#'   an array of tables. A `Cargo.toml` dependency such as
#'   `serde = { version = "1.0", features = ["derive"] }` is written this
#'   way.
#' * `toml_literal()` writes strings as literal strings, which need no
#'   escapes: `'C:\Users\tom'`. A string with a single quote or a newline is
#'   a multi-line literal string. One that no literal string can hold (a
#'   control character other than tab and newline, or three single quotes in
#'   a row) raises `zutoml_invalid_argument`.
#' * `toml_multiline()` writes strings as multi-line basic strings, even
#'   without a newline.
#'
#' Like [I()], which writes a vector of one as an array, the markers are
#' classes on the value; any other class it has is kept.
#'
#' @param x For `toml_inline()`, a list; for the others, a character vector.
#' @return `x`, with the marker class added.
#' @name toml-markers
#' @examples
#' cat(toml_emit(list(
#'   dependencies = list(
#'     serde = toml_inline(list(version = "1.0", features = c("derive", "std"))),
#'     rand = "0.8"
#'   ),
#'   path = toml_literal("C:\\Users\\tom"),
#'   motd = toml_multiline("Welcome!")
#' )))
NULL

#' @rdname toml-markers
#' @export
toml_inline <- function(x) {
  if (!is.list(x) || is.data.frame(x)) {
    ztm_invalid_argument("x", "`x` must be a list, named or of named lists.")
  }
  ztm_add_class(x, "toml_inline")
}

#' @rdname toml-markers
#' @export
toml_literal <- function(x) {
  if (!is.character(x)) {
    ztm_invalid_argument("x", "`x` must be a character vector.")
  }
  ztm_add_class(x, "toml_literal")
}

#' @rdname toml-markers
#' @export
toml_multiline <- function(x) {
  if (!is.character(x)) {
    ztm_invalid_argument("x", "`x` must be a character vector.")
  }
  ztm_add_class(x, "toml_multiline")
}

ztm_add_class <- function(x, cls) {
  class(x) <- unique(c(cls, oldClass(x)))
  x
}
