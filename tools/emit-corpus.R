# Writes toml_emit()'s text for every valid toml-test case that R can hold,
# one file per case and version, so that other TOML readers can be asked to
# accept it (tools/run-conformance; design section 15, acceptance criterion
# 3). Usage, from the package root:
#
#   Rscript tools/emit-corpus.R OUTDIR
suppressMessages(pkgload::load_all(quiet = TRUE))
out <- commandArgs(trailingOnly = TRUE)[[1]]
dir.create(out, showWarnings = FALSE, recursive = TRUE)
m <- utils::read.delim("tests/testthat/toml-test/manifest.tsv", colClasses = "character", quote = "")
n <- 0L
for (version in c("1.0.0", "1.1.0")) {
  keep <- vapply(strsplit(m$toml, ";", fixed = TRUE), function(v) version %in% v, TRUE)
  docs <- m$path[keep & startsWith(m$path, "valid/") & endsWith(m$path, ".toml")]
  for (p in docs) {
    bytes <- readBin(file.path("tests/testthat/toml-test", p), "raw", 1e7)
    v <- tryCatch(toml_parse(bytes, version = version), zutoml_unrepresentable = function(e) NULL)
    if (is.null(v)) next
    name <- paste0(version, "__", gsub("/", "__", sub("\\.toml$", "", p)), ".toml")
    writeBin(charToRaw(toml_emit(v)), file.path(out, name))
    n <- n + 1L
  }
}
cat(sprintf("%d emitted documents written to %s\n", n, out))
