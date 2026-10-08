test_that("toml_bigint() holds canonical decimal text", {
  x <- toml_bigint(c("+007", "-0", "-9223372036854775808", NA))
  expect_identical(unclass(x), c("7", "0", "-9223372036854775808", NA))
  expect_s3_class(x, "toml_bigint")
  expect_identical(
    toml_bigint(c(1, -2^53)),
    toml_bigint(c("1", "-9007199254740992"))
  )
  expect_identical(toml_bigint(x), x)
})

test_that("toml_bigint() refuses what is not a decimal integer", {
  for (bad in list("1.5", "1e3", "0x10", 2^53 + 2, 1.5, Inf, TRUE)) {
    expect_s3_class(
      tryCatch(toml_bigint(bad), error = identity),
      "zutoml_invalid_argument"
    )
  }
})

test_that("toml_bigint methods keep the class", {
  x <- toml_bigint(c("1", "9007199254740993"))
  expect_identical(x[2], toml_bigint("9007199254740993"))
  expect_identical(x[[1]], toml_bigint("1"))
  expect_identical(
    c(x, toml_bigint("3")),
    toml_bigint(c("1", "9007199254740993", "3"))
  )
  x[1] <- "5"
  expect_identical(x, toml_bigint(c("5", "9007199254740993")))
  expect_identical(as.character(x), c("5", "9007199254740993"))
  expect_identical(as.numeric(toml_bigint("12")), 12)
  expect_identical(trimws(format(x)), c("5", "9007199254740993"))
  expect_output(print(x), "toml_bigint\\[2\\]")
})
