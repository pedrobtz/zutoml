# toml_validate(): the grammar and the table model (roadmap Stage 3, design
# sections 4, 9 and 12).

test_that("a valid document is TRUE, an invalid one FALSE", {
  expect_true(toml_validate("title = 'TOML'\n[owner]\nname = 'Tom'\n"))
  expect_true(toml_validate(""))
  expect_true(toml_validate(charToRaw("a = 1")))
  expect_false(toml_validate("a = 1\na = 2"))
})

test_that("error = TRUE raises the classed condition with its position", {
  err <- validate_error("a = 1\n  a = 2")
  expect_s3_class(err, "zutoml_parse_error")
  expect_identical(err$kind, "duplicate_key")
  expect_identical(c(err$line, err$column, err$offset), c(2, 3, 8))
  expect_snapshot(conditionMessage(err))
})

test_that("the grammar: keys, values, headers, line ends", {
  expect_identical(validate_kind("a = 1 2"), "unexpected_token")
  expect_identical(validate_kind("a = 'x' 'y'"), "unexpected_token")
  expect_identical(validate_kind("a ="), "unexpected_token")
  expect_identical(validate_kind("a = \n1"), "unexpected_token")
  expect_identical(validate_kind("a 1"), "unexpected_token")
  expect_identical(validate_kind("= 1"), "unexpected_token")
  expect_identical(validate_kind("a.= 1"), "unexpected_token")
  expect_identical(validate_kind("[a] b = 1"), "unexpected_token")
  expect_identical(validate_kind("[]"), "unexpected_token")
  expect_identical(validate_kind("[a"), "unexpected_token")
  expect_identical(validate_kind("[a]]"), "unexpected_token")
  expect_identical(validate_kind("[[a]"), "unexpected_token")
  expect_identical(validate_kind("[[a] ]"), "unexpected_token")
  expect_true(toml_validate("[ a . b ]\n[[ c ]]\n\"q\".'r' . s = 1"))
  expect_true(toml_validate("a = 1 # comment\n# only a comment\n\n"))
})

test_that("arrays: separators, newlines, trailing commas, nesting", {
  expect_true(toml_validate("a = [\n  1,\n  # c\n  2,\n]"))
  expect_true(toml_validate("a = [[1, 2], ['x'], [], [{b = 1}]]"))
  expect_true(toml_validate("a = []"))
  expect_identical(validate_kind("a = [1 2]"), "unexpected_token")
  expect_identical(validate_kind("a = [1,,2]"), "unexpected_token")
  expect_identical(validate_kind("a = [,]"), "unexpected_token")
  expect_identical(validate_kind("a = [1"), "unexpected_token")
})

test_that("inline tables: one line and no trailing comma under 1.0.0", {
  expect_true(toml_validate(
    "a = {b = 1, c.d = 'x', e = {f = []}}",
    version = "1.0.0"
  ))
  expect_true(toml_validate("a = {}", version = "1.0.0"))
  for (doc in c(
    "a = {b = 1,}",
    "a = {\nb = 1}",
    "a = {b = 1\n}",
    "a = {b = 1,\nc = 2}"
  )) {
    expect_identical(
      validate_kind(doc, version = "1.0.0"),
      "unexpected_token",
      label = doc
    )
    expect_true(toml_validate(doc), label = doc)
  }
  expect_true(toml_validate("a = {\n  b = 1, # one\n  c = 2,\n}"))
  expect_identical(validate_kind("a = {b = 1,,}"), "unexpected_token")
  expect_identical(validate_kind("a = {b\n= 1}"), "unexpected_token")
  expect_identical(validate_kind("a = {b = 1 c = 2}"), "unexpected_token")
})

test_that("duplicate keys are refused at the second definition", {
  expect_identical(validate_kind("a = 1\na = 2"), "duplicate_key")
  expect_identical(validate_kind("a = 1\n'a' = 2"), "duplicate_key")
  expect_identical(validate_kind("\"a\" = 1\n'a' = 2"), "duplicate_key")
  expect_identical(validate_kind("[t]\na = 1\na = 2"), "duplicate_key")
  expect_identical(validate_kind("a = {b = 1, b = 2}"), "duplicate_key")
  expect_identical(validate_kind("a = 1\na.b = 2"), "duplicate_key")
  expect_identical(validate_kind("a.b = 1\na.b.c = 2"), "duplicate_key")
  expect_identical(validate_kind("a.b.c = 1\na.b = 2"), "duplicate_key")
  expect_identical(validate_kind("a = 1\n[a]"), "duplicate_key")
  expect_identical(validate_kind("a = 1\n[a.b]"), "duplicate_key")
  # Keys are compared decoded: an escape and its character are one key.
  expect_identical(validate_kind("\"\\u0061\" = 1\na = 2"), "duplicate_key")
  # The empty key is a key.
  expect_identical(validate_kind("\"\" = 1\n'' = 2"), "duplicate_key")
  expect_true(toml_validate(
    "a.b = 1\na.c = 2\nb = {a = 1}\nc = [{a = 1}, {a = 2}]"
  ))
})

test_that("a table is defined once; implicit tables may be defined after", {
  expect_identical(validate_kind("[a]\n[a]"), "table_redefined")
  expect_identical(validate_kind("[a.b]\n[a]\n[a]"), "table_redefined")
  expect_true(toml_validate("[a.b.c]\n[a]\n[a.b]"))
  expect_true(toml_validate("[a.b]\nx = 1\n[a]\ny = 2"))
  expect_true(toml_validate("[a]\n[a.b]\n[a.c]"))
})

