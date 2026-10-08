# The toml-test suite, as tools/update-fixtures commits it. These helpers
# live here, not at the top of a test file, because
# devtools::test(shuffle = TRUE) reorders a file's top-level expressions.

toml_test_dir <- function() test_path("toml-test")

toml_test_manifest <- function() {
  utils::read.delim(
    file.path(toml_test_dir(), "manifest.tsv"),
    colClasses = "character",
    quote = ""
  )
}

# The cases for one TOML version: a data frame with `name` (the path without
# the extension), `toml` (the document's path) and, for valid cases, `json`
# (its tagged-JSON twin's path).
toml_test_cases <- function(kind = c("valid", "invalid"), version = "1.0.0") {
  kind <- match.arg(kind)
  m <- toml_test_manifest()
  m <- m[
    vapply(
      strsplit(m$toml, ";", fixed = TRUE),
      function(v) version %in% v,
      TRUE
    ),
  ]
  docs <- m$path[
    startsWith(m$path, paste0(kind, "/")) & endsWith(m$path, ".toml")
  ]
  name <- sub("\\.toml$", "", docs)
  out <- data.frame(
    name = name,
    toml = file.path(toml_test_dir(), docs),
    stringsAsFactors = FALSE
  )
  if (kind == "valid") {
    out$json <- file.path(toml_test_dir(), paste0(name, ".json"))
  }
  out
}

# A case's bytes, exactly as committed: some are CRLF or invalid UTF-8 on
# purpose, so they are read as raw, never as text.
toml_test_bytes <- function(path) readBin(path, "raw", file.size(path))

# ---- the suite's tagged JSON as the R value toml_parse() should return -----
#
# toml-test writes every scalar as {"type": ..., "value": "<text>"}, tables as
# JSON objects and arrays as JSON arrays. tagged_json_to_r() turns that into
# the value design section 6 says toml_parse(d, simplify = "none", ...)
# returns: every array a list, every table a named list, and scalars by type.
# `datetimes` and `local_time` mirror toml_parse()'s arguments.

