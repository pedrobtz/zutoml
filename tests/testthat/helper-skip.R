# Skips shared by the test files (alignment rule R7 names).

# Skips a test that allocates millions of R objects. It checks a limit or a
# code path, not memory safety, and under gctorture or valgrind it would take
# hours; native-checks.yaml sets ZUTOML_SKIP_HEAVY for those jobs.
# They also skip on CRAN, to keep the suite inside its time budget; every
# CI leg runs them.
skip_heavy <- function() {
  skip_on_cran()
  skip_if(nzchar(Sys.getenv("ZUTOML_SKIP_HEAVY")), "ZUTOML_SKIP_HEAVY is set")
}

# Runs a slow test only when ZUTOML_SLOW_TESTS is set.
skip_if_no_slow_tests <- function() {
  skip_if_not(
    nzchar(Sys.getenv("ZUTOML_SLOW_TESTS")),
    "ZUTOML_SLOW_TESTS is not set"
  )
}

# Skips until the roadmap stage that exports `fn` lands, so the conformance
# tests can be written before the code they test.
skip_until_exported <- function(fn) {
  skip_if_not(
    fn %in% getNamespaceExports("zutoml"),
    paste0(fn, "() is not implemented yet")
  )
}
