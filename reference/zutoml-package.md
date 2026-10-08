# zutoml: Read and Write 'TOML' Documents

Parses 'TOML' (Tom's Obvious Minimal Language) version 1.0 documents
into ordinary R values and writes R values as 'TOML'. Every 'TOML' type
maps to one R type, including the four date and time types, and strings
are never reinterpreted. Invalid documents are refused with the line and
column at fault, under configurable size, depth and item limits. Output
is deterministic and readable. Conformance is checked against the
'toml-test' suite (<https://github.com/toml-lang/toml-test>) in both
directions. The parser and writer are written in C with no system
library required.

## See also

Useful links:

- <https://github.com/pedrobtz/zutoml>

- <https://pedrobtz.github.io/zutoml/>

- Report bugs at <https://github.com/pedrobtz/zutoml/issues>

## Author

**Maintainer**: Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]

Authors:

- Pedro Baltazar <pedrobtz@gmail.com> \[copyright holder\]
