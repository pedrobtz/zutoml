#' Integers beyond what a double holds exactly
#'
#' TOML integers are 64-bit. Those beyond 2^53 cannot be held exactly by a
#' double, so [toml_parse()] returns them, by default, as a `toml_bigint`
#' vector: their exact decimal text, with a class.
#'
#' @param x Decimal strings (`"-9223372036854775808"`), or whole numbers
#'   within 2^53. `NA` is kept.
#' @return A character vector of class `toml_bigint`, holding canonical
#'   decimal text: no leading zeros or plus sign.
#' @export
#' @examples
#' x <- toml_bigint(c("9007199254740993", "-42"))
#' x
#' as.numeric(x)   # loses the precision a bigint keeps
#' toml_parse("big = 9223372036854775807")$big
toml_bigint <- function(x) {
  if (inherits(x, "toml_bigint")) {
    return(x)
  }
  if (is.numeric(x)) {
    ok <- is.na(x) | (is.finite(x) & x == trunc(x) & abs(x) <= 2^53)
    if (!all(ok)) {
      ztm_invalid_argument(
        "x",
        "`x` must be whole numbers within 2^53, or decimal strings."
      )
    }
    x <- ifelse(
      is.na(x),
      NA_character_,
      format(x, scientific = FALSE, trim = TRUE)
    )
  }
  if (!is.character(x)) {
    ztm_invalid_argument("x", "`x` must be decimal strings or whole numbers.")
  }
  ok <- is.na(x) | grepl("^[+-]?[0-9]+$", x)
  if (!all(ok)) {
    ztm_invalid_argument("x", "`x` must hold decimal integers only.")
  }
  neg <- startsWith(x, "-")
  digits <- sub("^0+(?=.)", "", sub("^[+-]", "", x), perl = TRUE)
  out <- ifelse(
    is.na(x),
    NA_character_,
    ifelse(neg & digits != "0", paste0("-", digits), digits)
  )
  structure(out, class = "toml_bigint")
}

#' @export
format.toml_bigint <- function(x, ...) {
  format(unclass(x), ...)
}

#' @export
print.toml_bigint <- function(x, ...) {
  cat("<toml_bigint[", length(x), "]>\n", sep = "")
  if (length(x)) {
    print(unclass(x), quote = FALSE, ...)
  }
  invisible(x)
}

#' @export
as.character.toml_bigint <- function(x, ...) {
  unclass(x)
}

#' @export
as.double.toml_bigint <- function(x, ...) {
  as.double(unclass(x))
}

#' @export
`[.toml_bigint` <- function(x, i) {
  structure(unclass(x)[i], class = "toml_bigint")
}

#' @export
`[[.toml_bigint` <- function(x, i) {
  structure(unclass(x)[[i]], class = "toml_bigint")
}

#' @export
`[<-.toml_bigint` <- function(x, i, value) {
  y <- unclass(x)
  y[i] <- unclass(toml_bigint(value))
  structure(y, class = "toml_bigint")
}

#' @export
c.toml_bigint <- function(...) {
  toml_bigint(unlist(lapply(list(...), function(v) unclass(toml_bigint(v)))))
}
