# toml_inline(), toml_literal(), toml_multiline(): how one value is written.

test_that("toml_inline() writes a table inline, wherever it is", {
  expect_toml(
    list(p = toml_inline(list(x = 1L, y = 2L))),
    "p = { x = 1, y = 2 }\n"
  )
  expect_toml(
    list(
      d = list(
        serde = toml_inline(list(
          version = "1.0",
          features = c("derive", "std")
        ))
      )
    ),
    "[d]\nserde = { version = \"1.0\", features = [\"derive\", \"std\"] }\n"
  )
  # Nested lists inside an inline table are inline too.
  expect_toml(
    list(p = toml_inline(list(q = list(r = 1L)))),
    "p = { q = { r = 1 } }\n"
  )
  # An unnamed list of tables: an array of inline tables, not [[headers]].
  expect_toml(
    list(a = toml_inline(list(list(x = 1L), list(x = 2L)))),
    "a = [{ x = 1 }, { x = 2 }]\n"
  )
  expect_toml(list(p = toml_inline(setNames(list(), character()))), "p = {}\n")
  # Its value comes before the tables, like any other value.
  expect_toml(
    list(t = list(a = 1L), p = toml_inline(list(x = 1L))),
    "p = { x = 1 }\n\n[t]\na = 1\n"
  )
})

test_that("toml_literal() writes literal strings, multi-line when it must", {
  expect_toml(
    list(p = toml_literal("C:\\Users\\tom")),
    "p = 'C:\\Users\\tom'\n"
  )
  expect_toml(list(p = toml_literal("it's")), "p = '''\nit's'''\n")
  expect_toml(list(p = toml_literal("a\nb")), "p = '''\na\nb'''\n")
  expect_toml(list(p = toml_literal(c("x", "y\\z"))), "p = ['x', 'y\\z']\n")
  for (bad in c("a'''b", "tab\tok\001no")) {
    err <- tryCatch(toml_emit(list(p = toml_literal(bad))), error = identity)
    expect_s3_class(err, "zutoml_invalid_argument")
    expect_identical(err$path, "p")
  }
})

test_that("toml_multiline() writes multi-line basic strings", {
  expect_toml(
    list(p = toml_multiline("one line")),
    "p = \"\"\"\none line\"\"\"\n"
  )
  expect_toml(list(p = toml_multiline("a\nb")), "p = \"\"\"\na\nb\"\"\"\n")
})

test_that("marked values read back as the unmarked values", {
  marked <- list(
    a = toml_inline(list(x = 1L, y = list(z = "w"))),
    b = toml_literal(c("C:\\x", "it's", "two\nlines", "''")),
    c = toml_multiline(c("x", "\"\"\"q\"\"\"", "end\"")),
    d = toml_inline(list(list(k = 1L), list(k = 2L)))
  )
  unmark <- function(v) {
    if (is.list(v)) {
      v[] <- lapply(v, unmark)
    }
    class(v) <- setdiff(
      oldClass(v),
      c("toml_inline", "toml_literal", "toml_multiline")
    )
    if (!length(oldClass(v))) {
      v <- unclass(v)
    }
    v
  }
  expect_identical(toml_parse(toml_emit(marked)), unmark(marked))
})

test_that("markers keep other classes and check their input", {
  expect_s3_class(toml_literal(I("x")), c("toml_literal", "AsIs"), exact = TRUE)
  expect_toml(list(p = toml_literal(I("x"))), "p = ['x']\n")
  for (f in list(toml_literal, toml_multiline)) {
    expect_s3_class(tryCatch(f(1), error = identity), "zutoml_invalid_argument")
  }
  expect_s3_class(
    tryCatch(toml_inline("x"), error = identity),
    "zutoml_invalid_argument"
  )
  expect_s3_class(
    tryCatch(toml_inline(data.frame(a = 1)), error = identity),
    "zutoml_invalid_argument"
  )
})
