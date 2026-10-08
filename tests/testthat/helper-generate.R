# Random R values for the round-trip properties (design section 15, roadmap
# Stage 6). Every value is one toml_emit() writes and toml_parse() reads
# back identical(): the generator avoids exactly the losses design section
# 7.4 lists, so a difference is a bug, not a documented loss.
#
#   - whole numbers are integers (a whole double is written as an integer);
#   - a table's values come before its sub-tables (the emitter's order);
#   - an unnamed list holds values of different kinds, or containers, so
#     the lattice does not turn it into a vector;
#   - a vector of one is I()-marked, as toml_parse() returns it;
#   - local date-times use the session's zone, which the test fixes.

gen_string <- function() {
  pool <- c(
    "",
    "plain",
    "with \"quotes\"",
    "back\\slash",
    "tab\there",
    "two\nlines",
    "café",
    "水\U0001F600",
    "control\001\177",
    "'''",
    "\"\"\"x\"\"\"",
    "trailing\"",
    "   spaced   ",
    "#not a comment",
    "= sign",
    "a\r\nb"
  )
  sample(pool, 1L)
}

gen_double <- function() {
  # Not whole, or not finite, or negative zero: anything whole would be
  # written as an integer.
  switch(
    sample(6L, 1L),
    runif(1, -1e6, 1e6) + 0.5,
    exp(runif(1, -700, 700)) * sample(c(-1, 1), 1L),
    NaN,
    sample(c(Inf, -Inf), 1L),
    neg_zero(),
    2^63 * 4
  )
}

gen_posixct <- function(local) {
  secs <- sample(-2e9:4e9, 1L) + sample(0:999999, 1L) / 1e6
  structure(
    secs,
    class = c("POSIXct", "POSIXt"),
    tzone = if (local) "" else "UTC"
  )
}

# One scalar of `kind`, length one.
gen_scalar <- function(kind) {
  switch(
    kind,
    string = gen_string(),
    integer = sample(
      c(-.Machine$integer.max, -1L, 0L, 1L, 42L, .Machine$integer.max),
      1L
    ),
    wide = sample(c(-2^31, 2^31, 2^53, -2^53, 1e15), 1L),
    bigint = toml_bigint(sample(
      c("9007199254740993", "-9223372036854775808", "9223372036854775807"),
      1L
    )),
    double = gen_double(),
    logical = sample(c(TRUE, FALSE), 1L),
    # Double-backed, as toml_parse() returns them.
    date = as.Date(as.numeric(sample(-700000:2900000, 1L))),
    datetime = gen_posixct(FALSE),
    local = gen_posixct(TRUE),
    time = structure(
      sample(0:86399, 1L) + sample(c(0, 0.25, 0.5), 1L),
      class = "difftime",
      units = "secs"
    )
  )
}

scalar_kinds <- c(
  "string",
  "integer",
  "wide",
  "bigint",
  "double",
  "logical",
  "date",
  "datetime",
  "local",
  "time"
)

# A vector of one kind: length two to five, or one marked I().
gen_vector <- function(kind) {
  n <- sample(c(1L, 2L, 3L, 5L), 1L)
  v <- do.call(c, lapply(seq_len(n), function(i) gen_scalar(kind)))
  if (kind == "local") {
    attr(v, "tzone") <- ""
  }
  if (kind == "datetime") {
    attr(v, "tzone") <- "UTC"
  }
  if (kind == "bigint") {
    v <- toml_bigint(v)
  }
  if (kind == "time") {
    v <- structure(as.numeric(v), class = "difftime", units = "secs")
  }
  if (n == 1L) I(v) else v
}

# A value. In a table's own values (`top`), never a named list: the emitter
# writes a table under its own header, after the values (design 7.4).
gen_value <- function(depth, top = FALSE) {
  r <- sample(if (top) 9L else 10L, 1L)
  if (depth <= 0L || r <= 5L) {
    return(gen_scalar(sample(scalar_kinds, 1L)))
  }
  if (r <= 7L) {
    return(gen_vector(sample(scalar_kinds, 1L)))
  }
  if (r <= 9L) {
    # A list of values of two kinds the lattice cannot join, so it stays a
    # list: not two numeric kinds, which widen to one vector.
    numeric <- c("integer", "wide", "bigint", "double")
    repeat {
      k <- sample(scalar_kinds, 2L)
      if (!all(k %in% numeric)) break
    }
    return(list(gen_scalar(k[[1]]), gen_scalar(k[[2]]), gen_value(depth - 1L)))
  }
  gen_table(depth - 1L, inline = TRUE)
}

gen_key <- function(i) {
  sample(
    c(paste0("k", i), paste0("key ", i), paste0("k.", i), paste0("é", i)),
    1L
  )
}

# A table: its values first, then its sub-tables and arrays of tables.
gen_table <- function(depth, inline = FALSE) {
  nv <- sample(0:4, 1L)
  values <- lapply(seq_len(nv), function(i) gen_value(depth, top = !inline))
  names(values) <- vapply(seq_len(nv), gen_key, "")
  if (inline || depth <= 0L) {
    return(if (nv) values else stats::setNames(list(), character()))
  }
  nt <- sample(0:2, 1L)
  tables <- lapply(seq_len(nt), function(i) {
    if (sample(3L, 1L) == 1L) {
      lapply(seq_len(sample(1:3, 1L)), function(j) gen_table(depth - 2L))
    } else {
      gen_table(depth - 1L)
    }
  })
  names(tables) <- sprintf("t%d", seq_len(nt))
  out <- c(values, tables)
  if (!length(out)) stats::setNames(list(), character()) else out
}
