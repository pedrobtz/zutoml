# The lexer (roadmap Stage 1, design section 9).

test_that("a simple document tokenises with positions", {
  t <- ztm_tokens("a = 1\n[t]\nb = 'x'\n")
  expect_identical(
    t$type,
    c(
      "bare_key",
      "equals",
      "integer",
      "newline",
      "lbracket",
      "bare_key",
      "rbracket",
      "newline",
      "bare_key",
      "equals",
      "literal_string",
      "newline",
      "eof"
    )
  )
  expect_identical(t$line[t$type == "bare_key"], c(1, 2, 3))
  expect_identical(t$column[t$type == "equals"], c(3, 3))
  expect_identical(t$offset[t$type == "literal_string"], 14)
})

test_that("keys and values are lexed by mode", {
  # true and 1234 are keys before '=', values after it.
  expect_identical(tok_types("true = true"), c("bare_key", "equals", "bool"))
  expect_identical(tok_types("1234 = 1234"), c("bare_key", "equals", "integer"))
  expect_identical(
    tok_types("a.b.c = 1"),
    c("bare_key", "dot", "bare_key", "dot", "bare_key", "equals", "integer")
  )
  expect_identical(
    tok_types("\"a\".'b' = 1"),
    c("basic_string", "dot", "literal_string", "equals", "integer")
  )
})

test_that("headers, arrays and inline tables nest by bracket", {
  expect_identical(tok_types("[[a]]"), c("lbracket2", "bare_key", "rbracket2"))
  # In a value, [[ and ]] are two brackets each.
  expect_identical(
    tok_types("a = [[1]]"),
    c(
      "bare_key",
      "equals",
      "lbracket",
      "lbracket",
      "integer",
      "rbracket",
      "rbracket"
    )
  )
  expect_identical(
    tok_types("a = [{b = 1}, {}]"),
    c(
      "bare_key",
      "equals",
      "lbracket",
      "lbrace",
      "bare_key",
      "equals",
      "integer",
      "rbrace",
      "comma",
      "lbrace",
      "rbrace",
      "rbracket"
    )
  )
  expect_identical(
    tok_types("a = [\n  1, # one\n  2,\n]"),
    c(
      "bare_key",
      "equals",
      "lbracket",
      "newline",
      "integer",
      "comma",
      "newline",
      "integer",
      "comma",
      "newline",
      "rbracket"
    )
  )
})

test_that("scalars are classified by shape", {
  value <- function(v) tok_types(paste("a =", v))[[3]]
  expect_identical(value("+99"), "integer")
  expect_identical(value("0xDEADbeef"), "integer")
  expect_identical(value("0o755"), "integer")
  expect_identical(value("0b1101"), "integer")
  expect_identical(value("1_000"), "integer")
  expect_identical(value("3.14"), "float")
  expect_identical(value("5e+22"), "float")
  expect_identical(value("-inf"), "float")
  expect_identical(value("nan"), "float")
  expect_identical(value("false"), "bool")
  expect_identical(value("1979-05-27T07:32:00Z"), "datetime")
  expect_identical(value("1979-05-27T00:32:00.999999-07:00"), "datetime")
  expect_identical(value("1979-05-27 07:32:00Z"), "datetime")
  expect_identical(value("1979-05-27T07:32:00"), "local_datetime")
  expect_identical(value("1979-05-27"), "local_date")
  expect_identical(value("07:32:00"), "local_time")
  expect_identical(value("'''x'''"), "ml_literal_string")
  expect_identical(value("\"\"\"x\"\"\""), "ml_basic_string")
})

test_that("strings measure their decoded length", {
  t <- ztm_tokens("a = \"\\u00e9\\U0001F600\\t\"")
  expect_identical(t$decoded[t$type == "basic_string"], 2 + 4 + 1)
  # The newline after the opening delimiter is trimmed; CRLF counts as LF;
  # a line-ending backslash removes the whitespace that follows.
  t <- ztm_tokens(bytes("a = \"\"\"\r\nab\r\nc \\\r\n   d\"\"\""))
  expect_identical(
    t$decoded[t$type == "ml_basic_string"],
    as.double(nchar("ab\nc d"))
  )
  # Up to two quotes sit against the closing delimiter.
  t <- ztm_tokens("a = '''''x'''''")
  expect_identical(t$decoded[t$type == "ml_literal_string"], 5)
})

