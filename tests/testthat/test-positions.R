# toml_parse(positions = TRUE): where every key and array element is.

test_that("every key and array element has a path, a type and a position", {
  doc <- paste(
    "a = 1",
    "\"b c\" = [1, {d = 2}]",
    "[t.u]",
    "v = 1979-05-27",
    "[t]",
    "w = true",
    "[[p]]",
    "n = 1.5",
    "[[p]]",
    "n = 'x'",
    sep = "\n"
  )
  pos <- attr(toml_parse(doc, positions = TRUE), "toml_positions")
  expect_s3_class(pos, "data.frame")
  expect_named(pos, c("path", "type", "line", "column", "offset"))
  expect_identical(
    pos$path,
    c(
      "a",
      "\"b c\"",
      "\"b c\"[1]",
      "\"b c\"[2]",
      "\"b c\"[2].d",
      "t",
      "t.u",
      "t.u.v",
      "t.w",
      "p",
      "p[1]",
      "p[1].n",
      "p[2]",
      "p[2].n"
    )
  )
  expect_identical(
    pos$type,
    c(
      "integer",
      "array",
      "integer",
      "inline_table",
      "integer",
      "table",
      "table",
      "date-local",
      "bool",
      "array_of_tables",
      "table",
      "float",
      "table",
      "string"
    )
  )
  row <- function(p) unlist(pos[pos$path == p, c("line", "column", "offset")])
  expect_equal(row("a"), c(line = 1, column = 1, offset = 0))
  expect_equal(row("\"b c\"[2].d"), c(line = 2, column = 14, offset = 19))
  # A table implied by a deeper header is placed where it is defined.
  expect_equal(row("t")[["line"]], 5)
  # Each table of an array of tables is placed at its own [[header]].
  expect_equal(row("p[2]")[["line"]], 9)
})

test_that("every TOML type is named as toml-test names it", {
  doc <- paste(
    "s = 'x'",
    "i = 1",
    "f = 1.5",
    "b = true",
    "o = 1979-05-27T07:32:00Z",
    "l = 1979-05-27T07:32:00",
    "d = 1979-05-27",
    "t = 07:32:00",
    sep = "\n"
  )
  pos <- attr(toml_parse(doc, positions = TRUE), "toml_positions")
  expect_identical(
    pos$type,
    c(
      "string",
      "integer",
      "float",
      "bool",
      "datetime",
      "datetime-local",
      "date-local",
      "time-local"
    )
  )
})

test_that("paths quote keys as TOML needs, and columns count characters", {
  pos <- attr(
    toml_parse(
      "\"a.b\" = 1\n\"\u00e9\u00e9\" = 2\n\"q\\\"\" = 3\n'' = 4",
      positions = TRUE
    ),
    "toml_positions"
  )
  expect_identical(
    pos$path,
    c("\"a.b\"", "\"\u00e9\u00e9\"", "\"q\\\"\"", "\"\"")
  )
  x <- attr(toml_parse("a = 1", positions = FALSE), "toml_positions")
  expect_null(x)
  p2 <- attr(
    toml_parse("\"\u00e9\u00e9\" = [1, 2]", positions = TRUE),
    "toml_positions"
  )
  expect_identical(p2$column[p2$path == "\"\u00e9\u00e9\"[2]"], 12)
})

test_that("positions survive the other options and are absent by default", {
  doc <- "[[p]]\nn = 1\n[[p]]\nn = 2"
  expect_null(attr(toml_parse(doc), "toml_positions"))
  x <- toml_parse(doc, positions = TRUE, data_frame = TRUE, simplify = "none")
  expect_s3_class(x$p, "data.frame")
  expect_identical(nrow(attr(x, "toml_positions")), 5L)
  expect_identical(
    nrow(attr(toml_parse("", positions = TRUE), "toml_positions")),
    0L
  )
  expect_s3_class(
    tryCatch(toml_parse(doc, positions = NA), error = identity),
    "zutoml_invalid_argument"
  )
})

test_that("a configuration check can point at the value at fault", {
  doc <- "[server]\nhost = 'localhost'\nport = 99999\n"
  x <- toml_parse(doc, positions = TRUE)
  pos <- attr(x, "toml_positions")
  at <- pos[pos$path == "server.port", ]
  expect_true(x$server$port > 65535)
  expect_identical(c(at$line, at$column), c(3, 1))
})
