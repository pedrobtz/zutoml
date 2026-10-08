# toml_parse(): the mapping of design section 6 (roadmap Stage 4). Every row
# of the tables in 6.1 to 6.4 has a test here.

test_that("6.1 strings: character, marked UTF-8", {
  x <- toml_parse(
    "a = \"caf\\u00e9\"\nb = 'raw'\nc = \"\"\"\nml\"\"\"\nd = '''\nml'''"
  )
  expect_identical(x, list(a = "café", b = "raw", c = "ml", d = "ml"))
  expect_identical(Encoding(x$a), "UTF-8")
})

test_that("6.1 integers: integer, double past R's range, bigint past 2^53", {
  x <- toml_parse(paste(
    "a = 1",
    "b = -2147483647",
    "c = -2147483648",
    "d = 2147483648",
    "e = 9007199254740992",
    "f = 9007199254740993",
    "g = -9223372036854775808",
    sep = "\n"
  ))
  expect_identical(x$a, 1L)
  expect_identical(x$b, -2147483647L)
  expect_identical(x$c, -2^31)
  expect_identical(x$d, 2^31)
  expect_identical(x$e, 2^53)
  expect_identical(x$f, toml_bigint("9007199254740993"))
  expect_identical(x$g, toml_bigint("-9223372036854775808"))
})

test_that("big_integers decides past 2^53", {
  doc <- "a = 9007199254740993\nb = 1"
  expect_identical(toml_parse(doc, big_integers = "double")$a, 2^53)
  err <- tryCatch(toml_parse(doc, big_integers = "error"), error = identity)
  expect_s3_class(err, "zutoml_unrepresentable")
  expect_identical(err$kind, "big_integer")
  expect_identical(c(err$line, err$column), c(1, 1))
  # Within 2^53, big_integers changes nothing.
  expect_identical(toml_parse("a = 1", big_integers = "error")$a, 1L)
})

test_that("6.1 floats: double, with inf, nan and the sign of zero", {
  x <- toml_parse("a = 1.5\nb = inf\nc = -inf\nd = nan\ne = -0.0\nf = 1e-400")
  expect_identical(x$a, 1.5)
  expect_identical(x$b, Inf)
  expect_identical(x$c, -Inf)
  expect_true(is.nan(x$d))
  expect_identical(1 / x$e, -Inf)
  expect_identical(x$f, 0)
})

test_that("6.1 booleans: logical", {
  expect_identical(toml_parse("a = true\nb = false"), list(a = TRUE, b = FALSE))
})

test_that("6.1 offset date-times: POSIXct in UTC, the offset applied", {
  x <- toml_parse(
    "a = 1979-05-27T00:32:00.999999-07:00\nb = 1979-05-27 07:32:00Z"
  )
  expect_s3_class(x$a, "POSIXct")
  expect_identical(attr(x$a, "tzone"), "UTC")
  expect_equal(
    unclass(x$a),
    296638320 + 0.999999,
    tolerance = 0,
    ignore_attr = TRUE
  )
  expect_equal(unclass(x$b), 296638320, ignore_attr = TRUE)
  # Past microseconds: truncated in a POSIXct, never rounded up a second.
  y <- toml_parse("a = 1979-05-27T07:32:00.9999999Z")$a
  expect_equal(
    unclass(y),
    296638320 + 0.999999,
    tolerance = 0,
    ignore_attr = TRUE
  )
})

test_that("6.1 local date-times: POSIXct in the session's zone", {
  withr::local_timezone("America/New_York")
  x <- toml_parse("a = 1979-05-27T07:32:00.5")$a
  expect_s3_class(x, "POSIXct")
  expect_identical(attr(x, "tzone"), "")
  expect_identical(format(x, "%Y-%m-%d %H:%M:%OS1"), "1979-05-27 07:32:00.5")
  withr::local_timezone("Asia/Tokyo")
  y <- toml_parse("a = 1979-05-27T07:32:00")$a
  expect_identical(format(y, "%H:%M:%S"), "07:32:00")
  expect_false(identical(unclass(x), unclass(y)))
})

test_that("6.1 local dates and local times", {
  x <- toml_parse("a = 1979-05-27\nb = 07:32:00.25")
  expect_identical(x$a, as.Date("1979-05-27"))
  expect_identical(x$b, "07:32:00.250")
  y <- toml_parse("b = 07:32:00.25", local_time = "difftime")$b
  expect_identical(y, structure(27120.25, class = "difftime", units = "secs"))
})

