# The committed toml-test suite is whole and unmodified (design section 15).
# tools/run-conformance also checks it against a fresh fetch.

test_that("every file in the manifest is present with its recorded SHA-256", {
  skip_if_not(
    exists("sha256sum", asNamespace("tools")),
    "tools::sha256sum needs R >= 4.5"
  )
  m <- toml_test_manifest()
  paths <- file.path(toml_test_dir(), m$path)
  expect_true(all(file.exists(paths)))
  sums <- unname(get("sha256sum", asNamespace("tools"))(paths))
  expect_identical(m$path[sums != m$sha256], character())
})

test_that("the suite is the pinned version with the expected case counts", {
  expect_identical(
    readLines(file.path(toml_test_dir(), "VERSION")),
    c("v2.2.0", "ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c")
  )
  valid <- toml_test_cases("valid")
  invalid <- toml_test_cases("invalid")
  expect_identical(nrow(valid) * 2L + nrow(invalid), 884L)
  expect_true(all(file.exists(valid$json)))
  expect_gt(nrow(toml_test_cases("valid", "1.1.0")), nrow(valid))
})

test_that("every valid case's expectation converts to an R value", {
  skip_if_not_installed("jsonlite")
  cases <- toml_test_cases("valid", "1.0.0")
  for (i in seq_len(nrow(cases))) {
    j <- tagged_json_read(cases$json[[i]])
    for (dt in c("keep", "convert")) {
      v <- tagged_json_to_r(j, datetimes = dt, local_time = "difftime")
      expect_type(v, "list")
      expect_false(is.null(names(v)), label = cases$name[[i]])
      expect_null(toml_test_diff(v, v), label = cases$name[[i]])
    }
  }
})
