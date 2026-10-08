# data_frame = TRUE (design section 6.3): an array whose elements are all
# tables becomes a data frame, bottom-up, so nested arrays of tables become
# frames first. zujson's rules, with its cell budget.

ztm_max_df_cells <- function() {
  n <- getOption("zutoml.max_df_cells", 1e7)
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 1) {
    ztm_invalid_argument(
      "zutoml.max_df_cells",
      "`options(zutoml.max_df_cells = )` must be a single number of 1 or more."
    )
  }
  n
}

ztm_is_table <- function(x) {
  is.list(x) && !is.data.frame(x) && !is.null(names(x))
}

ztm_data_frames <- function(x) {
  if (!is.list(x) || is.data.frame(x)) {
    return(x)
  }
  x[] <- lapply(x, ztm_data_frames)
  if (
    is.null(names(x)) && length(x) > 0L && all(vapply(x, ztm_is_table, TRUE))
  ) {
    return(ztm_as_data_frame(x))
  }
  x
}

ztm_as_data_frame <- function(rows) {
  cols <- unique(unlist(lapply(rows, names), use.names = FALSE))
  n <- length(rows)
  if (as.double(n) * length(cols) > ztm_max_df_cells()) {
    stop(structure(
      class = c("zutoml_limit_error", "zutoml_error", "error", "condition"),
      list(
        message = paste0(
          "TOML limit reached: a data frame of ",
          n,
          " rows and ",
          length(cols),
          " columns is more than options(zutoml.max_df_cells) = ",
          format(ztm_max_df_cells(), scientific = FALSE),
          " cells"
        ),
        call = NULL,
        kind = "df_cell_limit",
        limit = "zutoml.max_df_cells",
        limit_value = ztm_max_df_cells()
      )
    ))
  }
  out <- lapply(cols, function(col) {
    ztm_column(lapply(rows, function(r) {
      if (col %in% names(r)) r[[col]] else NULL
    }))
  })
  names(out) <- cols
  structure(out, class = "data.frame", row.names = .set_row_names(n))
}

# The lattice kind of one cell for a column: a length-one atomic value that
# is not I()-marked (an array of one), or NA for anything else.
ztm_cell_kind <- function(v) {
  if (is.null(v)) {
    return("missing")
  }
  if (!is.atomic(v) || length(v) != 1L || inherits(v, "AsIs")) {
    return(NA_character_)
  }
  if (inherits(v, "toml_bigint")) {
    return("bigint")
  }
  if (inherits(v, "POSIXct")) {
    return(paste0("POSIXct:", attr(v, "tzone")))
  }
  if (inherits(v, "Date")) {
    return("Date")
  }
  if (inherits(v, "difftime")) {
    return("difftime")
  }
  if (is.object(v)) {
    return(NA_character_)
  }
  switch(
    typeof(v),
    character = "character",
    logical = "logical",
    integer = "integer",
    double = "double",
    NA_character_
  )
}

# A column from its cells (NULL where a row has no such key): a vector when
# the present cells share a kind, integer widening to double; else a list.
ztm_column <- function(cells) {
  kinds <- vapply(cells, ztm_cell_kind, "")
  present <- kinds[kinds != "missing"]
  if (length(present) && !anyNA(present)) {
    u <- unique(present)
    if (setequal(u, c("integer", "double"))) {
      u <- "double"
    }
    if (length(u) == 1L) {
      first <- cells[[which(kinds != "missing")[1L]]]
      col <- first[rep(NA_integer_, length(cells))]
      if (u == "double") {
        col <- as.double(col)
      }
      for (i in which(kinds != "missing")) {
        col[i] <- cells[[i]]
      }
      return(col)
    }
  }
  lapply(cells, function(v) if (is.null(v)) NA else v)
}