test_that("datetimes = 'keep' returns canonical RFC 3339 text", {
  x <- toml_parse(
    "a = 1979-05-27 07:32:00+00:00\nb = 1979-05-27t07:32:00.5-07:00\nc = 1979-05-27T07:32\nd = 1979-05-27\ne = 07:32",
    datetimes = "keep"
  )
  expect_identical(
    x,
    list(
      a = "1979-05-27T07:32:00Z",
      b = "1979-05-27T07:32:00.500-07:00",
      c = "1979-05-27T07:32:00",
      d = "1979-05-27",
      e = "07:32:00"
    )
  )
})

test_that("6.2 tables: named lists in definition order", {
  x <- toml_parse("z = 1\n[b]\ny = 2\n[a]\nx = 3\n[b.c]\nw = 4")
  expect_identical(names(x), c("z", "b", "a"))
  expect_identical(x$b, list(y = 2L, c = list(w = 4L)))
  # A table defined after its sub-table: the same nested list.
  expect_identical(
    toml_parse("[a.b]\nx = 1\n[a]\ny = 2"),
    list(a = list(b = list(x = 1L), y = 2L))
  )
})

test_that("6.2 dotted keys, inline tables, empty keys and empty tables", {
  expect_identical(toml_parse("a.b.c = 1"), list(a = list(b = list(c = 1L))))
  expect_identical(
    toml_parse("a = {b = 1, c.d = 2}"),
    list(a = list(b = 1L, c = list(d = 2L)))
  )
  expect_identical(toml_parse("\"\" = 1"), list(1L) |> stats::setNames(""))
  empty <- stats::setNames(list(), character())
  expect_identical(toml_parse("[t]")$t, empty)
  expect_identical(toml_parse("t = {}")$t, empty)
  expect_identical(toml_parse(""), empty)
})

test_that("6.2 arrays of tables: an unnamed list of named lists", {
  x <- toml_parse("[[p]]\nn = 1\n[[p]]\n[[p]]\nn = 3\n[p.q]\nr = 1")
  expect_identical(
    x$p,
    list(
      list(n = 1L),
      stats::setNames(list(), character()),
      list(n = 3L, q = list(r = 1L))
    )
  )
})

test_that("6.3 the lattice", {
  p <- function(v) toml_parse(paste("a =", v))$a
  expect_identical(p("['a', 'b']"), c("a", "b"))
  expect_identical(p("[true, false]"), c(TRUE, FALSE))
  expect_identical(p("[1, 2]"), 1:2)
  expect_identical(p("[1, 2.5]"), c(1, 2.5))
  expect_identical(p("[1, 2147483648]"), c(1, 2^31))
  expect_identical(
    p("[1, 9007199254740993]"),
    toml_bigint(c("1", "9007199254740993"))
  )
  expect_identical(
    p("[1979-05-27, 1980-01-01]"),
    as.Date(c("1979-05-27", "1980-01-01"))
  )
  expect_s3_class(p("[1979-05-27T07:32:00Z, 1980-01-01T00:00:00Z]"), "POSIXct")
  expect_identical(p("[07:32:00, 08:00:00]"), c("07:32:00", "08:00:00"))
  # Kinds that do not share a type: a list.
  expect_identical(p("[true, 1]"), list(TRUE, 1L))
  expect_identical(p("[1, 'a']"), list(1L, "a"))
  expect_identical(
    p("[1.5, 9007199254740993]"),
    list(1.5, toml_bigint("9007199254740993"))
  )
  expect_identical(p("[[1], [2]]"), list(I(1L), I(2L)))
  expect_identical(p("[{b = 1}, 2]"), list(list(b = 1L), 2L))
  expect_type(p("[1979-05-27T07:32:00Z, 1979-05-27T07:32:00]"), "list")
  expect_type(p("[1979-05-27, 07:32:00]"), "list")
  # Empty, and one element.
  expect_identical(p("[]"), logical(0))
  expect_identical(p("[1]"), I(1L))
  expect_identical(p("['x']"), I("x"))
  expect_s3_class(p("[1979-05-27]"), c("AsIs", "Date"), exact = TRUE)
  expect_identical(p("[[]]"), list(logical(0)))
})

