# The conformance helpers are code too: they decide what "passes toml-test"
# means, so they get their own tests.

test_that("integers take the type design section 6.1 gives by range", {
  expect_identical(toml_test_integer("42"), 42L)
  expect_identical(toml_test_integer("-2147483647"), -2147483647L)
  expect_identical(toml_test_integer("+2147483647"), 2147483647L)
  expect_identical(toml_test_integer("-2147483648"), -2^31)
  expect_identical(toml_test_integer("2147483648"), 2^31)
  expect_identical(toml_test_integer("9007199254740992"), 2^53)
  expect_identical(
    toml_test_integer("9007199254740993"),
    structure("9007199254740993", class = "toml_bigint")
  )
  expect_identical(
    toml_test_integer("-9223372036854775808"),
    structure("-9223372036854775808", class = "toml_bigint")
  )
  expect_identical(toml_test_integer("-0"), 0L)
})

test_that("floats keep inf, nan and the sign of zero", {
  expect_identical(toml_test_float("inf"), Inf)
  expect_identical(toml_test_float("+inf"), Inf)
  expect_identical(toml_test_float("-inf"), -Inf)
  expect_true(is.nan(toml_test_float("nan")))
  expect_true(is.nan(toml_test_float("-nan")))
  expect_identical(1 / toml_test_float("-0.0"), -Inf)
  expect_identical(toml_test_float("1.5"), 1.5)
})

test_that("date-times convert to the section 6.1 types", {
  odt <- toml_test_datetime("1979-05-27T00:32:00-07:00", "datetime")
  expect_identical(attr(odt, "tzone"), "UTC")
  expect_identical(unclass(odt)[[1]], 296638320)
  frac <- toml_test_datetime("1979-05-27 07:32:00.999999999Z", "datetime")
  expect_equal(unclass(frac)[[1]], 296638320 + 0.999999, tolerance = 0)
  withr::local_timezone("Europe/Lisbon")
  ldt <- toml_test_datetime("1979-05-27T07:32:00", "datetime-local")
  expect_identical(attr(ldt, "tzone"), "")
  expect_identical(format(ldt, "%Y-%m-%d %H:%M:%S"), "1979-05-27 07:32:00")
  expect_identical(
    tagged_scalar_to_r("date-local", "1979-05-27", "convert", "character"),
    as.Date("1979-05-27")
  )
  expect_identical(
    toml_test_time("07:32:00.5", "convert", "difftime"),
    structure(27120.5, class = "difftime", units = "secs")
  )
  expect_identical(
    toml_test_time("07:32:00", "convert", "character"),
    "07:32:00"
  )
})

test_that("kept date-times are normalised to T and Z", {
  expect_identical(
    toml_test_dt_text("1979-05-27 07:32:00z"),
    "1979-05-27T07:32:00Z"
  )
  expect_identical(
    toml_test_dt_text("1979-05-27t07:32:00.5+01:00"),
    "1979-05-27T07:32:00.5+01:00"
  )
})

test_that("tables, arrays and empties map as section 6.2 and 6.3 say", {
  j <- list(
    a = tj("integer", "1"),
    arr = list(tj("string", "x"), tj("bool", "true")),
    empty_arr = list(),
    t = stats::setNames(list(), character()),
    aot = list(list(b = tj("float", "2.5")))
  )
  v <- tagged_json_to_r(j)
  expect_identical(v$a, 1L)
  expect_identical(v$arr, list("x", TRUE))
  expect_identical(v$empty_arr, list())
  expect_identical(v$t, stats::setNames(list(), character()))
  expect_identical(v$aot, list(list(b = 2.5)))
  expect_identical(
    tagged_json_to_r(stats::setNames(list(), character())),
    stats::setNames(list(), character())
  )
})

test_that("a table whose keys are 'type' and 'value' is not a scalar", {
  j <- list(type = tj("string", "a"), value = tj("string", "b"))
  expect_identical(tagged_json_to_r(j), list(type = "a", value = "b"))
})

test_that("toml_test_diff() finds the first difference by key path", {
  expect_null(toml_test_diff(list(a = 1L), list(a = 1L)))
  expect_match(toml_test_diff(list(a = 1L), list(a = 1)), "^a: class")
  expect_match(
    toml_test_diff(list(a = list(1L, 2L)), list(a = list(1L, 3L))),
    "^a\\[2\\]"
  )
  expect_match(toml_test_diff(list(b = 1L), list(a = 1L)), "names")
  expect_match(toml_test_diff(list(z = 0), list(z = neg_zero())), "^z:")
  expect_null(toml_test_diff(list(x = NaN), list(x = NaN)))
  # One ulp apart: accepted, since as.numeric() is not correctly rounded on
  # every platform.
  x <- 0.1
  expect_null(toml_test_diff(
    list(x = x + .Machine$double.eps / 16),
    list(x = x)
  ))
  expect_match(toml_test_diff(list(x = 0.1), list(x = 0.2)), "^x:")
})
