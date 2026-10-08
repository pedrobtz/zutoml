# The lexer's token table (roadmap Stage 1). Internal: the lexer's tests and
# tools/run-conformance use it until the grammar lands at Stage 3.
ztm_tokens <- function(
  x,
  version = c("1.1.0", "1.0.0"),
  max_size = 64 * 1024^2,
  max_string = 2^31 - 1
) {
  bytes <- ztm_input_bytes(x)
  version <- ztm_check_version(version)
  max_size <- ztm_check_limit(max_size, "max_size")
  max_string <- ztm_check_limit(max_string, "max_string")
  out <- .Call(zutoml_tokens, bytes, version, max_size, max_string)
  if (!is.null(out$fault)) {
    ztm_raise_fault(out$fault)
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}
