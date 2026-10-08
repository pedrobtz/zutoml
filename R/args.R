# Argument checks shared by the exported functions (design section 12). A
# limit silently replaced by a default is a limit the caller did not set, so
# anything but a positive whole number (or Inf, where allowed) is refused.

ztm_check_limit <- function(x, arg, allow_inf = TRUE) {
  ok <- is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    x >= 1 &&
    (if (is.infinite(x)) allow_inf else x == floor(x) && x <= 2^63)
  if (!ok) {
    ztm_invalid_argument(
      arg,
      paste0(
        "`",
        arg,
        "` must be a positive whole number",
        if (allow_inf) " or Inf" else "",
        "."
      )
    )
  }
  as.double(x)
}

# A document as a raw vector of UTF-8 bytes: a string is translated to
# UTF-8 first; a raw vector is taken as it is.
ztm_input_bytes <- function(x, arg = "x") {
  if (is.raw(x)) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L && !is.na(x)) {
    return(charToRaw(enc2utf8(x)))
  }
  ztm_invalid_argument(
    arg,
    paste0("`", arg, "` must be a single string or a raw vector.")
  )
}

# The TOML version (design D17): "1.1.0", the default, or "1.0.0", strict.
# Returned as the integer the C layer takes (10 or 11).
ztm_check_version <- function(version) {
  if (
    !is.character(version) ||
      length(version) < 1L ||
      is.na(version[[1L]]) ||
      !version[[1L]] %in% c("1.1.0", "1.0.0")
  ) {
    ztm_invalid_argument("version", '`version` must be "1.1.0" or "1.0.0".')
  }
  if (version[[1L]] == "1.0.0") 10L else 11L
}
