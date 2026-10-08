# A document for test-select.R. Here, not in the test file, because
# devtools::test(shuffle = TRUE) reorders a file's top-level code.
select_doc <- function() {
  paste(
    "title = 'x'",
    "\"a.b\" = { c = 1 }",
    "arr = [10, [20, 30]]",
    "[tool.poetry]",
    "name = 'spam'",
    "when = 1979-05-27T07:32:00",
    "[[products]]",
    "name = 'Hammer'",
    "[[products]]",
    "name = 'Nail'",
    "color = 'gray'",
    "[tool.black]",
    "line-length = 88",
    sep = "\n"
  )
}
