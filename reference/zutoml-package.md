# zutoml: Read and Write 'TOML' Documents

Parses 'TOML' (Tom's Obvious Minimal Language) documents, versions 1.0.0
and 1.1.0 <https://toml.io/en/v1.1.0>, into ordinary R values, and
writes R values as 'TOML'. Every 'TOML' type maps to one R type,
including the four date and time types, and strings are never
reinterpreted. Invalid documents are refused with the line and column at
fault, under configurable size, depth, item and string limits, and
output is deterministic. Both directions pass the 'toml-test'
conformance suite <https://github.com/toml-lang/toml-test>. The parser
and writer are written in C, with no system library required.

## See also

[`toml_parse()`](https://pedrobtz.github.io/zutoml/reference/toml_parse.md)
to read,
[`toml_emit()`](https://pedrobtz.github.io/zutoml/reference/toml_emit.md)
to write, and
[`vignette("zutoml")`](https://pedrobtz.github.io/zutoml/articles/zutoml.md)
for a tour.

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Other contributors:

- TOML authors (the 'toml-test' suite in tests/testthat/toml-test)
  \[copyright holder\]
