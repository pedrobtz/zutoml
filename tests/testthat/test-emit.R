# toml_emit(): design sections 7 and 8 (roadmap Stage 5). Every row of the
# tables in 7.1 to 7.3 has a test, as exact text.

test_that("7.1 strings: basic, escaped, multi-line, literal", {
  expect_toml(list(a = "x"), "a = \"x\"\n")
  expect_toml(
    list(a = "q\"b\\t\tc\001\177"),
    "a = \"q\\\"b\\\\t\\tc\\u0001\\u007F\"\n"
  )
  expect_toml(list(a = "caf\u00e9"), "a = \"caf\u00e9\"\n")
  expect_toml(list(a = "l1\nl2"), "a = \"\"\"\nl1\nl2\"\"\"\n")
  expect_toml(list(a = "end\""), "a = \"end\\\"\"\n")
  expect_toml(list(a = "x\n\"\"\""), "a = \"\"\"\nx\n\\\"\\\"\\\"\"\"\"\n")
  expect_toml(list(a = "C:\\x"), "a = 'C:\\x'\n", strings = "literal")
  expect_toml(list(a = "it's"), "a = \"it's\"\n", strings = "literal")
  expect_toml(list(a = ""), "a = \"\"\n")
})

test_that("7.1 integers, whole doubles and floats", {
  expect_toml(list(a = 1L, b = -5L), "a = 1\nb = -5\n")
  expect_toml(list(a = 8080), "a = 8080\n")
  expect_toml(list(a = -2^63), "a = -9223372036854775808\n")
  expect_toml(list(a = 2^63), "a = 9223372036854776000.0\n")
  expect_toml(
    list(a = 0.1, b = 1e21, c = 1e-7, d = 1.5),
    "a = 0.1\nb = 1e+21\nc = 1e-7\nd = 1.5\n"
  )
  expect_toml(list(a = neg_zero()), "a = -0.0\n")
  expect_toml(list(a = NaN, b = Inf, c = -Inf), "a = nan\nb = inf\nc = -inf\n")
  expect_toml(
    list(a = toml_bigint("-9223372036854775808")),
    "a = -9223372036854775808\n"
  )
})

test_that("7.1 booleans, dates, times and factors", {
  expect_toml(list(a = TRUE, b = FALSE), "a = true\nb = false\n")
  expect_toml(list(a = as.Date("1979-05-27")), "a = 1979-05-27\n")
  expect_toml(
    list(a = as.POSIXct(296638320.5, tz = "UTC")),
    "a = 1979-05-27T07:32:00.500Z\n"
  )
  # A non-UTC zone is converted to UTC (design section 18 Q3).
  expect_toml(
    list(a = as.POSIXct("1979-05-27 00:32:00", tz = "America/Los_Angeles")),
    "a = 1979-05-27T07:32:00Z\n"
  )
  expect_toml(
    list(a = as.difftime(27120.25, units = "secs")),
    "a = 07:32:00.250\n"
  )
  expect_toml(list(a = factor("b", levels = c("a", "b"))), "a = \"b\"\n")
})

test_that("7.1 a POSIXct with no time zone is a local date-time", {
  withr::local_timezone("Europe/Lisbon")
  x <- as.POSIXct("1979-05-27 07:32:00.123", tz = "")
  expect_toml(list(a = x), "a = 1979-05-27T07:32:00.123\n")
  attr(x, "tzone") <- NULL
  expect_toml(list(a = x), "a = 1979-05-27T07:32:00.123\n")
})

test_that("7.1 vectors are arrays; I() makes an array of one", {
  expect_toml(list(a = 1:3), "a = [1, 2, 3]\n")
  expect_toml(list(a = c("x", "y")), "a = [\"x\", \"y\"]\n")
  expect_toml(list(a = I(1L)), "a = [1]\n")
  expect_toml(list(a = integer()), "a = []\n")
  expect_toml(list(a = I(as.Date("1979-05-27"))), "a = [1979-05-27]\n")
})

test_that("difftime other than seconds within a day is refused", {
  err <- tryCatch(
    toml_emit(list(a = as.difftime(5, units = "mins"))),
    error = identity
  )
  expect_s3_class(err, "zutoml_invalid_argument")
  expect_identical(err$path, "a")
  err <- tryCatch(
    toml_emit(list(a = as.difftime(90000, units = "secs"))),
    error = identity
  )
  expect_s3_class(err, "zutoml_invalid_argument")
})

