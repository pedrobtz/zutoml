# The build phase and the emitter, fuzzed through R (roadmap Stage 6). The
# check phase has libFuzzer (tools/run-fuzz); the R-side code, which
# allocates R objects and can be interrupted, is exercised here, under the
# sanitizer jobs of native-checks.yaml, which set ZUTOML_SLOW_TESTS. Any
# outcome is fine but a crash or a sanitizer report.

test_that("mutated toml-test documents through every parse and emit option", {
  skip_if_no_slow_tests()
  withr::local_seed(20261010)
  files <- toml_test_cases("valid", "1.1.0")$toml
  seeds <- lapply(files, toml_test_bytes)
  exercise <- function(x) {
    for (args in list(
      list(),
      list(simplify = "none", datetimes = "keep", big_integers = "double"),
      list(data_frame = TRUE, local_time = "difftime", big_integers = "error"),
      list(max_depth = 3, max_items = 50, max_string = 20)
    )) {
      v <- tryCatch(do.call(toml_parse, c(list(x), args)), zutoml_error = function(e) NULL)
      if (is.list(v)) {
        tryCatch(toml_emit(v), zutoml_error = function(e) NULL)
        tryCatch(toml_emit(v, na = "omit", strings = "literal", inline = 3, width = 8),
          zutoml_error = function(e) NULL,
          warning = function(w) NULL
        )
      }
    }
  }
  for (x in seeds) {
    exercise(x)
    for (n in unique(round(seq(0, length(x), length.out = 6)))) exercise(x[seq_len(n)])
  }
  for (i in seq_len(20000)) {
    x <- seeds[[sample(length(seeds), 1L)]]
    if (!length(x)) next
    for (k in seq_len(sample(1:4, 1L))) {
      at <- sample(length(x), 1L)
      x <- switch(sample(3L, 1L),
        {
          x[at] <- as.raw(sample(0:255, 1L))
          x
        },
        x[-at],
        append(x, x[sample(length(x), sample(1:8, 1L), replace = TRUE)], at)
      )
    }
    exercise(x)
  }
  expect_true(TRUE)
})

test_that("generated values through every emit option", {
  skip_if_no_slow_tests()
  withr::local_seed(20261011)
  withr::local_timezone("UTC")
  for (i in seq_len(500)) {
    x <- gen_table(6L)
    for (args in list(list(), list(inline = 4, width = 5, strings = "literal"), list(max_depth = 2))) {
      text <- tryCatch(do.call(toml_emit, c(list(x), args)), zutoml_error = function(e) NULL)
      if (!is.null(text)) expect_true(toml_validate(text))
    }
  }
})
