test_that("toml_read() reads a path, closing what it opened", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeBin(charToRaw("a = 1\n[t]\nb = 'x'\n"), path)
  expect_identical(toml_read(path), list(a = 1L, t = list(b = "x")))
  expect_identical(toml_read(path, simplify = "none", version = "1.0.0")$a, 1L)
})

test_that("toml_read() reads a connection from its position and leaves it open", {
  con <- rawConnection(charToRaw("xxa = [1, 2]"))
  on.exit(close(con))
  readBin(con, "raw", n = 2)
  expect_identical(toml_read(con), list(a = 1:2))
  expect_true(isOpen(con))
  # An unopened connection is opened and closed.
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines("b = true", path)
  fc <- file(path)
  expect_identical(toml_read(fc), list(b = TRUE))
  expect_error(isOpen(fc))
})

test_that("an endless connection stops one byte past max_size", {
  con <- rawConnection(charToRaw(strrep("#", 1e6)))
  on.exit(close(con))
  err <- tryCatch(toml_read(con, max_size = 1000), error = identity)
  expect_s3_class(err, "zutoml_size_limit")
  expect_identical(err$limit_value, 1000)
  expect_identical(seek(con), 1001)
})

test_that("files that cannot be read are refused by class", {
  for (bad in list(NA_character_, 1, c("a", "b"))) {
    expect_s3_class(
      tryCatch(toml_read(bad), error = identity),
      "zutoml_invalid_argument"
    )
  }
  missing <- file.path(tempdir(), "no-such-file.toml")
  err <- tryCatch(toml_read(missing), error = identity)
  expect_s3_class(err, "zutoml_invalid_argument")
  expect_identical(err$arg, "file")
  expect_s3_class(
    tryCatch(toml_read(tempdir()), error = identity),
    "zutoml_invalid_argument"
  )
  tc <- textConnection("a = 1")
  on.exit(close(tc))
  expect_s3_class(
    tryCatch(toml_read(tc), error = identity),
    "zutoml_invalid_argument"
  )
})

test_that("a parse error in a file has its position", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(c("a = 1", "a = 2"), path)
  err <- tryCatch(toml_read(path), error = identity)
  expect_s3_class(err, "zutoml_parse_error")
  expect_identical(c(err$line, err$column), c(2, 1))
})