test_that("simplify = 'none' makes every array a list", {
  x <- toml_parse("a = [1, 2]\nb = []\nc = [[1]]", simplify = "none")
  expect_identical(x, list(a = list(1L, 2L), b = list(), c = list(list(1L))))
})

test_that("data_frame = TRUE: arrays of tables as data frames", {
  doc <- "[[p]]\nname = 'a'\nn = 1\n[[p]]\nname = 'b'\nx = 2.5\n[[p]]\nname = 'c'\nn = 3"
  df <- toml_parse(doc, data_frame = TRUE)$p
  expect_s3_class(df, "data.frame")
  expect_identical(names(df), c("name", "n", "x"))
  expect_identical(df$name, c("a", "b", "c"))
  expect_identical(df$n, c(1L, NA, 3L))
  expect_identical(df$x, c(NA, 2.5, NA))
  # A column whose values share no type is a list; arrays are list cells.
  df2 <- toml_parse(
    "t = [{a = 1, b = [1, 2]}, {a = 'x', b = [3]}]",
    data_frame = TRUE
  )$t
  expect_identical(df2$a, list(1L, "x"))
  expect_identical(df2$b, list(1:2, I(3L)))
  # Integers and floats widen; dates and bigints keep their class.
  df3 <- toml_parse(
    "t = [{a = 1, d = 1979-05-27, g = 9007199254740993}, {a = 2.5, d = 1980-01-01}]",
    data_frame = TRUE
  )$t
  expect_identical(df3$a, c(1, 2.5))
  expect_identical(df3$d, as.Date(c("1979-05-27", "1980-01-01")))
  expect_identical(df3$g, toml_bigint(c("9007199254740993", NA)))
  # Nested arrays of tables become frames first.
  df4 <- toml_parse(
    "[[a]]\n[[a.b]]\nx = 1\n[[a.b]]\nx = 2",
    data_frame = TRUE
  )$a
  expect_s3_class(df4$b[[1]], "data.frame")
})

test_that("the data frame cell budget refuses rows that share no keys", {
  withr::local_options(zutoml.max_df_cells = 10)
  doc <- paste0("t = [", paste0("{k", 1:4, " = 1}", collapse = ", "), "]")
  err <- tryCatch(toml_parse(doc, data_frame = TRUE), error = identity)
  expect_s3_class(err, "zutoml_limit_error")
  expect_identical(err$limit, "zutoml.max_df_cells")
  expect_type(toml_parse(doc)$t, "list")
})

test_that("6.4 valid TOML R cannot hold is zutoml_unrepresentable", {
  e1 <- tryCatch(toml_parse("a = \"x\\u0000y\""), error = identity)
  expect_s3_class(e1, "zutoml_unrepresentable")
  expect_identical(e1$kind, "nul_in_string")
  e2 <- tryCatch(toml_parse("\"k\\u0000\" = 1"), error = identity)
  expect_identical(e2$kind, "nul_in_string")
  e3 <- tryCatch(toml_parse("a = [1.0, 1e400]"), error = identity)
  expect_s3_class(e3, "zutoml_unrepresentable")
  expect_identical(e3$kind, "float_overflow")
  # ...and toml_validate() accepts each of them.
  expect_true(toml_validate("a = \"x\\u0000y\""))
  expect_true(toml_validate("a = [1.0, 1e400]"))
})

test_that("arguments are checked", {
  bad <- list(
    list(simplify = "x"),
    list(datetimes = "x"),
    list(big_integers = 1),
    list(local_time = NA),
    list(data_frame = NA),
    list(max_depth = 1024),
    list(version = "2")
  )
  for (a in bad) {
    err <- tryCatch(do.call(toml_parse, c(list("a = 1"), a)), error = identity)
    expect_s3_class(err, "zutoml_invalid_argument")
    expect_identical(err$arg, names(a))
  }
  expect_identical(toml_parse("a = 1", simplify = "n")$a, 1L)
})

test_that("max_depth is capped at 1023, and the cap holds in parse", {
  deep <- paste0("a = ", strrep("[", 1023), strrep("]", 1023))
  expect_type(toml_parse(deep, max_depth = 1023)$a, "list")
  expect_s3_class(
    tryCatch(toml_parse(deep), error = identity),
    "zutoml_depth_limit"
  )
})
