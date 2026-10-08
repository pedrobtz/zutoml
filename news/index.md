# Changelog

## zutoml 0.0.0.9000

- [`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
  reads a TOML document into ordinary R values: tables as named lists in
  document order, arrays as vectors where their elements share a type,
  date-times as `POSIXct` and `Date`, and integers beyond 2^53 as
  [`toml_bigint()`](https://pedrobtz.github.io/zutoml/reference/toml_bigint.md).
  `data_frame = TRUE` turns arrays of tables into data frames.
- [`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
  checks that a document is valid TOML, within size, depth, item and
  string limits, and with `error = TRUE` says why and where (`line`,
  `column`, `offset` and `kind` on a classed condition).
- Both pass every case of the `toml-test` suite for TOML 1.0.0 and
  1.1.0. TOML 1.1.0 is read by default; `version = "1.0.0"` reads
  strictly.