test_that("multi-line strings advance the line count", {
  t <- ztm_tokens("a = \"\"\"\none\ntwo\"\"\"\nb = 1")
  expect_identical(t$line[t$type == "bare_key"], c(1, 4))
})

test_that("a byte-order mark is skipped and columns count code points", {
  t <- ztm_tokens(bytes(c(0xEF, 0xBB, 0xBF), "a = 1"))
  expect_identical(t$type[[1]], "bare_key")
  expect_identical(t$column[[1]], 1)
  t <- ztm_tokens("\"\u00e9\u00e9\" = 1")
  expect_identical(t$column[t$type == "equals"], 6)
})

test_that("every control character in every string form is refused", {
  controls <- c(0:8, 10:31, 127)
  forms <- list(
    basic = c("\"", "\""),
    literal = c("'", "'"),
    ml_basic = c("\"\"\"", "\"\"\""),
    ml_literal = c("'''", "'''"),
    comment = c("# ", "")
  )
  for (form in names(forms)) {
    for (cc in controls) {
      # A newline is legal in multi-line strings, ends a single-line string
      # (unterminated) and ends a comment; CR alone is a control character.
      if (cc == 10) {
        next
      }
      d <- forms[[form]]
      doc <- if (form == "comment") {
        bytes("a = 1 ", d[[1]], "x", cc, "y")
      } else {
        bytes("a = ", d[[1]], "x", cc, "y", d[[2]])
      }
      err <- lex_error(doc)
      expect_s3_class(err, "zutoml_parse_error")
      expect_identical(err$kind, "control_character", label = paste(form, cc))
      expect_identical(err$line, 1)
      expect_identical(
        err$offset,
        if (form == "comment") 9 else 5 + nchar(d[[1]])
      )
    }
  }
})

test_that("a bare CR and a control character outside strings are refused", {
  expect_identical(lex_error(bytes("a = 1\rb = 2"))$kind, "control_character")
  expect_identical(lex_error(bytes("a = 1", 0, "\n"))$kind, "control_character")
  expect_identical(lex_error(bytes("a = 1", 127))$kind, "control_character")
})

test_that("CRLF is a newline", {
  t <- ztm_tokens(bytes("a = 1\r\nb = 2\r\n"))
  expect_identical(sum(t$type == "newline"), 2L)
  expect_identical(t$line[t$type == "bare_key"], c(1, 2))
})

test_that("escapes TOML does not define are refused at the backslash", {
  for (e in c("\\ ", "\\a", "\\'", "\\/", "\\E", "\\X41")) {
    err <- lex_error(paste0("a = \"z", e, "\""))
    expect_identical(err$kind, "bad_escape", label = e)
    expect_identical(err$column, 7)
  }
})

test_that("unicode escapes must be scalar values with all their digits", {
  expect_identical(lex_error("a = \"\\uD800\"")$kind, "bad_unicode_escape")
  expect_identical(lex_error("a = \"\\U00110000\"")$kind, "bad_unicode_escape")
  expect_identical(lex_error("a = \"\\u12\"")$kind, "bad_unicode_escape")
  expect_identical(lex_error("a = \"\\U0000004\"")$kind, "bad_unicode_escape")
})

test_that("strings must end on their line, or before the end of input", {
  expect_identical(lex_error("a = \"abc\nb = 1")$kind, "unterminated_string")
  expect_identical(lex_error("a = 'abc")$kind, "unterminated_string")
  expect_identical(lex_error("a = \"\"\"abc\n")$kind, "unterminated_string")
  expect_identical(lex_error("a = \"abc\\")$kind, "unterminated_string")
})

test_that("a multi-line string cannot be a key", {
  expect_identical(lex_error("\"\"\"a\"\"\" = 1")$kind, "multiline_key")
  expect_identical(lex_error("'''a''' = 1")$kind, "multiline_key")
})

