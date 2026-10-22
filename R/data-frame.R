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
  nested <- vapply(x, is.list, NA)
  # Only a list that holds a list can change, so the rows of a long array of
  # tables of scalars are looked at in one sweep, not one call each.
  inner <- unlist(x[nested], recursive = FALSE, use.names = FALSE)
  owner <- rep.int(which(nested), lengths(x[nested]))
  deep <- unique(owner[vapply(inner, is.list, NA)])
  x[deep] <- lapply(x[deep], ztm_data_frames)
  if (
    is.null(names(x)) &&
      length(x) > 0L &&
      all(nested) &&
      all(vapply(x, ztm_is_table, TRUE))
  ) {
    return(ztm_as_data_frame(x))
  }
  x
}

# One pass over the rows: every cell is flattened once, matched to its column
# once and typed once, so the work is linear in the cells the rows hold.
ztm_as_data_frame <- function(rows) {
  keys <- unlist(lapply(rows, names), use.names = FALSE)
  cols <- unique(keys)
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
  cells <- unlist(lapply(rows, unname), recursive = FALSE, use.names = FALSE)
  at <- rep.int(seq_len(n), lengths(rows))
  kinds <- ztm_cell_kinds(cells)
  by_col <- split(seq_along(keys), factor(match(keys, cols), seq_along(cols)))
  out <- lapply(by_col, function(k) ztm_column(cells[k], kinds[k], at[k], n))
  names(out) <- cols
  structure(out, class = "data.frame", row.names = .set_row_names(n))
}

# The lattice kind of one cell for a column: a length-one atomic value that
# is not I()-marked (an array of one), or NA for anything else.
ztm_cell_kind <- function(v) {
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

# ztm_cell_kind() over a list of cells: the plain ones (unclassed, atomic,
# length one) by type in one sweep, only the classed ones one at a time.
ztm_cell_kinds <- function(cells) {
  kinds <- vapply(cells, typeof, "")
  single <- kinds %in%
    c("character", "logical", "integer", "double") &
    lengths(cells) == 1L
  classed <- vapply(cells, is.object, NA)
  kinds[!single] <- NA
  kinds[single & classed] <- vapply(cells[single & classed], ztm_cell_kind, "")
  kinds
}

# A column of n rows from the cells of the rows `at`, of kinds `kinds`: a
# vector when the cells share a kind, integer widening to double; else a list
# with NA for the rows that have no such key.
ztm_column <- function(cells, kinds, at, n) {
  if (!anyNA(kinds)) {
    u <- unique(kinds)
    if (setequal(u, c("integer", "double"))) {
      u <- "double"
    }
    if (length(u) == 1L) {
      col <- cells[[1L]][rep(NA_integer_, n)]
      if (u == "double") {
        col <- as.double(col)
      }
      # Filled unclassed, so no `[<-` method converts the cells one by one.
      a <- attributes(col)
      attributes(col) <- NULL
      col[at] <- unlist(cells, use.names = FALSE)
      attributes(col) <- a
      return(col)
    }
  }
  col <- rep(list(NA), n)
  col[at] <- cells
  col
}
