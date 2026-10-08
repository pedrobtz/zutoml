# toml_parse(select = ): a path into the document (design D20). The whole
# document is still checked; only the selected value is built.

# `select` as a list of steps for C: character keys and integer (1-based)
# array indices. A single string is a path in TOML key syntax, as the
# positions table writes it ("tool.poetry", '"a.b".c', "products[2].name");
# a vector of two or more strings is a sequence of keys, taken as they are.
ztm_select_steps <- function(select) {
  if (is.null(select)) {
    return(NULL)
  }
  if (!is.character(select) || !length(select) || anyNA(select)) {
    ztm_invalid_argument(
      "select",
      "`select` must be a path string, such as \"tool.poetry\", or a vector of keys."
    )
  }
  if (length(select) > 1L) {
    return(as.list(enc2utf8(select)))
  }
  ztm_parse_path(enc2utf8(select))
}

# The steps of a path in TOML key syntax: keys (bare, "basic" or 'literal')
# separated by dots, each optionally followed by [i] indices.
ztm_parse_path <- function(path) {
  bad <- function(why) {
    ztm_invalid_argument("select", paste0("`select` is not a TOML path: ", why, "."))
  }
  chars <- strsplit(path, "", fixed = TRUE)[[1]]
  n <- length(chars)
  i <- 1L
  steps <- list()
  skip_ws <- function() {
    while (i <= n && chars[[i]] %in% c(" ", "\t")) i <<- i + 1L
  }
  repeat {
    skip_ws()
    if (i > n) bad("it ends where a key should be")
    c1 <- chars[[i]]
    if (c1 == "\"") {
      j <- i + 1L
      while (j <= n && chars[[j]] != "\"") {
        j <- j + if (chars[[j]] == "\\") 2L else 1L
      }
      if (j > n) bad("a quoted key is not closed")
      quoted <- paste(chars[i:j], collapse = "")
      key <- tryCatch(
        toml_parse(paste0("k = ", quoted))$k,
        zutoml_error = function(e) bad("a quoted key has an invalid escape")
      )
      i <- j + 1L
    } else if (c1 == "'") {
      j <- i + 1L
      while (j <= n && chars[[j]] != "'") j <- j + 1L
      if (j > n) bad("a quoted key is not closed")
      key <- paste(chars[seq_len(j - i - 1L) + i], collapse = "")
      i <- j + 1L
    } else if (grepl("^[A-Za-z0-9_-]$", c1)) {
      j <- i
      while (j <= n && grepl("^[A-Za-z0-9_-]$", chars[[j]])) j <- j + 1L
      key <- paste(chars[i:(j - 1L)], collapse = "")
      i <- j
    } else {
      bad(paste0("unexpected \"", c1, "\""))
    }
    steps[[length(steps) + 1L]] <- key
    skip_ws()
    while (i <= n && chars[[i]] == "[") {
      j <- i + 1L
      while (j <= n && grepl("^[0-9]$", chars[[j]])) j <- j + 1L
      if (j > n || chars[[j]] != "]" || j == i + 1L) bad("an index must be [1], [2], ...")
      idx <- as.numeric(paste(chars[(i + 1L):(j - 1L)], collapse = ""))
      if (idx < 1) bad("indices count from 1")
      steps[[length(steps) + 1L]] <- as.integer(idx)
      i <- j + 1L
      skip_ws()
    }
    if (i > n) break
    if (chars[[i]] != ".") bad(paste0("unexpected \"", chars[[i]], "\""))
    i <- i + 1L
  }
  steps
}

# Steps written as a canonical path, for messages and the condition's
# fields: keys bare where they can be, quoted otherwise; [i] for indices.
ztm_path_text <- function(steps) {
  out <- ""
  for (s in steps) {
    if (is.numeric(s)) {
      out <- paste0(out, "[", s, "]")
      next
    }
    key <- if (grepl("^[A-Za-z0-9_-]+$", s)) {
      s
    } else {
      esc <- gsub("([\"\\\\])", "\\\\\\1", s)
      paste0("\"", esc, "\"")
    }
    out <- if (nzchar(out)) paste0(out, ".", key) else key
  }
  out
}

ztm_raise_missing <- function(steps, failed) {
  path <- ztm_path_text(steps)
  found <- ztm_path_text(steps[seq_len(failed - 1L)])
  ztm_abort(
    "zutoml_missing_key",
    paste0(
      "TOML document has no `", path, "`",
      if (nzchar(found)) paste0(": `", found, "` has no `", ztm_path_text(steps[failed]), "`") else ""
    ),
    path = path,
    found = found
  )
}
