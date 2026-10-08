# toml_parse(select = ): only part of a document (roadmap Stage 7c, design
# D20).


test_that("a path selects a table, a value, or an element", {
  doc <- select_doc()
  expect_identical(toml_parse(doc, select = "title"), "x")
  expect_identical(
    toml_parse(doc, select = "tool"),
    toml_parse(doc)$tool
  )
  expect_identical(toml_parse(doc, select = "tool.black.line-length"), 88L)
  expect_identical(toml_parse(doc, select = '"a.b".c'), 1L)
  expect_identical(toml_parse(doc, select = "'a.b'.c"), 1L)
  expect_identical(toml_parse(doc, select = " tool . poetry . name "), "spam")
  expect_identical(toml_parse(doc, select = "products[2].color"), "gray")
  expect_identical(
    toml_parse(doc, select = "products[1]"),
    list(name = "Hammer")
  )
  expect_identical(toml_parse(doc, select = "arr[2][1]"), 20L)
  expect_identical(toml_parse(doc, select = "arr[2]"), c(20L, 30L))
})

test_that("a vector of keys is taken as it is, dots and all", {
  doc <- select_doc()
  expect_identical(
    toml_parse(doc, select = c("tool", "poetry", "name")),
    "spam"
  )
  expect_identical(toml_parse(doc, select = c("a.b", "c")), 1L)
})

test_that("the selected value is built under every option", {
  doc <- select_doc()
  df <- toml_parse(doc, select = "products", data_frame = TRUE)
  expect_s3_class(df, "data.frame")
  expect_identical(df$color, c(NA, "gray"))
  expect_identical(toml_parse(doc, select = "arr", simplify = "none")[[1]], 10L)
  expect_identical(
    toml_parse(doc, select = "tool.poetry.when", datetimes = "keep"),
    "1979-05-27T07:32:00"
  )
  # A selected local date-time is moved into the session's zone too.
  withr::local_timezone("Asia/Tokyo")
  when <- toml_parse(doc, select = "tool.poetry.when")
  expect_identical(attr(when, "tzone"), "")
  expect_identical(format(when, "%H:%M"), "07:32")
})

test_that("positions below a selection keep their absolute paths", {
  pos <- attr(
    toml_parse(select_doc(), select = "products[2]", positions = TRUE),
    "toml_positions"
  )
  expect_identical(
    pos$path,
    c("products[2]", "products[2].name", "products[2].color")
  )
  expect_identical(pos$line, c(9, 10, 11))
  scalar <- attr(
    toml_parse(select_doc(), select = "title", positions = TRUE),
    "toml_positions"
  )
  expect_identical(scalar$path, "title")
})

test_that("a path the document does not have is zutoml_missing_key", {
  doc <- select_doc()
  cases <- list(
    c("tool.poetry.version", "tool.poetry"),
    c("nothing", ""),
    c("products[3]", "products"),
    c("title.x", "title"),
    c("tool[1]", "tool"),
    c("arr[1].x", "arr[1]")
  )
  for (cs in cases) {
    err <- tryCatch(toml_parse(doc, select = cs[[1]]), error = identity)
    expect_s3_class(err, "zutoml_missing_key")
    expect_s3_class(err, "zutoml_error")
    expect_identical(err$path, cs[[1]], label = cs[[1]])
    expect_identical(err$found, cs[[2]], label = cs[[1]])
  }
})

test_that("the whole document is still checked", {
  doc <- paste0(select_doc(), "\nline-length = 89")
  err <- tryCatch(toml_parse(doc, select = "tool.poetry"), error = identity)
  expect_s3_class(err, "zutoml_parse_error")
  expect_identical(err$kind, "duplicate_key")
  # A key that only exists in a table extended later in the file is found.
  later <- "[a]\nx = 1\n[b]\ny = 2\n[a.c]\nz = 3"
  expect_identical(toml_parse(later, select = "a.c.z"), 3L)
})

test_that("select must be a path or keys", {
  for (bad in list(
    1,
    NA_character_,
    character(),
    "a..b",
    "a.",
    "[1]",
    "a[0]",
    "a[x]",
    "a b",
    "\"a",
    "\"\\q\""
  )) {
    err <- tryCatch(toml_parse("a = 1", select = bad), error = identity)
    expect_s3_class(err, "zutoml_invalid_argument")
    expect_identical(err$arg, "select")
  }
})

test_that("toml_read() passes select on", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(select_doc(), path)
  expect_identical(toml_read(path, select = "tool.black.line-length"), 88L)
})
