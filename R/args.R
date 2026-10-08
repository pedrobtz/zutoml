# Argument checks shared by the exported functions (design section 12). A
# limit silently replaced by a default is a limit the caller did not set, so
# anything but a positive whole number (or Inf, where allowed) is refused.

ztm_check_limit <- function(x, arg, allow_inf = TRUE, max = 2^63) {
  ok <- is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    x >= 1 &&
    (if (is.infinite(x)) allow_inf else x == floor(x) && x <= max)
  if (!ok) {
    ztm_invalid_argument(
      arg,
      paste0(
        "`",
        arg,
        "` must be a positive whole number",
        if (max < 2^63) paste0(" no larger than ", max) else "",
        if (allow_inf) " or Inf" else "",
        "."
      )
    )
  }
  as.double(x)
}

# max_depth is capped (ZTM_MAX_DEPTH_CAP in src/ztm_check.h): the build
# phase recurses once per level (design section 12).
ztm_max_depth_cap <- 1023 # test-info.R checks it against ZTM_MAX_DEPTH_CAP

ztm_check_depth <- function(x) {
  ztm_check_limit(x, "max_depth", allow_inf = FALSE, max = ztm_max_depth_cap)
}

# One of `choices`, by partial matching as match.arg() does, but refused as
# zutoml_invalid_argument rather than a bare error. Returns the 0-based index
# the C layer takes.
ztm_check_choice <- function(x, choices, arg) {
  if (identical(x, choices)) {
    return(0L)
  }
  i <- if (is.character(x) && length(x) == 1L && !is.na(x)) {
    pmatch(x, choices)
  } else {
    NA
  }
  if (is.na(i)) {
    ztm_invalid_argument(
      arg,
      paste0(
        "`",
        arg,
        "` must be one of ",
        paste0('"', choices, '"', collapse = ", "),
        "."
      )
    )
  }
  i - 1L
}

ztm_check_flag <- function(x, arg) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) {
    ztm_invalid_argument(arg, paste0("`", arg, "` must be TRUE or FALSE."))
  }
  x
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
