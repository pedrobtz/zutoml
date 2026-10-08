# The round-trip properties of design sections 7.4 and 15 (roadmap Stage
# 6), over generated values covering every row of 7.1 and 7.2.

test_that("toml_parse(toml_emit(x)) is identical to x, over 300 values", {
  withr::local_seed(20261008)
  withr::local_timezone("UTC")
  for (i in seq_len(300)) {
    x <- gen_table(6L)
    text <- toml_emit(x)
    # Deterministic: the same value gives the same text.
    expect_identical(toml_emit(x), text)
    # Valid TOML 1.0.0, whatever the value.
    expect_true(
      toml_validate(text, version = "1.0.0"),
      label = paste("value", i)
    )
    back <- toml_parse(text, local_time = "difftime")
    expect_identical(back, x, label = paste("value", i))
  }
})

test_that("round trip holds with literal strings, inline tables and wrapping", {
  withr::local_seed(20261009)
  withr::local_timezone("UTC")
  for (i in seq_len(60)) {
    x <- gen_table(4L)
    for (args in list(
      list(strings = "literal"),
      list(width = 10, indent = 3)
    )) {
      text <- do.call(toml_emit, c(list(x), args))
      expect_identical(
        toml_parse(text, local_time = "difftime"),
        x,
        label = paste("value", i)
      )
    }
  }
})

test_that("local date-times round-trip in any zone", {
  for (tz in c("UTC", "America/New_York", "Asia/Kolkata")) {
    withr::local_timezone(tz)
    x <- list(a = as.POSIXct("2024-03-01 12:34:56.25", tz = ""))
    attr(x$a, "tzone") <- ""
    expect_identical(toml_parse(toml_emit(x)), x, label = tz)
  }
})
