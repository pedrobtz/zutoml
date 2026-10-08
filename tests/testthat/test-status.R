test_that("every status the C layer can report maps to a condition class", {
  for (s in .Call(zutoml_status_names)) {
    cls <- ztm_status_class(s)
    expect_true(length(cls) > 0L, label = s)
    expect_true(
      any(
        c(
          "zutoml_parse_error",
          "zutoml_limit_error",
          "zutoml_unrepresentable"
        ) %in%
          cls
      ),
      label = s
    )
  }
})

test_that("every parse status has a message", {
  parse <- Filter(
    function(s) "zutoml_parse_error" %in% ztm_status_class(s),
    .Call(zutoml_status_names)
  )
  expect_setequal(names(ztm_status_text), parse)
})

test_that("a parse fault becomes a classed condition with its position", {
  err <- tryCatch(ztm_tokens("a = \"\\q\""), error = identity)
  expect_identical(
    class(err),
    c("zutoml_parse_error", "zutoml_error", "error", "condition")
  )
  expect_identical(err$kind, "bad_escape")
  expect_identical(c(err$line, err$column, err$offset), c(1, 6, 5))
  expect_snapshot(conditionMessage(err))
})