test_that("invalid UTF-8 is refused at the first bad byte", {
  cases <- list(
    lone_continuation = bytes("a = 'x", 0x80, "'"),
    overlong = bytes("a = 'x", 0xC0, 0xAF, "'"),
    surrogate = bytes("a = 'x", 0xED, 0xA0, 0x80, "'"),
    beyond = bytes("a = 'x", 0xF4, 0x90, 0x80, 0x80, "'"),
    truncated = bytes("a = 'x", 0xE2, 0x82)
  )
  for (nm in names(cases)) {
    err <- lex_error(cases[[nm]])
    expect_identical(err$kind, "invalid_utf8", label = nm)
    expect_identical(err$offset, 6, label = nm)
  }
  err <- lex_error(bytes("a = 1\nb = 'x", 0xFF, "'"))
  expect_identical(c(err$line, err$column), c(2, 7))
})

test_that("characters that start no token are refused", {
  expect_identical(lex_error("a = foo")$kind, "invalid_value")
  expect_identical(lex_error("a = True")$kind, "invalid_value")
  expect_identical(lex_error("\u00e9 = 1")$kind, "unexpected_character")
  expect_identical(lex_error("a = @")$kind, "unexpected_character")
  expect_identical(lex_error("a = 1979-05-27X07:32:00")$kind, "invalid_value")
})

test_that("max_string bounds a string's or a key's decoded length", {
  expect_identical(nrow(ztm_tokens("a = 'xyz'", max_string = 3)), 4L)
  err <- lex_error("a = 'xyzw'", max_string = 3)
  expect_s3_class(err, "zutoml_string_limit")
  expect_s3_class(err, "zutoml_limit_error")
  expect_identical(err$limit, "max_string")
  expect_identical(err$limit_value, 3)
  expect_identical(err$column, 5)
  # Decoded, not raw: six bytes of escape are one byte of string.
  expect_identical(nrow(ztm_tokens("a = \"\\u0041\"", max_string = 1)), 4L)
  expect_s3_class(lex_error("abcd = 1", max_string = 3), "zutoml_string_limit")
})

test_that("max_size bounds the input in bytes", {
  expect_identical(nrow(ztm_tokens("a = 1", max_size = 5)), 4L)
  err <- lex_error("a = 1", max_size = 4)
  expect_s3_class(err, "zutoml_size_limit")
  expect_identical(err$limit_value, 4)
  expect_true(is.na(err$line))
})

test_that("limits must be positive whole numbers or Inf", {
  for (bad in list(0, -1, 1.5, NA, "1", c(1, 2), NULL)) {
    err <- tryCatch(ztm_tokens("a = 1", max_size = bad), error = identity)
    expect_s3_class(err, "zutoml_invalid_argument")
    expect_identical(err$arg, "max_size")
  }
  expect_identical(nrow(ztm_tokens("a = 1", max_size = Inf)), 4L)
})

test_that("the input is a single string or a raw vector", {
  for (bad in list(1, c("a", "b"), NA_character_, list("a"))) {
    expect_s3_class(
      tryCatch(ztm_tokens(bad), error = identity),
      "zutoml_invalid_argument"
    )
  }
  expect_identical(ztm_tokens(raw())$type, "eof")
})

test_that("TOML 1.1 adds \\e and \\xHH; 1.0.0 refuses them", {
  t <- ztm_tokens("a = \"\\e\\x41\\xe9\"")
  expect_identical(t$decoded[t$type == "basic_string"], 1 + 1 + 2)
  for (e in c("\\e", "\\x41")) {
    err <- lex_error(paste0("a = \"z", e, "\""), version = "1.0.0")
    expect_identical(err$kind, "bad_escape", label = e)
  }
  expect_identical(lex_error("a = \"\\x4\"")$kind, "bad_unicode_escape")
})

test_that("version must be 1.1.0 or 1.0.0", {
  err <- tryCatch(ztm_tokens("a = 1", version = "2.0"), error = identity)
  expect_s3_class(err, "zutoml_invalid_argument")
  expect_identical(err$arg, "version")
})
