## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

GitHub Actions (pedrobtz/r-actions):

* macOS, Windows and Ubuntu R-release; Ubuntu R-oldrel-1; Windows R-devel.
* The r-devel containers `clang23`, `ubuntu-clang` and `ubuntu-gcc16`,
  matching CRAN's Debian clang and GCC flavours.
* `nosuggests` and `nold`, CRAN's NOSUGGESTS and NOLD flavours.
* Native-code checks on every change: ASan and UBSan (gcc and clang),
  valgrind, gctorture, rchk and LTO.

## Notes

The package's C code is its own; no library is vendored. It uses the
header-only 'zufast' package (by the same maintainer, on CRAN) through
`LinkingTo`.

## Method references

The package implements the TOML specification, cited in the Description
(<https://toml.io/en/v1.1.0>); there is no published paper describing it.

The tests include the 'toml-test' conformance suite (MIT licence, the TOML
authors, credited in `inst/COPYRIGHTS`, which `DESCRIPTION` points to),
about 130 KB under `tests/testthat/toml-test/`, with its licence beside it.
The tests use no network.