test_that("dotted keys and headers: what each may extend", {
  # A table created by dotted keys cannot be redefined by a header...
  expect_identical(
    validate_kind("[t1]\nt2.t3.v = 0\n[t1.t2]"),
    "table_redefined"
  )
  expect_identical(validate_kind("a.b = 1\n[a]"), "table_redefined")
  # ...but may get sub-tables from one.
  expect_true(toml_validate(
    "[fruit]\napple.color = 'red'\n[fruit.apple.texture]\nsmooth = true"
  ))
  expect_true(toml_validate(
    "[fruit]\napple.color = 'red'\n[[fruit.apple.seeds]]\nsize = 2"
  ))
  # Dotted keys cannot reach into a table defined by a header.
  expect_identical(
    validate_kind("[a.b.c]\nz = 9\n[a]\nb.c.t = 1"),
    "table_redefined"
  )
  # They may pass through a table a header only implied.
  expect_true(toml_validate("[a.b.c]\nz = 9\n[a]\nb.d = 1"))
  # ...which is then defined, so a header for it comes too late.
  expect_identical(
    validate_kind("[a.b.c]\n[a]\nb.d = 1\n[a.b]"),
    "table_redefined"
  )
})

test_that("inline tables are sealed once closed", {
  expect_identical(
    validate_kind("a = {b = 1}\na.c = 2"),
    "inline_table_extended"
  )
  expect_identical(validate_kind("a = {b = 1}\n[a]"), "inline_table_extended")
  expect_identical(validate_kind("a = {b = 1}\n[a.c]"), "inline_table_extended")
  expect_identical(
    validate_kind("a = {b = {c = 1}, b.d = 2}"),
    "inline_table_extended"
  )
  expect_identical(
    validate_kind("a = {b = 1}\n[[a.c]]"),
    "inline_table_extended"
  )
})

test_that("arrays of tables append; nothing else can be one", {
  expect_true(toml_validate(
    "[[a]]\nx = 1\n[[a]]\nx = 2\n[a.b]\ny = 1\n[[a.c]]"
  ))
  expect_true(toml_validate("[[a.b]]\nx = 1\n[a]\ny = 2"))
  expect_identical(validate_kind("[a]\n[[a]]"), "table_redefined")
  expect_identical(validate_kind("[[a]]\n[a]"), "table_redefined")
  expect_identical(validate_kind("a = []\n[[a]]"), "table_redefined")
  expect_identical(validate_kind("a = [{}]\n[[a]]"), "table_redefined")
  expect_identical(validate_kind("[[a.b]]\n[[a]]"), "table_redefined")
  expect_identical(validate_kind("[[a.b]]\n[a]\nb.y = 2"), "table_redefined")
  expect_identical(validate_kind("a = [1]\n[a.b]"), "table_redefined")
})

test_that("max_depth counts tables and arrays together", {
  expect_true(toml_validate("a = [[[1]]]", max_depth = 4))
  err <- validate_error("a = [[[1]]]", max_depth = 3)
  expect_s3_class(err, "zutoml_depth_limit")
  expect_identical(err$limit, "max_depth")
  expect_identical(err$limit_value, 3)
  expect_s3_class(
    validate_error("a.b.c = 1", max_depth = 2),
    "zutoml_depth_limit"
  )
  expect_s3_class(
    validate_error("[a.b.c]", max_depth = 2),
    "zutoml_depth_limit"
  )
  expect_s3_class(
    validate_error("a = {b = {c = 1}}", max_depth = 2),
    "zutoml_depth_limit"
  )
  expect_true(toml_validate("a.b = 1", max_depth = 2))
})

test_that("max_items counts keys and array elements", {
  expect_true(toml_validate("a = [1, 2]", max_items = 3))
  err <- validate_error("a = [1, 2, 3]", max_items = 3)
  expect_s3_class(err, "zutoml_item_limit")
  expect_identical(err$limit_value, 3)
  expect_s3_class(
    validate_error("a.b.c = 1", max_items = 2),
    "zutoml_item_limit"
  )
  expect_true(toml_validate("a = [1, 2, 3]", max_items = Inf))
})

test_that("max_depth must be a positive whole number, and not Inf", {
  expect_s3_class(
    tryCatch(toml_validate("a = 1", max_depth = Inf), error = identity),
    "zutoml_invalid_argument"
  )
  expect_s3_class(
    tryCatch(toml_validate("a = 1", error = NA), error = identity),
    "zutoml_invalid_argument"
  )
})

test_that("hostile inputs fail by class, not by crash or stack overflow", {
  skip_heavy()
  # 10^6 open brackets: the depth counter, never the C stack.
  err <- validate_error(paste0("a = ", strrep("[", 1e6)))
  expect_s3_class(err, "zutoml_depth_limit")
  err <- validate_error(paste0("a = ", strrep("{b = ", 1e5)))
  expect_s3_class(err, "zutoml_depth_limit")
  # A dotted key of 5 * 10^5 parts is a nesting, and the depth limit says so.
  err <- validate_error(paste0(strrep("a.", 5e5), "a = 1"))
  expect_s3_class(err, "zutoml_depth_limit")
  # 10^6 array-of-tables headers: within max_items, or refused by it.
  doc <- strrep("[[a]]\n", 1e6)
  expect_s3_class(validate_error(doc), "zutoml_item_limit")
  expect_true(toml_validate(doc, max_items = 2e6))
  # A million distinct keys parse in linear time; the last duplicate is
  # still found.
  keys <- paste0("k", seq_len(2e5), " = 1", collapse = "\n")
  expect_true(toml_validate(keys))
  expect_identical(validate_kind(paste0(keys, "\nk1 = 2")), "duplicate_key")
})
