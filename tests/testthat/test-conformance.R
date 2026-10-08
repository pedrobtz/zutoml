# toml-test, the conformance gate of design section 15 and acceptance
# criterion 2, for TOML 1.0.0 and 1.1.0 (design D17). Written before the
# parser: each block skips until the roadmap stage that exports its function
# (toml_validate() at Stage 3, toml_parse() at Stage 4), and from then on
# every case must pass.

test_that("every valid toml-test case validates", {
  validate <- toml_validate
  for (version in c("1.0.0", "1.1.0")) {
    cases <- toml_test_cases("valid", version)
    for (i in seq_len(nrow(cases))) {
      expect_true(
        validate(toml_test_bytes(cases$toml[[i]]), version = version),
        label = paste(version, cases$name[[i]])
      )
    }
  }
})

test_that("every invalid toml-test case is refused with a position", {
  validate <- toml_validate
  for (version in c("1.0.0", "1.1.0")) {
    cases <- toml_test_cases("invalid", version)
    for (i in seq_len(nrow(cases))) {
      label <- paste(version, cases$name[[i]])
      bytes <- toml_test_bytes(cases$toml[[i]])
      expect_false(validate(bytes, version = version), label = label)
      err <- tryCatch(
        validate(bytes, version = version, error = TRUE),
        error = identity
      )
      expect_s3_class(err, "zutoml_parse_error")
      expect_true(err$line >= 1 && err$column >= 1, label = label)
    }
  }
})

test_that("every valid toml-test case parses to its expected value", {
  skip_if_not_installed("jsonlite")
  for (version in c("1.0.0", "1.1.0")) {
    cases <- toml_test_cases("valid", version)
    for (i in seq_len(nrow(cases))) {
      label <- paste(version, cases$name[[i]])
      bytes <- toml_test_bytes(cases$toml[[i]])
      if (cases$name[[i]] %in% toml_test_unrepresentable) {
        # Valid TOML R cannot hold (design section 6.4).
        err <- tryCatch(toml_parse(bytes, version = version), error = identity)
        expect_s3_class(err, "zutoml_unrepresentable")
        expect_identical(err$kind, "nul_in_string", label = label)
        next
      }
      expected <- tagged_json_read(cases$json[[i]])
      expect_toml_test_value(
        toml_parse(
          bytes,
          version = version,
          simplify = "none",
          datetimes = "keep"
        ),
        tagged_json_to_r(expected, datetimes = "keep"),
        label
      )
      expect_toml_test_value(
        toml_parse(
          bytes,
          version = version,
          simplify = "none",
          local_time = "difftime"
        ),
        tagged_json_to_r(
          expected,
          datetimes = "convert",
          local_time = "difftime"
        ),
        label
      )
    }
  }
})

test_that("toml_validate() and toml_parse() disagree only on the 6.4 cases", {
  for (version in c("1.0.0", "1.1.0")) {
    cases <- toml_test_cases("valid", version)
    refused <- character()
    for (i in seq_len(nrow(cases))) {
      bytes <- toml_test_bytes(cases$toml[[i]])
      expect_true(toml_validate(bytes, version = version))
      ok <- tryCatch(
        {
          toml_parse(bytes, version = version)
          TRUE
        },
        zutoml_unrepresentable = function(e) FALSE
      )
      if (!ok) refused <- c(refused, cases$name[[i]])
    }
    expect_setequal(refused, intersect(toml_test_unrepresentable, cases$name))
  }
})
