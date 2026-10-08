# Hostile inputs (design sections 12 and 15; roadmap Stages 3 and 6), each a
# permanent regression: every one fails through its class with a position,
# and none crashes, hangs or allocates without bound. The ones that build
# millions of objects skip under gctorture and valgrind (skip_heavy()).

test_that("10^6 open brackets: the depth counter, never the C stack", {
  skip_heavy()
  for (open in c("[", "{b = ")) {
    doc <- paste0("a = ", strrep(open, 1e6))
    err <- validate_error(doc)
    expect_s3_class(err, "zutoml_depth_limit")
    expect_identical(err$line, 1)
    expect_s3_class(
      tryCatch(toml_parse(doc), error = identity),
      "zutoml_depth_limit"
    )
  }
})

test_that("a dotted key of 5 * 10^5 parts is a nesting, and the limit says so", {
  skip_heavy()
  err <- validate_error(paste0(strrep("a.", 5e5), "a = 1"))
  expect_s3_class(err, "zutoml_depth_limit")
})

test_that("10^6 array elements or headers: refused by max_items, or parsed", {
  skip_heavy()
  doc <- paste0("a = [", strrep("{}, ", 1e6), "]")
  expect_s3_class(validate_error(doc), "zutoml_item_limit")
  headers <- strrep("[[a]]\n", 1e6)
  expect_s3_class(validate_error(headers), "zutoml_item_limit")
  expect_length(toml_parse(headers, max_items = 2e6)$a, 1e6)
})

test_that("a million distinct keys cost linear time; the last duplicate is found", {
  skip_heavy()
  keys <- paste0("k", seq_len(2e5), " = 1", collapse = "\n")
  expect_true(toml_validate(keys))
  err <- validate_error(paste0(keys, "\nk1 = 2"))
  expect_identical(err$kind, "duplicate_key")
  expect_identical(err$line, 2e5 + 1)
})

test_that("10^7 line-ending backslashes in one string: linear, and empty", {
  skip_heavy()
  doc <- paste0("a = \"\"\"", strrep("\\\n", 1e7), "\"\"\"")
  expect_identical(toml_parse(doc)$a, "")
})

test_that("10^6 escaped NULs: valid TOML that R cannot hold", {
  skip_heavy()
  doc <- paste0("a = \"", strrep("\\u0000", 1e6), "\"")
  expect_true(toml_validate(doc))
  expect_s3_class(
    tryCatch(toml_parse(doc), error = identity),
    "zutoml_unrepresentable"
  )
})

test_that("a huge document is refused at max_size before any parsing", {
  err <- validate_error(strrep("#", 1001), max_size = 1000)
  expect_s3_class(err, "zutoml_size_limit")
  expect_true(is.na(err$line))
})

test_that("an interrupt during a large parse unwinds cleanly", {
  skip_heavy()
  skip_on_cran()
  doc <- paste0("k", seq_len(5e5), " = [1, 2, 3]", collapse = "\n")
  # setTimeLimit() is checked where R checks for interrupts, which the lexer
  # does every 65536 tokens. A limit in the same expression as the parse
  # stops it part way.
  stopped <- tryCatch(
    {
      setTimeLimit(elapsed = 0.02, transient = TRUE)
      toml_parse(doc, max_items = Inf)
      FALSE
    },
    error = function(e) TRUE
  )
  setTimeLimit()
  expect_true(stopped)
  # Nothing was left behind: the same input then parses.
  expect_length(toml_parse(doc, max_items = Inf), 5e5)
})
