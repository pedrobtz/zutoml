# Scalar values through zufast (roadmap Stage 2, design sections 6.1 and 9).

test_that("integers in every base and their R classes by range", {
  expect_identical(value_of("+99")$value, "99")
  expect_identical(value_of("-17")$value, "-17")
  expect_identical(value_of("0")$value, "0")
  expect_identical(value_of("+0")$value, "0")
  expect_identical(value_of("-0")$value, "0")
  expect_identical(value_of("1_000_000")$value, "1000000")
  expect_identical(value_of("0xDEAD_beef")$value, "3735928559")
  expect_identical(value_of("0x00ff")$value, "255")
  expect_identical(value_of("0o755")$value, "493")
  expect_identical(value_of("0b1101_0110")$value, "214")
  expect_identical(value_of("2147483647")$class, "integer")
  expect_identical(value_of("-2147483647")$class, "integer")
  # -2^31 is NA as an R integer, so it is a double (the zujson rule).
  expect_identical(value_of("-2147483648")$class, "double")
  expect_identical(value_of("2147483648")$class, "double")
  expect_identical(value_of("9007199254740992")$class, "double")
  expect_identical(value_of("-9007199254740992")$class, "double")
  expect_identical(value_of("9007199254740993")$class, "bigint")
  expect_identical(value_of("-9007199254740993")$class, "bigint")
  expect_identical(value_of("9223372036854775807")$value, "9223372036854775807")
  expect_identical(
    value_of("-9223372036854775808")$value,
    "-9223372036854775808"
  )
  expect_identical(value_of("0x7fffffffffffffff")$value, "9223372036854775807")
})

test_that("integers outside 64-bit signed are refused", {
  expect_identical(value_error("9223372036854775808"), "integer_range")
  expect_identical(value_error("-9223372036854775809"), "integer_range")
  expect_identical(value_error("0x8000000000000000"), "integer_range")
})

test_that("integer shapes TOML forbids are refused", {
  for (v in c(
    "01",
    "-01",
    "+01",
    "0_1",
    "1__0",
    "_1",
    "1_",
    "0x",
    "0x_1",
    "0x1_",
    "0X1F",
    "0O7",
    "0B1",
    "-0x1",
    "+0x1",
    "0o8",
    "0b2",
    "0xg",
    "1a",
    "++1",
    "+-1"
  )) {
    # A span that starts with no digit is refused by the lexer already.
    expect_true(
      value_error(v) %in% c("invalid_integer", "invalid_value"),
      label = v
    )
  }
})

test_that("floats, with underscores, exponents and the special values", {
  expect_identical(value_of("3.1415")$value, "3.1415")
  expect_identical(value_of("-0.01")$value, "-0.01")
  expect_identical(value_of("5e+22")$value, "5e+22")
  expect_identical(value_of("1e06")$value, "1000000")
  expect_identical(value_of("-2E-2")$value, "-0.02")
  expect_identical(value_of("6.626e-34")$value, "6.626e-34")
  expect_identical(value_of("224_617.445_991_228")$value, "224617.445991228")
  expect_identical(value_of("1e1_0")$value, "10000000000")
  expect_identical(value_of("0.0")$value, "0")
  expect_identical(value_of("-0.0")$value, "-0")
  expect_identical(value_of("+0.0")$value, "0")
  expect_identical(value_of("inf")$value, "Inf")
  expect_identical(value_of("+inf")$value, "Inf")
  expect_identical(value_of("-inf")$value, "-Inf")
  expect_identical(value_of("nan")$value, "NaN")
  expect_identical(value_of("-nan")$value, "NaN")
  # Correctly rounded, by zufast: the nearest double, ties to even.
  expect_identical(value_of("0.1")$value, "0.1")
  expect_identical(value_of("5e-324")$value, "5e-324")
})

test_that("a float beyond double's range is flagged, not refused", {
  # Valid TOML that R cannot hold: the build phase refuses it (design 6.4),
  # so toml_validate() stays TRUE.
  expect_identical(value_of("1e400")$class, "overflow")
  expect_identical(value_of("-1e400")$class, "overflow")
  expect_identical(value_of("1e-400")$value, "0")
})

test_that("float shapes TOML forbids are refused", {
  for (v in c(
    "1.",
    ".1",
    "+.1",
    "-.1",
    "1.e5",
    "1e",
    "1e+",
    "1e_1",
    "1e1_",
    "1_.0",
    "1._0",
    "01.0",
    "-01.0",
    "00.0",
    "1__0.0",
    "1.0.0",
    "1e1.0",
    "1e1e1",
    "infinity",
    "+infinity",
    "Inf",
    "NaN",
    "nan_",
    "in",
    "na",
    "1.0_"
  )) {
    expect_true(
      value_error(v) %in% c("invalid_float", "invalid_value"),
      label = v
    )
  }
})

