# toml-test

The [toml-test](https://github.com/toml-lang/toml-test) conformance suite at
tag `v2.2.0` (commit `ce08da1d`), MIT-licensed; the licence is in
`LICENSE` beside this file. Used by `test-conformance.R` (design section 15).

Every file here is written by `tools/update-fixtures`; do not edit them by hand.
`manifest.tsv` lists each file with the TOML versions whose case lists name
it (`toml`) and its SHA-256. `tools/run-conformance --fixtures-only` fails if
this directory differs from a fresh fetch. Tests never use the network.
