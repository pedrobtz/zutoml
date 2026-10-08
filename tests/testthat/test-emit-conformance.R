# The emitter against toml-test (design section 15, acceptance criterion
# 3): every valid case's value, emitted and parsed back, equals itself,
# modulo the losses design section 7.4 lists. tools/run-conformance also
# feeds the emitted text to the reference decoder and to Python's tomllib.

test_that("every valid toml-test value round-trips through the emitter", {
  for (version in c("1.0.0", "1.1.0")) {
    cases <- toml_test_cases("valid", version)
    for (i in seq_len(nrow(cases))) {
      if (cases$name[[i]] %in% toml_test_unrepresentable) {
        next
      }
      label <- paste(version, cases$name[[i]])
      bytes <- toml_test_bytes(cases$toml[[i]])
      # Converted, so that date-times keep their types: under
      # datetimes = "keep" they are strings, and come back as strings.
      v <- toml_parse(bytes, version = version, local_time = "difftime")
      text <- toml_emit(v)
      # Whatever version was read, the text is TOML 1.0.0 (design D17).
      expect_true(toml_validate(text, version = "1.0.0"), label = label)
      back <- toml_parse(text, local_time = "difftime")
      expect_null(roundtrip_diff(back, v), label = label)
    }
  }
})
