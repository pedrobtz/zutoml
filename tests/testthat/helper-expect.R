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

# Where toml_parse(toml_emit(v)) differs from v beyond design section 7.4's
# losses, or NULL. Allowed: tables compare by key in any order (the emitter
# writes a table's values before its sub-tables), and a whole double reads
# back as an integer (design D4), so numbers compare by value.
roundtrip_diff <- function(actual, expected, path = "") {
  at <- if (nzchar(path)) path else "<document>"
  num <- function(v) is.numeric(v) && !is.object(v)
  if (num(actual) && num(expected)) {
    same <- length(actual) == length(expected) &&
      identical(inherits(actual, "AsIs"), inherits(expected, "AsIs")) &&
      all(
        (is.nan(actual) & is.nan(expected)) |
          (!is.nan(actual) &
            !is.nan(expected) &
            actual == expected &
            (actual != 0 | (1 / actual == 1 / expected)))
      )
    return(
      if (same) {
        NULL
      } else {
        sprintf("%s: %s, expected %s", at, deparse1(actual), deparse1(expected))
      }
    )
  }
  if (is.list(actual) && is.list(expected) && !is.null(names(expected))) {
    if (!setequal(names(actual), names(expected))) {
      return(sprintf("%s: names differ", at))
    }
    for (nm in names(expected)) {
      d <- roundtrip_diff(
        actual[[nm]],
        expected[[nm]],
        if (nzchar(path)) paste0(path, ".", nm) else nm
      )
      if (!is.null(d)) return(d)
    }
    return(NULL)
  }
  if (is.list(actual) && is.list(expected)) {
    if (length(actual) != length(expected)) {
      return(sprintf("%s: length differs", at))
    }
    for (i in seq_along(expected)) {
      d <- roundtrip_diff(
        actual[[i]],
        expected[[i]],
        sprintf("%s[%d]", path, i)
      )
      if (!is.null(d)) return(d)
    }
    return(NULL)
  }
  if (!identical(actual, expected)) {
    return(sprintf(
      "%s: %s, expected %s",
      at,
      deparse1(actual),
      deparse1(expected)
    ))
  }
  NULL
}