test_that("the four date-time types", {
  expect_identical(
    value_of("1979-05-27T07:32:00Z")$value,
    "1979-05-27T07:32:00Z"
  )
  expect_identical(
    value_of("1979-05-27t07:32:00z")$value,
    "1979-05-27T07:32:00Z"
  )
  expect_identical(value_of("1979-05-27 07:32:00Z")$type, "datetime")
  expect_identical(
    value_of("1979-05-27T00:32:00-07:00")$value,
    "1979-05-27T00:32:00-07:00"
  )
  expect_identical(
    value_of("1979-05-27T00:32:00.999999+07:00")$value,
    "1979-05-27T00:32:00.999999+07:00"
  )
  expect_identical(value_of("1979-05-27T07:32:00")$value, "1979-05-27T07:32:00")
  expect_identical(value_of("1979-05-27")$value, "1979-05-27")
  expect_identical(value_of("00:32:00.999999")$value, "00:32:00.999999")
  expect_identical(value_of("2000-02-29")$value, "2000-02-29")
  # A leap second, as RFC 3339 allows.
  expect_identical(
    value_of("1990-12-31T23:59:60Z")$value,
    "1990-12-31T23:59:60Z"
  )
})

test_that("fractions past nanoseconds are truncated, not refused", {
  # TOML: "the additional precision must be truncated, not rounded".
  expect_identical(value_of("07:32:00.1234567899")$value, "07:32:00.123456789")
  expect_identical(
    value_of("1979-05-27T07:32:00.9999999999Z")$value,
    "1979-05-27T07:32:00.999999999Z"
  )
})

test_that("TOML 1.1 makes seconds optional; 1.0.0 requires them", {
  expect_identical(value_of("07:32")$value, "07:32:00")
  expect_identical(value_of("1979-05-27T07:32Z")$value, "1979-05-27T07:32:00Z")
  expect_identical(value_of("1979-05-27 07:32")$type, "local_datetime")
  for (v in c("07:32", "1979-05-27T07:32Z", "1979-05-27T07:32")) {
    expect_identical(
      value_error(v, version = "1.0.0"),
      "invalid_datetime",
      label = v
    )
  }
})

test_that("date-time shapes and dates TOML forbids are refused", {
  for (v in c(
    "1979-05-27T07:32:00+0700",
    "1979-05-27T07:32:00+07",
    "1979-05-27T07:32:00+7:00",
    "1979-05-27T7:32:00Z",
    "1979-5-27",
    "1979-05-27T07:32:00.Z",
    "1979-05-27T07:32:00.",
    "2100-02-29",
    "1979-02-30",
    "1979-13-01",
    "1979-00-01",
    "1979-01-00",
    "1979-01-32",
    "1979-05-27T24:00:00Z",
    "1979-05-27T07:60:00Z",
    "1979-05-27T07:32:61Z",
    "1979-05-27T07:32:00+24:00",
    "1979-05-27T07:32:00+07:60",
    "25:00:00",
    "07:32:00.",
    "1979-05-27T07:32:00X"
  )) {
    expect_true(
      value_error(v) %in%
        c("invalid_datetime", "invalid_value", "invalid_integer"),
      label = v
    )
  }
})

test_that("strings decode their escapes and newlines", {
  expect_identical(value_of("\"a\\tb\\n\\\"\\\\\"")$value, "a\tb\n\"\\")
  expect_identical(value_of("\"\\u00e9\\U0001F600\"")$value, "\u00e9\U0001F600")
  expect_identical(value_of("\"\\e\\x41\"")$value, "\033A")
  expect_identical(value_of("'C:\\Users\\'")$value, "C:\\Users\\")
  expect_identical(value_of("\"\"\"\nline1\nline2\"\"\"")$value, "line1\nline2")
  expect_identical(value_of("'''\n  raw \\n '''")$value, "  raw \\n ")
  expect_identical(value_of("\"\"\"a \\\n\n    b\"\"\"")$value, "a b")
  expect_identical(value_of("\"\"\"\"\"x\"\"\"\"\"")$value, "\"\"x\"\"")
  expect_identical(value_of("''''x'''")$value, "'x")
  expect_identical(
    ztm_tokens(bytes("a = \"\"\"\r\nx\r\ny\"\"\""))$value[[3]],
    "x\ny"
  )
})

test_that("a string holding U+0000 is flagged for the build phase", {
  expect_identical(value_of("\"a\\u0000b\"")$class, "nul")
  expect_true(is.na(value_of("\"a\\u0000b\"")$value))
})

test_that("faults in values point at the value", {
  err <- lex_error("a = 1\nbb = 0x_1")
  expect_identical(c(err$line, err$column, err$offset), c(2, 6, 11))
  expect_s3_class(err, "zutoml_parse_error")
})
