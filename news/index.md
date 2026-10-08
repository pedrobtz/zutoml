# Changelog

## zutoml 0.0.0.9000

- [`toml_validate()`](https://pedrobtz.github.io/zutoml/reference/toml_validate.md)
  checks that a document is valid TOML, within size, depth, item and
  string limits, and with `error = TRUE` says why and where (`line`,
  `column`, `offset` and `kind` on a classed condition). It passes every
  case of the `toml-test` suite for TOML 1.0.0 and 1.1.0.
- TOML 1.1.0 is read by default; `version = "1.0.0"` reads strictly
  (design D17).