test_that("7.2 tables, sub-tables and headers", {
  expect_toml(
    list(a = 1L, t = list(b = 2L, u = list(c = 3L)), z = "last"),
    "a = 1\nz = \"last\"\n\n[t]\nb = 2\n\n[t.u]\nc = 3\n"
  )
  # A table of only sub-tables gets no header; an empty one does.
  expect_toml(list(a = list(b = list(c = 1L))), "[a.b]\nc = 1\n")
  expect_toml(list(a = setNames(list(), character())), "[a]\n")
  # Keys that are not bare are quoted; the empty key is "".
  expect_toml(
    setNames(list(1L, 2L, 3L), c("a b", "", "x.y")),
    "\"a b\" = 1\n\"\" = 2\n\"x.y\" = 3\n"
  )
  expect_toml(list("a b" = list(c = 1L)), "[\"a b\"]\nc = 1\n")
})

test_that("7.2 arrays of tables, inline tables, and data frames", {
  expect_toml(
    list(p = list(list(n = 1L), list(n = 2L, q = list(r = 1L)))),
    "[[p]]\nn = 1\n\n[[p]]\nn = 2\n\n[p.q]\nr = 1\n"
  )
  # Inside an array, a named list is an inline table.
  expect_toml(list(a = list(1L, list(b = 2L))), "a = [1, { b = 2 }]\n")
  expect_toml(list(a = I(list(list(b = 2L)))), "a = [{ b = 2 }]\n")
  expect_toml(list(a = list(list())), "a = [[]]\n")
  # Data frames: one table per row, NA cells left out.
  expect_toml(
    list(d = data.frame(n = c("a", "b"), v = c(1L, NA))),
    "[[d]]\nn = \"a\"\nv = 1\n\n[[d]]\nn = \"b\"\n"
  )
  expect_toml(
    list(a = list(data.frame(x = 1:2))),
    "a = [[{ x = 1 }, { x = 2 }]]\n"
  )
  # A data frame with no rows is an empty array, not a missing key.
  expect_toml(list(d = data.frame(x = integer())), "d = []\n")
})

test_that("inline = writes small flat tables inline", {
  x <- list(p = list(x = 1L, y = 2L), q = list(x = 1L, y = 2L, z = 3L))
  expect_toml(
    x,
    "p = { x = 1, y = 2 }\n\n[q]\nx = 1\ny = 2\nz = 3\n",
    inline = 2
  )
  # p holds a list, so it keeps its header; x is small and flat.
  expect_toml(list(p = list(x = list(y = 1L))), "[p]\nx = { y = 1 }\n", inline = 2)
})

test_that("width = wraps long arrays one element per line", {
  x <- list(a = c("aaaaaaaaaa", "bbbbbbbbbb", "cccccccccc"))
  expect_toml(
    x,
    "a = [\n  \"aaaaaaaaaa\",\n  \"bbbbbbbbbb\",\n  \"cccccccccc\",\n]\n",
    width = 20
  )
  expect_toml(
    x,
    "a = [\n    \"aaaaaaaaaa\",\n    \"bbbbbbbbbb\",\n    \"cccccccccc\",\n]\n",
    width = 20,
    indent = 4
  )
  expect_toml(
    x,
    "a = [\"aaaaaaaaaa\", \"bbbbbbbbbb\", \"cccccccccc\"]\n",
    width = 0
  )
  expect_identical(toml_parse(toml_emit(x, width = 5)), x)
})

test_that("7.3 values with no TOML form are zutoml_unsupported_type, with a path", {
  bad <- list(
    1i,
    as.raw(1),
    sum,
    globalenv(),
    as.POSIXlt("2024-01-01", tz = "UTC"),
    matrix(1:4, 2),
    structure(1, class = "integer64")
  )
  for (b in bad) {
    err <- tryCatch(
      toml_emit(list(t = list(k = list(1L, b)))),
      error = identity
    )
    expect_s3_class(err, "zutoml_unsupported_type")
    expect_identical(err$path, "t.k[2]")
  }
})

