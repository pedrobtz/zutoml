# toml-test, the conformance gate of design section 15 and acceptance
# criterion 2. Written before the parser: each block skips until the roadmap
# stage that exports its function (toml_validate() at Stage 3, toml_parse()
# at Stage 4), and from then on every case must pass.

test_that("every valid toml-test case validates (TOML 1.0.0)", {
  skip_until_exported("toml_validate")
  validate <- getExportedValue("zutoml", "toml_validate")
  cases <- toml_test_cases("valid")
  for (i in seq_len(nrow(cases))) {
    expect_true(
      validate(toml_test_bytes(cases$toml[[i]])),
      label = cases$name[[i]]
    )
  }
})

test_that("every invalid toml-test case is refused with a position (TOML 1.0.0)", {
  skip_until_exported("toml_validate")
  validate <- getExportedValue("zutoml", "toml_validate")
  cases <- toml_test_cases("invalid")
  for (i in seq_len(nrow(cases))) {
    expect_false(
      validate(toml_test_bytes(cases$toml[[i]])),
      label = cases$name[[i]]
    )
    err <- tryCatch(
      validate(toml_test_bytes(cases$toml[[i]]), error = TRUE),
      error = identity
    )
    expect_s3_class(err, "zutoml_error")
    if (inherits(err, "zutoml_parse_error")) {
      expect_true(err$line >= 1L && err$column >= 1L, label = cases$name[[i]])
    }
  }
})

test_that("every valid toml-test case parses to its expected value (TOML 1.0.0)", {
  skip_until_exported("toml_parse")
  skip_if_not_installed("jsonlite")
  parse <- getExportedValue("zutoml", "toml_parse")
  cases <- toml_test_cases("valid")
  for (i in seq_len(nrow(cases))) {
    bytes <- toml_test_bytes(cases$toml[[i]])
    expected <- tagged_json_read(cases$json[[i]])
    expect_toml_test_value(
      parse(bytes, simplify = "none", datetimes = "keep"),
      tagged_json_to_r(expected, datetimes = "keep"),
      cases$name[[i]]
    )
    expect_toml_test_value(
      parse(bytes, simplify = "none", local_time = "difftime"),
      tagged_json_to_r(
        expected,
        datetimes = "convert",
        local_time = "difftime"
      ),
      cases$name[[i]]
    )
  }
})
