# The performance targets of design section 16: parsing a 1 MB document of
# mixed tables within 2x of RcppTOML, and emitting within 2x of zuyaml on
# the same R value. Not a CI gate; run with tools/run-benchmarks and record
# the result in design section 16.
suppressMessages(pkgload::load_all(quiet = TRUE))
stopifnot(requireNamespace("bench", quietly = TRUE))

# A deterministic document of about 1 MB: arrays of tables with strings,
# integers, floats, booleans, dates and arrays, and nested tables.
set.seed(16)
row <- function(i) {
  sprintf(
    paste(
      "[[products]]", "name = \"product %d\"", "sku = %d", "price = %.2f",
      "in_stock = %s", "released = 2024-%02d-%02d", "tags = [\"a%d\", \"b%d\", \"c\"]",
      "dims = { w = %d, h = %d }", "", "[products.meta]", "rating = %.1f",
      "updated = 2024-01-01T%02d:00:00Z", "",
      sep = "\n"
    ),
    i, 1e6 + i, runif(1, 1, 999), if (i %% 2) "true" else "false",
    i %% 12 + 1, i %% 28 + 1, i, i, i %% 100, i %% 50, runif(1, 0, 5), i %% 24
  )
}
doc <- paste(vapply(seq_len(4800), row, ""), collapse = "\n")
cat(sprintf("document: %.2f MB\n", nchar(doc, "bytes") / 1024^2))

# zuyaml writes no Date or POSIXct, so both emitters get date-times as text.
value <- toml_parse(doc, datetimes = "keep")
parse <- bench::mark(
  zutoml = toml_parse(doc),
  RcppTOML = RcppTOML::parseTOML(doc, fromFile = FALSE),
  check = FALSE, min_iterations = 10
)
emit <- bench::mark(
  zutoml = toml_emit(value),
  zuyaml = zuyaml::yaml_emit(value),
  check = FALSE, min_iterations = 10
)
show <- function(b, what) {
  med <- as.numeric(b$median)
  cat(sprintf("\n%s (median, ms):\n", what))
  for (i in seq_along(med)) cat(sprintf("  %-9s %8.1f\n", as.character(b$expression[i]), med[i] * 1000))
  cat(sprintf("  ratio     %8.2f (target: at most 2)\n", med[1] / med[2]))
}
show(parse, "parse 1 MB")
show(emit, "emit the parsed value")
cat("\n", R.version.string, ", ", Sys.info()[["machine"]], "\n", sep = "")