test_that("NA and NULL: refused, or omitted on request", {
  for (v in list(NA, NA_character_, NA_integer_, NA_real_, NULL, as.Date(NA))) {
    err <- tryCatch(toml_emit(list(a = 1L, b = v)), error = identity)
    expect_s3_class(err, "zutoml_na_error")
    expect_identical(err$path, "b")
  }
  expect_toml(list(a = 1L, b = NA, c = NULL), "a = 1\n", na = "omit")
  expect_warning(
    out <- toml_emit(list(a = c(1L, NA, 3L)), na = "omit"),
    "dropped"
  )
  expect_identical(out, "a = [1, 3]\n")
  err <- tryCatch(toml_emit(list(a = list(1L, NULL))), error = identity)
  expect_identical(err$path, "a[2]")
})

test_that("the document must be a named list with usable names", {
  for (x in list(1:3, list(1, 2), data.frame(a = 1), "x")) {
    expect_s3_class(
      tryCatch(toml_emit(x), error = identity),
      "zutoml_invalid_argument"
    )
  }
  expect_identical(toml_emit(list()), "")
  dup <- tryCatch(toml_emit(list(a = 1, a = 2)), error = identity)
  expect_s3_class(dup, "zutoml_invalid_argument")
  na_name <- tryCatch(toml_emit(setNames(list(1), NA)), error = identity)
  expect_s3_class(na_name, "zutoml_invalid_argument")
  bad_utf8 <- tryCatch(toml_emit(list(a = "\xff")), error = identity)
  expect_s3_class(bad_utf8, "zutoml_invalid_argument")
})

test_that("emission charges max_depth as parsing does", {
  for (depth in 1:5) {
    x <- list(a = Reduce(function(acc, i) list(acc), seq_len(depth), 1L))
    text <- tryCatch(
      toml_emit(x, max_depth = 4),
      zutoml_depth_limit = function(e) NULL
    )
    parsed <- tryCatch(
      toml_validate(
        toml_emit(x, max_depth = 1023),
        max_depth = 4,
        error = TRUE
      ),
      zutoml_depth_limit = function(e) NULL
    )
    expect_identical(
      is.null(text),
      is.null(parsed),
      label = paste("depth", depth)
    )
  }
  err <- tryCatch(
    toml_emit(list(a = list(b = list(c = 1L))), max_depth = 2),
    error = identity
  )
  expect_s3_class(err, "zutoml_depth_limit")
  expect_identical(err$limit, "max_depth")
})

test_that("emission is deterministic: a checked-in document", {
  x <- list(
    title = "zutoml",
    version = 1L,
    ratio = 0.1,
    big = toml_bigint("9007199254740993"),
    flags = c(TRUE, FALSE),
    when = as.POSIXct(296638320.25, tz = "UTC"),
    day = as.Date("1979-05-27"),
    at = as.difftime(27120, units = "secs"),
    text = "two\nlines",
    empty = list(),
    one = I("x"),
    owner = list(name = "Tom", "quoted key" = 1L, nested = list(deep = TRUE)),
    rows = list(list(a = 1L), list(a = 2L, b = c(1.5, 2)))
  )
  expect_identical(toml_emit(x), toml_emit(x))
  expect_snapshot(cat(toml_emit(x)))
})

test_that("toml_write() writes to a path or a connection", {
  path <- withr::local_tempfile(fileext = ".toml")
  x <- list(a = 1L, b = "caf\u00e9")
  expect_identical(toml_write(x, path), path)
  expect_identical(readBin(path, "raw", 100), charToRaw(enc2utf8(toml_emit(x))))
  con <- rawConnection(raw(), "wb")
  toml_write(x, con)
  expect_identical(rawToChar(rawConnectionValue(con)), enc2native(toml_emit(x)))
  close(con)
  tc <- textConnection("out", "w", local = TRUE)
  toml_write(x, tc)
  close(tc)
  expect_identical(paste0(out, collapse = "\n"), sub("\n$", "", toml_emit(x)))
  err <- tryCatch(
    toml_write(x, file.path(tempdir(), "no", "such", "dir", "x.toml")),
    error = identity
  )
  expect_s3_class(err, "zutoml_io_error")
  expect_s3_class(
    tryCatch(toml_write(x, 1), error = identity),
    "zutoml_invalid_argument"
  )
})
