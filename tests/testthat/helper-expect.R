# Expectations shared by the test files. They live here, not at the top of a
# test file, because devtools::test(shuffle = TRUE) reorders a file's
# top-level expressions, definitions included.

# toml_emit(x, ...) is exactly `text`.
expect_toml <- function(x, text, ...) {
  expect_identical(toml_emit(x, ...), text)
}

# toml_parse(toml_emit(x)) is identical() to x (design section 7.4).
expect_roundtrip <- function(x, ...) {
  expect_identical(toml_parse(toml_emit(x, ...)), x)
}

# `expr` raises `class` (a zutoml condition), and each field named in `...`
# has the value given. Asserts on classes and fields, never on the message.
expect_zutoml_error <- function(expr, class, kind = NULL, ...) {
  err <- expect_error(expr, class = class)
  expect_s3_class(err, "zutoml_error")
  if (!is.null(kind)) {
    expect_identical(err$kind, kind)
  }
  fields <- list(...)
  for (f in names(fields)) {
    expect_identical(err[[f]], fields[[f]], label = paste0("$", f))
  }
  invisible(err)
}

# R's byte-code compiler folds the literal -0 to +0, so a test that needs
# negative zero makes it at run time.
neg_zero <- function() {
  z <- 0
  -z
}
