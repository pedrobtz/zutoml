#' Information about the zutoml build
#'
#' @return A list: `version`, the package version; `zufast`, the version of
#'   the 'zufast' headers it was compiled against; `toml_test`, the version of
#'   the `toml-test` conformance suite it passes; `toml_versions`, the TOML
#'   versions [toml_parse()] reads; `max_depth_cap`, the largest `max_depth`
#'   accepted; and `ndebug`, whether the C code was compiled without
#'   assertions.
#' @export
#' @examples
#' zutoml_info()$toml_test
zutoml_info <- function() {
  b <- .Call(zutoml_build_info)
  list(
    version = as.character(utils::packageVersion("zutoml")),
    zufast = b$zufast,
    toml_test = ztm_toml_test_version,
    toml_versions = c("1.0.0", "1.1.0"),
    max_depth_cap = b$max_depth_cap,
    ndebug = b$ndebug
  )
}

# The toml-test release the committed suite is pinned to: the tag in
# tools/update-fixtures. test-info.R checks the two agree.
ztm_toml_test_version <- "v2.2.0"
