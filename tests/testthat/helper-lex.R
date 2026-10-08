# Lexer helpers (roadmap Stage 1). ztm_tokens() is internal until the grammar
# lands; tests reach it through the namespace, which load_all() and
# test_check() both expose.

# The token types of a document, EOF dropped.
tok_types <- function(x, ...) {
  t <- ztm_tokens(x, ...)$type
  t[t != "eof"]
}

# The parse error a document raises, with its fields.
lex_error <- function(x, ...) {
  err <- tryCatch(ztm_tokens(x, ...), error = identity)
  if (!inherits(err, "zutoml_error")) {
    stop("expected a zutoml_error, got ", class(err)[1L])
  }
  err
}

# Bytes from code points, so a test can hold control characters and
# invalid UTF-8 without writing them into its source.
bytes <- function(...) {
  parts <- list(...)
  as.raw(unlist(lapply(parts, function(p) {
    if (is.character(p)) as.integer(charToRaw(p)) else p
  })))
}

# The parsed value and class of `a = <v>`, from the token table.
value_of <- function(v, ...) {
  t <- ztm_tokens(paste("a =", v), ...)
  t[3L, c("type", "value", "class")]
}

# The kind of the fault `a = <v>` raises.
value_error <- function(v, ...) lex_error(paste("a =", v), ...)$kind
