# The condition hierarchy of design section 11. The class is the contract:
# callers branch on it and on the fields below, never on the message.

#' Conditions raised by zutoml
#'
#' Every error zutoml raises carries a condition class, so it can be caught
#' by kind rather than by matching the message, which may change. Every
#' class below inherits from `zutoml_error`.
#'
#' \describe{
#'   \item{`zutoml_invalid_argument`}{An argument was unusable, or a value
#'     cannot be written as TOML as given, such as a list with partial
#'     names or a string that is not valid UTF-8. Carries `arg`, the
#'     argument at fault.}
#'   \item{`zutoml_parse_error`}{The document is not TOML. Carries `line`
#'     and `column` (1-based, in characters), `offset` (0-based, in bytes)
#'     and `kind`, the name of the rule broken, such as `"bad_escape"` or
#'     `"table_redefined"`.}
#'   \item{`zutoml_unrepresentable`}{The document is valid TOML but holds a
#'     value R cannot: a string containing U+0000, a string longer than an R
#'     string, or an integer beyond 2^53 with `big_integers = "error"`.}
#'   \item{`zutoml_unsupported_type`}{An R value has no TOML form, such as a
#'     function, a raw vector or a matrix. Carries `path`, the key path of
#'     the value, as `a.b[3].c`.}
#'   \item{`zutoml_na_error`}{An `NA` or `NULL` value with `na = "error"`.
#'     Carries `path`.}
#'   \item{`zutoml_limit_error`}{A limit was reached. The subclasses
#'     `zutoml_size_limit`, `zutoml_depth_limit`, `zutoml_item_limit` and
#'     `zutoml_string_limit` name which one. Carries `limit`, the argument's
#'     name, such as `"max_depth"`, and `limit_value`.}
#'   \item{`zutoml_io_error`}{A file or connection could not be read or
#'     written.}
#' }
#'
#' @name zutoml-conditions
#' @examples
#' tryCatch(
#'   stop(structure(
#'     class = c("zutoml_parse_error", "zutoml_error", "error", "condition"),
#'     list(message = "TOML parse error", call = NULL)
#'   )),
#'   zutoml_error = function(e) class(e)[1]
#' )
NULL

# Builds and raises a classed condition. `class` is the most specific class
# first, without "zutoml_error"; the fields in `...` become list elements.
ztm_abort <- function(class, message, ..., call = NULL) {
  stop(structure(
    class = c(class, "zutoml_error", "error", "condition"),
    list(message = message, call = call, ...)
  ))
}

ztm_invalid_argument <- function(arg, message, call = NULL) {
  ztm_abort("zutoml_invalid_argument", message, arg = arg, call = call)
}

# The limit subclasses sit under zutoml_limit_error (design section 11).
ztm_limit_class <- function(limit) {
  sub <- switch(
    limit,
    max_size = "zutoml_size_limit",
    max_depth = "zutoml_depth_limit",
    max_items = "zutoml_item_limit",
    max_string = "zutoml_string_limit",
    stop("unknown limit: ", limit, call. = FALSE)
  )
  c(sub, "zutoml_limit_error")
}
