# Runs every toml-test case through the current check phase and prints counts
# by directory (design section 15). Usage, from the package root:
#
#   Rscript tools/conformance.R [version]     default 1.0.0
#
# Loads the package from source with pkgload. Exits non-zero when a valid
# case is refused or an invalid case accepted: since Stage 3 the check phase
# passes the whole suite, and this is the gate that keeps it so.
suppressMessages(pkgload::load_all(quiet = TRUE))
args <- commandArgs(trailingOnly = TRUE)
version <- if (length(args)) args[[1]] else "1.0.0"

m <- utils::read.delim("tests/testthat/toml-test/manifest.tsv", colClasses = "character", quote = "")
m <- m[vapply(strsplit(m$toml, ";", fixed = TRUE), function(v) version %in% v, TRUE), ]
docs <- m$path[endsWith(m$path, ".toml")]

check <- function(path) {
  bytes <- readBin(file.path("tests/testthat/toml-test", path), "raw", 1e7)
  r <- tryCatch({ toml_validate(bytes, version = version, error = TRUE); NA_character_ }, zutoml_error = function(e) e$kind)
  r
}
kind <- sub("/.*$", "", docs)
dir <- ifelse(grepl("^[^/]+/[^/]+/", docs), sub("^[^/]+/([^/]+)/.*$", "\\1", docs), "(top level)")
res <- vapply(docs, check, "", USE.NAMES = FALSE)
ok <- ifelse(kind == "valid", is.na(res), !is.na(res))

tab <- aggregate(ok, list(kind = kind, dir = dir), function(v) sprintf("%d/%d", sum(v), length(v)))
names(tab)[3] <- "passing"
cat(sprintf("toml-test %s, TOML %s, through toml_validate()\n\n", readLines("tests/testthat/toml-test/VERSION")[1], version))
print(tab[order(tab$kind, tab$dir), ], row.names = FALSE)

bad_valid <- docs[kind == "valid" & !ok]
cat(sprintf("\nvalid: %d/%d accepted; invalid: %d/%d refused\n",
            sum(ok[kind == "valid"]), sum(kind == "valid"),
            sum(ok[kind == "invalid"]), sum(kind == "invalid")))
if (length(bad_valid)) {
  cat("\nFAIL: valid cases refused:\n")
  cat(sprintf("  %s (%s)\n", bad_valid, res[kind == "valid" & !ok]), sep = "")
  quit(status = 1)
}
if (any(!ok)) {
  cat("\nFAIL: invalid cases accepted:\n")
  cat(sprintf("  %s\n", docs[!ok]), sep = "")
  quit(status = 1)
}
