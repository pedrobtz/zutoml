# Changelog

## zutoml 0.1.0

- Initial CRAN submission.

- [`toml_read()`](https://pedrobtz.github.io/zutoml/reference/toml_read.md)
  reads a TOML document from a file, URL or connection, never holding
  more than `max_size + 1` bytes.

- [`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
  reads a TOML document into ordinary R values: tables as named lists in
  document order, arrays as vectors where their elements share a type,
  date-times as `POSIXct` and `Date`, and integers beyond 2^53 as
  [`toml_bigint()`](https://pedrobtz.github.io/zutoml/reference/toml_bigint.md).
  `data_frame = TRUE` turns arrays of tables into data frames.

- [`toml_emit()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
  and
  [`toml_write()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
  write a named list as TOML: deterministic text, tables as `[headers]`,
  lists of tables and data frames as arrays of tables, and errors that
  name the key path of the value at fault.

- `toml_parse(select = "tool.poetry")`, and so
  [`toml_read()`](https://pedrobtz.github.io/zutoml/reference/toml_read.md),
  returns only the value at a path, building no R values for the rest of
  the document; a path the document does not have raises
  `zutoml_missing_key`.

- `toml_parse(positions = TRUE)` records where every key and array
  element is defined (path, type, line, column, offset), so code that
  checks a configuration can point at the value at fault.

- [`toml_inline()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md),
  [`toml_literal()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
  and
  [`toml_multiline()`](https://pedrobtz.github.io/zutoml/reference/toml-markers.md)
  mark how one value is written by
  [`toml_emit()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md).

- [`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
  checks that a document is valid TOML, within size, depth, item and
  string limits, and with `error = TRUE` says why and where (`line`,
  `column`, `offset` and `kind` on a classed condition).

- [`zutoml_info()`](https://pedrobtz.github.io/zutoml/reference/zutoml_info.md)
  reports the versions zutoml was built against and the `toml-test`
  suite it passes.

- Every case of the `toml-test` suite passes, for TOML 1.0.0 and 1.1.0,
  in both directions. TOML 1.1.0 is read by default; `version = "1.0.0"`
  reads strictly; the emitter always writes TOML 1.0.0.

- A vignette,
  [`vignette("zutoml")`](https://pedrobtz.github.io/zutoml/articles/zutoml.md),
  reads `pyproject.toml` and `Cargo.toml` and writes a configuration.
