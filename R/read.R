#' Read a TOML document from a file or connection
#'
#' Reads the input and parses it as [toml_parse()] would. At most
#' `max_size + 1` bytes are ever read, so an oversized file or an endless
#' connection fails with `zutoml_size_limit` rather than exhausting memory.
#'
#' A string with an `http`, `https`, `ftp`, `ftps` or `file` scheme is read
#' with [url()], any other string as a file path. A connection that is not
#' open is opened in `"rb"` mode and closed afterwards; an open one must be
#' binary, is read from its current position, and is left open.
#'
#' @param file A file path, a URL, or a connection.
#' @param ... Arguments passed on to [toml_parse()].
#' @inheritParams toml_parse
#' @return As [toml_parse()].
#' @export
#' @examples
#' path <- tempfile(fileext = ".toml")
#' writeLines(c("[package]", 'name = "zutoml"', "version = 1"), path)
#' toml_read(path)
#' unlink(path)
toml_read <- function(file, ..., max_size = 64 * 1024^2) {
  toml_parse(ztm_read_bounded(file, max_size), ..., max_size = max_size)
}

# Reads at most max_size + 1 bytes in 64 KiB blocks: one past the limit is
# enough to know the input is too big, and nothing more is ever held
# (design section 10). The loop is in R: R_ReadConnection() is experimental
# API and costs a NOTE (zucbor's reason).
ztm_read_bounded <- function(file, max_size) {
  max_size <- ztm_check_limit(max_size, "max_size")
  input <- zu_open_input(
    file,
    what = "file",
    prefix = "zutoml",
    abort = function(arg, message) ztm_invalid_argument(arg, message)
  )
  if (input$close) {
    on.exit(close(input$con), add = TRUE)
  }
  chunk <- 65536L
  chunks <- list()
  total <- 0
  repeat {
    want <- if (is.finite(max_size)) min(chunk, max_size + 1 - total) else chunk
    b <- tryCatch(
      readBin(input$con, "raw", n = want),
      error = function(e) {
        ztm_abort(
          "zutoml_io_error",
          paste0("could not read the input: ", conditionMessage(e))
        )
      }
    )
    if (length(b) == 0L) {
      break
    }
    chunks[[length(chunks) + 1L]] <- b
    total <- total + length(b)
    if (total > max_size) {
      ztm_raise_fault(list(
        status = "size_limit",
        line = NA_real_,
        column = NA_real_,
        offset = NA_real_,
        limit = "max_size",
        limit_value = max_size
      ))
    }
  }
  if (length(chunks) == 0L) raw() else unlist(chunks, use.names = FALSE)
}
