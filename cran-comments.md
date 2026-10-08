## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

* GitHub Actions: macOS (R release), Windows (R release), Ubuntu (R release
  and oldrel-1).
* R-hub containers matching CRAN's r-devel-linux-x86_64-debian-gcc (GCC 16)
  and -debian-clang (clang 23) flavours.
* Native-code checks on every change: ASan and UBSan (gcc and clang),
  valgrind, gctorture, rchk and LTO.

## Notes

The package's C code is its own; nothing is bundled. It uses the header-only
'zufast' package (by the same maintainer, on CRAN) through `LinkingTo`.

## Method references

The package implements the TOML specification, cited in the Description
(<https://toml.io/en/v1.1.0>); there is no published paper describing it.

The tests include the 'toml-test' conformance suite (MIT licence, the TOML
authors), about 130 KB under `tests/testthat/toml-test/`, with its licence
beside it. The tests use no network.