tagged_json_read <- function(path) {
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

tagged_json_to_r <- function(
  x,
  datetimes = c("keep", "convert"),
  local_time = c("character", "difftime")
) {
  datetimes <- match.arg(datetimes)
  local_time <- match.arg(local_time)
  walk <- function(v) {
    if (is_tagged_scalar(v)) {
      return(tagged_scalar_to_r(v$type, v$value, datetimes, local_time))
    }
    if (is.null(names(v))) {
      # A JSON array: an unnamed list; an empty one is list().
      return(lapply(v, walk))
    }
    # A JSON object: a table. An empty table keeps its (empty) names.
    out <- lapply(v, walk)
    if (!length(out)) {
      out <- stats::setNames(list(), character())
    }
    out
  }
  out <- walk(x)
  if (!length(out)) {
    out <- stats::setNames(list(), character())
  }
  out
}

is_tagged_scalar <- function(v) {
  is.list(v) &&
    length(v) == 2L &&
    setequal(names(v), c("type", "value")) &&
    is.character(v$type) &&
    is.character(v$value)
}

tagged_scalar_to_r <- function(type, value, datetimes, local_time) {
  switch(
    type,
    string = enc2utf8(value),
    bool = switch(value, true = TRUE, false = FALSE, stop("bad bool: ", value)),
    integer = toml_test_integer(value),
    float = toml_test_float(value),
    datetime = ,
    "datetime-local" = if (datetimes == "keep") {
      toml_test_dt_text(value)
    } else {
      toml_test_datetime(value, type)
    },
    "date-local" = if (datetimes == "keep") value else as.Date(value),
    "time-local" = toml_test_time(value, datetimes, local_time),
    stop("unknown toml-test type: ", type)
  )
}

# design section 6.1: integer within R's range (but -2^31 is a double, since
# as an integer it is NA), double up to 2^53, toml_bigint beyond. The range is
# decided on the decimal text, never through a double.
toml_test_integer <- function(value) {
  neg <- startsWith(value, "-")
  digits <- sub("^0+(?=.)", "", sub("^[+-]", "", value), perl = TRUE)
  canonical <- if (neg && digits != "0") paste0("-", digits) else digits
  if (dec_le(digits, "2147483647")) {
    return(as.integer(canonical))
  }
  if (dec_le(digits, "9007199254740992")) {
    return(as.numeric(canonical))
  }
  structure(canonical, class = "toml_bigint")
}

# a <= b for non-negative decimal strings without leading zeros.
dec_le <- function(a, b) nchar(a) < nchar(b) || (nchar(a) == nchar(b) && a <= b)

toml_test_float <- function(value) {
  v <- tolower(sub("^\\+", "", value))
  switch(v, inf = Inf, "-inf" = -Inf, nan = , "-nan" = NaN, as.numeric(v))
}

toml_dt_re <- paste0(
  "^(\\d{4}-\\d{2}-\\d{2})[Tt ](\\d{2}):(\\d{2})(?::(\\d{2})(\\.\\d+)?)?",
  "([Zz]|[+-]\\d{2}:\\d{2})?$"
)

dt_parts <- function(value) {
  m <- regmatches(value, regexec(toml_dt_re, value, perl = TRUE))[[1]]
  if (!length(m)) {
    stop("not a toml-test date-time: ", value)
  }
  list(
    date = m[[2]],
    h = as.integer(m[[3]]),
    m = as.integer(m[[4]]),
    s = if (nzchar(m[[5]])) as.integer(m[[5]]) else 0L,
    frac = if (nzchar(m[[6]])) m[[6]] else "",
    offset = m[[7]]
  )
}

# "keep" text: RFC 3339 with an upper-case T and Z (design section 6.1).
toml_test_dt_text <- function(value) {
  p <- dt_parts(value)
  off <- if (p$offset %in% c("z", "Z")) "Z" else p$offset
  sprintf("%sT%02d:%02d:%02d%s%s", p$date, p$h, p$m, p$s, p$frac, off)
}

# Fractional seconds, truncated to microseconds (design section 6.1).
frac_secs <- function(frac) {
  if (!nzchar(frac)) {
    return(0)
  }
  digits <- substr(paste0(sub("^\\.", "", frac), "000000"), 1L, 6L)
  as.integer(digits) / 1e6
}

toml_test_datetime <- function(value, type) {
  p <- dt_parts(value)
  secs <- p$h * 3600 + p$m * 60 + p$s + frac_secs(p$frac)
  if (type == "datetime") {
    off <- if (p$offset %in% c("z", "Z")) {
      0
    } else {
      sign <- if (startsWith(p$offset, "-")) -1 else 1
      hm <- as.integer(strsplit(substring(p$offset, 2L), ":", fixed = TRUE)[[
        1
      ]])
      sign * (hm[[1]] * 3600 + hm[[2]] * 60)
    }
    days <- as.numeric(as.Date(p$date))
    return(structure(
      days * 86400 + secs - off,
      class = c("POSIXct", "POSIXt"),
      tzone = "UTC"
    ))
  }
  # Local date-time: a wall-clock time in the session's zone, tzone "".
  wall <- as.POSIXct(paste(p$date, "00:00:00"), tz = "")
  structure(as.numeric(wall) + secs, class = c("POSIXct", "POSIXt"), tzone = "")
}

toml_test_time <- function(value, datetimes, local_time) {
  m <- regmatches(
    value,
    regexec("^(\\d{2}):(\\d{2})(?::(\\d{2})(\\.\\d+)?)?$", value, perl = TRUE)
  )[[1]]
  if (!length(m)) {
    stop("not a toml-test local time: ", value)
  }
  s <- if (nzchar(m[[4]])) m[[4]] else "00"
  if (local_time == "character") {
    return(sprintf("%s:%s:%s%s", m[[2]], m[[3]], s, m[[5]]))
  }
  secs <- as.integer(m[[2]]) *
    3600 +
    as.integer(m[[3]]) * 60 +
    as.integer(s) +
    frac_secs(m[[5]])
  structure(secs, class = "difftime", units = "secs")
}

# ---- comparing a parsed value with the suite's expectation -----------------
#
# Returns NULL when `actual` matches `expected`, or a string naming the first
# difference and its key path. Exact everywhere except doubles: R's parser
# does not round every decimal literal correctly on every platform (macOS
# arm64), so a float expectation built with as.numeric() may be one ulp off
# zufast's correctly rounded value. Signs of zero and NaN are exact.
toml_test_diff <- function(actual, expected, path = "") {
  at <- if (nzchar(path)) path else "<document>"
  if (!identical(class(actual), class(expected))) {
    return(sprintf(
      "%s: class %s, expected %s",
      at,
      paste(class(actual), collapse = "/"),
      paste(class(expected), collapse = "/")
    ))
  }
  if (is.list(actual)) {
    if (!identical(names(actual), names(expected))) {
      return(sprintf(
        "%s: names %s, expected %s",
        at,
        deparse1(names(actual)),
        deparse1(names(expected))
      ))
    }
    if (length(actual) != length(expected)) {
      return(sprintf(
        "%s: length %d, expected %d",
        at,
        length(actual),
        length(expected)
      ))
    }
    nm <- names(expected)
    for (i in seq_along(expected)) {
      sub <- if (is.null(nm)) {
        sprintf("%s[%d]", path, i)
      } else if (nzchar(path)) {
        paste0(path, ".", nm[[i]])
      } else {
        nm[[i]]
      }
      d <- toml_test_diff(actual[[i]], expected[[i]], sub)
      if (!is.null(d)) return(d)
    }
    return(NULL)
  }
  if (
    is.double(expected) && !inherits(expected, c("POSIXct", "Date", "difftime"))
  ) {
    same <- (is.nan(actual) && is.nan(expected)) ||
      (!is.nan(actual) &&
        !is.nan(expected) &&
        (identical(actual, expected) ||
          (is.finite(expected) &&
            expected != 0 &&
            abs(actual - expected) <= 2 * .Machine$double.eps * abs(expected))))
    if (same && expected == 0 && !is.nan(expected)) {
      same <- identical(1 / actual, 1 / expected)
    }
    if (!same) {
      return(sprintf(
        "%s: %s, expected %s",
        at,
        format(actual, digits = 17),
        format(expected, digits = 17)
      ))
    }
    return(NULL)
  }
  if (inherits(expected, "POSIXct")) {
    if (
      !identical(attr(actual, "tzone"), attr(expected, "tzone")) ||
        abs(unclass(actual) - unclass(expected)) > 5e-7
    ) {
      return(sprintf(
        "%s: %s, expected %s",
        at,
        format(actual, "%Y-%m-%d %H:%M:%OS6 %Z"),
        format(expected, "%Y-%m-%d %H:%M:%OS6 %Z")
      ))
    }
    return(NULL)
  }
  if (inherits(expected, "difftime")) {
    if (
      !identical(units(actual), units(expected)) ||
        abs(unclass(actual) - unclass(expected)) > 5e-7
    ) {
      return(sprintf(
        "%s: %s, expected %s",
        at,
        format(actual),
        format(expected)
      ))
    }
    return(NULL)
  }
  if (!identical(actual, expected)) {
    return(sprintf(
      "%s: %s, expected %s",
      at,
      deparse1(actual),
      deparse1(expected)
    ))
  }
  NULL
}

expect_toml_test_value <- function(actual, expected, case) {
  d <- toml_test_diff(actual, expected)
  expect(is.null(d), sprintf("toml-test %s: %s", case, d))
  invisible(actual)
}

# A tagged scalar, for hand-written expectations.
tj <- function(type, value) list(type = type, value = value)
