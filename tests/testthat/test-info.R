test_that("zutoml_info() reports the build", {
  info <- zutoml_info()
  expect_named(
    info,
    c(
      "version",
      "zufast",
      "toml_test",
      "toml_versions",
      "max_depth_cap",
      "ndebug"
    )
  )
  expect_identical(info$version, as.character(packageVersion("zutoml")))
  expect_match(info$zufast, "^[0-9]+\\.[0-9]+\\.[0-9]+")
  # R's cap and C's are one number.
  expect_identical(info$max_depth_cap, as.integer(ztm_max_depth_cap))
  expect_type(info$ndebug, "logical")
})

test_that("zutoml_info() names the toml-test suite that is committed", {
  expect_identical(
    zutoml_info()$toml_test,
    readLines(file.path(toml_test_dir(), "VERSION"))[[1]]
  )
})
