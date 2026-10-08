#' Check that a document is valid TOML
#'
#' Runs the whole check phase of [toml_parse()] (the lexer, the grammar, the
#' rules for defining tables and keys, every value, and the limits) without
#' building any R value. It is exactly the check `toml_parse()` makes, with
#' the same limits: the two disagree only where a document is valid TOML
#' that R cannot hold, such as a string containing U+0000.
#'
#' @param x A TOML document: a single string, or a raw vector of UTF-8
#'   bytes.
#' @param version The TOML version to read: `"1.1.0"` (the default) or
#'   `"1.0.0"`, which refuses the forms 1.1.0 added (`\e` and `\xHH` escapes,
#'   times without seconds, newlines and a trailing comma in inline tables).
#' @param max_size The largest document accepted, in bytes, or `Inf`.
#' @param max_depth The deepest nesting of tables and arrays, counting both;
#'   at most 1023.
#' @param max_items The most keys plus array elements, or `Inf`.
#' @param max_string The longest string or key, in decoded bytes, or `Inf`.
#' @param error If `FALSE` (the default), return `FALSE` for a document that
#'   is not valid. If `TRUE`, raise the condition instead, so the caller
#'   learns why and where.
#'
#' @return `TRUE` when `x` is valid TOML within the limits. Otherwise `FALSE`,
#'   or with `error = TRUE` a condition of class `zutoml_parse_error` or
#'   `zutoml_limit_error` (see [zutoml-conditions]) carrying the `line`,
#'   `column`, byte `offset` and `kind` of the fault.
#' @export
#' @examples
#' toml_validate('title = "TOML"\n[owner]\nname = "Tom"\n')
#' toml_validate("a = 1\na = 2\n")
#'
#' # Why not, and where:
#' tryCatch(
#'   toml_validate("a = 1\na = 2\n", error = TRUE),
#'   zutoml_parse_error = function(e) c(e$kind, e$line, e$column)
#' )
toml_validate <- function(
  x,
  version = c("1.1.0", "1.0.0"),
  max_size = 64 * 1024^2,
  max_depth = 128L,
  max_items = 1e6,
  max_string = 2^31 - 1,
  error = FALSE
) {
  ztm_check_flag(error, "error")
  bytes <- ztm_input_bytes(x)
  fault <- .Call(
    zutoml_check,
    bytes,
    ztm_check_version(version),
    ztm_check_limit(max_size, "max_size"),
    ztm_check_depth(max_depth),
    ztm_check_limit(max_items, "max_items"),
    ztm_check_limit(max_string, "max_string")
  )
  if (is.null(fault)) {
    return(TRUE)
  }
  if (error) {
    ztm_raise_fault(fault)
  }
  FALSE
}
