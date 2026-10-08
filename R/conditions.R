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

# ---- faults from the check phase -------------------------------------------

# Status name (the condition's `kind`) -> class vector, by the enumerator's
# name, never by English. test-status.R checks that every name C can report
# is here.
ztm_status_class <- function(status) {
  switch(
    status,
    size_limit = ztm_limit_class("max_size"),
    depth_limit = ztm_limit_class("max_depth"),
    item_limit = ztm_limit_class("max_items"),
    string_limit = ztm_limit_class("max_string"),
    if (status %in% ztm_parse_statuses) "zutoml_parse_error" else character()
  )
}

ztm_parse_statuses <- c(
  "invalid_utf8",
  "control_character",
  "bad_escape",
  "bad_unicode_escape",
  "unterminated_string",
  "multiline_key",
  "unexpected_character",
  "invalid_value"
)

# English for each status, for the message only. Tests never match it.
ztm_status_text <- c(
  invalid_utf8 = "the document is not valid UTF-8",
  control_character = "control character not allowed here",
  bad_escape = "invalid escape sequence",
  bad_unicode_escape = "\\u or \\U escape is not a Unicode scalar value",
  unterminated_string = "string is not terminated",
  multiline_key = "a multi-line string cannot be a key",
  unexpected_character = "unexpected character",
  invalid_value = "not a TOML value"
)

ztm_fault_message <- function(fault, class) {
  fmt <- function(v) format(v, scientific = FALSE, big.mark = "")
  if ("zutoml_limit_error" %in% class) {
    what <- switch(
      fault$limit,
      max_size = "the document is larger than",
      max_depth = "the document nests deeper than",
      max_items = "the document has more keys and array elements than",
      max_string = "a string or key is longer than"
    )
    at <- if (is.na(fault$line)) {
      ""
    } else {
      paste0(" at line ", fault$line, ", column ", fault$column)
    }
    return(paste0(
      "TOML limit reached",
      at,
      ": ",
      what,
      " ",
      fault$limit,
      " = ",
      fmt(fault$limit_value)
    ))
  }
  text <- ztm_status_text[fault$status]
  if (is.na(text)) {
    text <- fault$status
  }
  paste0(
    "TOML parse error at line ",
    fault$line,
    ", column ",
    fault$column,
    ": ",
    text
  )
}

# Raises the condition for a fault the check phase returned.
ztm_raise_fault <- function(fault, call = NULL) {
  class <- ztm_status_class(fault$status)
  cond <- list(
    message = ztm_fault_message(fault, class),
    call = call,
    kind = fault$status,
    line = fault$line,
    column = fault$column,
    offset = fault$offset
  )
  if ("zutoml_limit_error" %in% class) {
    cond$limit <- fault$limit
    cond$limit_value <- fault$limit_value
  }
  stop(structure(class = c(class, "zutoml_error", "error", "condition"), cond))
}
