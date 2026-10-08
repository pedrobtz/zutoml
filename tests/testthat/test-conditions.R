test_that("ztm_abort() raises the class under zutoml_error with its fields", {
  err <- tryCatch(
    ztm_abort("zutoml_parse_error", "m", line = 3L, kind = "bad_escape"),
    error = identity
  )
  expect_identical(
    class(err),
    c("zutoml_parse_error", "zutoml_error", "error", "condition")
  )
  expect_identical(err$line, 3L)
  expect_identical(err$kind, "bad_escape")
})

test_that("ztm_invalid_argument() carries the argument's name", {
  err <- tryCatch(ztm_invalid_argument("max_depth", "m"), error = identity)
  expect_s3_class(err, "zutoml_invalid_argument")
  expect_identical(err$arg, "max_depth")
})

test_that("every limit maps to its subclass under zutoml_limit_error", {
  limits <- c("max_size", "max_depth", "max_items", "max_string")
  subs <- c(
    "zutoml_size_limit",
    "zutoml_depth_limit",
    "zutoml_item_limit",
    "zutoml_string_limit"
  )
  for (i in seq_along(limits)) {
    expect_identical(
      ztm_limit_class(limits[[i]]),
      c(subs[[i]], "zutoml_limit_error")
    )
  }
  expect_error(ztm_limit_class("max_cells"))
})
