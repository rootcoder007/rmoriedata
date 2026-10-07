# SPDX-License-Identifier: AGPL-3.0-or-later

# Equivalence classes over the quasi-identifiers, with a missing value as a level
# of its own. stats::aggregate() drops every row whose grouping value is NA, and in
# administrative data the rows with an unrecorded quasi-identifier are often the
# rarest, so dropping them hides exactly the classes a verifier exists to catch.
# Returns the class id per row and one row of keys per class (original values, NA
# kept), in order of first appearance.
.morie_qi_classes <- function(qi) {
  enc <- lapply(qi, function(col) {
    v <- as.character(col)
    ifelse(is.na(col), "\001NA", paste0("\002", v))
  })
  key <- if (length(enc) == 1L) enc[[1L]] else do.call(paste, c(enc, sep = "\003"))
  id <- match(key, unique(key))
  first <- match(seq_len(max(c(0L, id))), id)
  keys <- qi[first, , drop = FALSE]
  rownames(keys) <- NULL
  list(id = id, keys = keys)
}

#' k-anonymity verification
#'
#' Checks whether a data.frame satisfies k-anonymity over the supplied
#' quasi-identifier columns. A dataset is k-anonymous if every combination
#' of quasi-identifier values appears in at least `k` rows.
#'
#' A missing value (`NA`) in a quasi-identifier is treated as a value of
#' its own: rows with an unrecorded ward, age band or race form their own
#' classes and are counted, never dropped. Unrecorded values are often the
#' rarest records, which makes them the most re-identifiable, so they must
#' meet the threshold like any other class. Every row is accounted for:
#' the class sizes sum to `nrow(data)`.
#'
#' @param data data.frame.
#' @param quasi_identifiers Character vector of column names.
#' @param k Minimum equivalence-class size. Default 5 (a common
#'   public-health / open-data threshold).
#' @return A list with class \code{"morie_k_anon"} containing:
#' \describe{
#'   \item{\code{satisfies}}{logical, whether the dataset is k-anonymous.}
#'   \item{\code{k}}{the threshold used.}
#'   \item{\code{min_class_size}}{integer, size of the smallest class.}
#'   \item{\code{n_classes}}{integer, total number of equivalence classes.}
#'   \item{\code{n_violations}}{integer, number of classes below the threshold.}
#'   \item{\code{violating_classes}}{data.frame of class keys plus their
#'     \code{.n} sizes (empty data.frame when none).}
#'   \item{\code{summary}}{human-readable one-line summary.}
#' }
#' @export
#' @examples
#' df <- data.frame(
#'   age = c(25, 25, 25, 32, 32, 40),
#'   sex = c("F", "F", "F", "M", "M", "M")
#' )
#'
#' # k = 2: the class {age=40, sex=M} has only 1 row -> VIOLATED.
#' res <- morie_k_anonymity_verify(df, c("age", "sex"), k = 2)
#' res$summary
#' res$satisfies
#' res$violating_classes # the offending quasi-identifier combos
#'
#' # Loosening to k = 1 always holds; the default k = 5 is stricter.
#' morie_k_anonymity_verify(df, c("age", "sex"), k = 1)$satisfies
#' morie_k_anonymity_verify(df, c("age", "sex"))$satisfies # k = 5
#'
#' # A single quasi-identifier is fine too.
#' morie_k_anonymity_verify(df, "sex", k = 3)$min_class_size
#'
#' # On real bundled data: are (year, arrest) cells 5-anonymous?
#' morie_k_anonymity_verify(complaint_sample,
#'   c("year", "arrest"),
#'   k = 5
#' )$summary
morie_k_anonymity_verify <- function(data, quasi_identifiers, k = 5) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data.frame.", call. = FALSE)
  }
  if (!is.character(quasi_identifiers) || length(quasi_identifiers) == 0L) {
    stop("`quasi_identifiers` must be a non-empty character vector.",
      call. = FALSE
    )
  }
  missing_cols <- setdiff(quasi_identifiers, names(data))
  if (length(missing_cols) > 0L) {
    stop("Columns not found in `data`: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(k) != 1L || !is.numeric(k) || is.na(k) ||
    k < 1 || k != as.integer(k)) {
    stop("`k` must be a single positive integer.", call. = FALSE)
  }
  k <- as.integer(k)

  qi <- data[, quasi_identifiers, drop = FALSE]
  cls <- .morie_qi_classes(qi)
  class_sizes <- cls$keys
  class_sizes$.n <- as.integer(tabulate(cls$id, nbins = nrow(cls$keys)))
  # every row belongs to exactly one class: a verifier that loses rows cannot see them
  stopifnot(sum(class_sizes$.n) == nrow(data))

  min_class_size <- if (nrow(class_sizes) == 0L) 0L else min(class_sizes$.n)
  violating <- class_sizes[class_sizes$.n < k, , drop = FALSE]
  rownames(violating) <- NULL

  satisfies <- nrow(violating) == 0L && nrow(class_sizes) > 0L
  summary_txt <- sprintf(
    "k=%d: %s (min class size=%d; %d/%d classes below threshold)",
    k,
    if (satisfies) "SATISFIED" else "VIOLATED",
    as.integer(min_class_size),
    nrow(violating),
    nrow(class_sizes)
  )

  structure(
    list(
      satisfies         = satisfies,
      k                 = k,
      min_class_size    = as.integer(min_class_size),
      n_classes         = nrow(class_sizes),
      n_violations      = nrow(violating),
      violating_classes = violating,
      summary           = summary_txt
    ),
    class = "morie_k_anon"
  )
}

#' l-diversity verification
#'
#' Checks whether a data.frame satisfies l-diversity: within each
#' equivalence class defined by the quasi-identifiers, the sensitive
#' attribute must take at least `l` distinct values.
#'
#' Only known (non-`NA`) sensitive values count towards diversity: a class
#' whose rows read `"HIV"`, `NA`, `NA` tells an adversary the attribute is
#' HIV or withheld, which is diversity 1. Classes are formed as in
#' [morie_k_anonymity_verify()], with `NA` in a quasi-identifier as a
#' level of its own.
#'
#' @param data data.frame.
#' @param quasi_identifiers Character vector of QI column names.
#' @param sensitive Name of the sensitive-attribute column.
#' @param l Minimum number of distinct sensitive values per class.
#'   Default 3.
#' @return A list with class \code{"morie_l_div"} containing:
#' \describe{
#'   \item{\code{satisfies}}{logical.}
#'   \item{\code{l}}{the threshold used.}
#'   \item{\code{min_diversity}}{integer, lowest per-class distinct count.}
#'   \item{\code{n_classes}}{integer.}
#'   \item{\code{n_violations}}{integer, classes below the threshold.}
#'   \item{\code{violating_classes}}{data.frame of class keys plus their
#'     \code{.diversity} count.}
#'   \item{\code{summary}}{human-readable.}
#' }
#' @export
#' @examples
#' df <- data.frame(
#'   age = c(25, 25, 25, 25, 32, 32, 32),
#'   sex = c("F", "F", "F", "F", "M", "M", "M"),
#'   dx  = c("A", "B", "C", "A", "X", "Y", "Z")
#' )
#'
#' # Class {25,F} has 3 distinct dx (A,B,C); {32,M} has 3 (X,Y,Z) -> l=3 holds.
#' res <- morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 3)
#' res$summary
#' res$satisfies
#' res$min_diversity
#'
#' # Demanding l = 4 fails: no class has 4 distinct sensitive values.
#' bad <- morie_l_diversity_verify(df, c("age", "sex"), "dx", l = 4)
#' bad$satisfies
#' bad$violating_classes
#'
#' # k-anonymity and l-diversity are complementary: check both.
#' morie_k_anonymity_verify(df, c("age", "sex"), k = 3)$satisfies
morie_l_diversity_verify <- function(data, quasi_identifiers, sensitive, l = 3) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data.frame.", call. = FALSE)
  }
  if (!is.character(quasi_identifiers) || length(quasi_identifiers) == 0L) {
    stop("`quasi_identifiers` must be a non-empty character vector.",
      call. = FALSE
    )
  }
  if (!is.character(sensitive) || length(sensitive) != 1L) {
    stop("`sensitive` must be a single column name.", call. = FALSE)
  }
  missing_cols <- setdiff(c(quasi_identifiers, sensitive), names(data))
  if (length(missing_cols) > 0L) {
    stop("Columns not found in `data`: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }
  if (length(l) != 1L || !is.numeric(l) || is.na(l) ||
    l < 1 || l != as.integer(l)) {
    stop("`l` must be a single positive integer.", call. = FALSE)
  }
  l <- as.integer(l)

  qi <- data[, quasi_identifiers, drop = FALSE]
  sens <- data[[sensitive]]
  cls <- .morie_qi_classes(qi)
  diversity_tbl <- cls$keys
  # a missing sensitive value is the absence of a value, not a second one: a class whose
  # only known value is "HIV" has diversity 1 however many rows withhold it
  known <- !is.na(sens)
  diversity_tbl$.diversity <- vapply(seq_len(nrow(cls$keys)), function(g) {
    length(unique(sens[cls$id == g & known]))
  }, integer(1))
  min_div <- if (nrow(diversity_tbl) == 0L) 0L else min(diversity_tbl$.diversity)

  violating <- diversity_tbl[diversity_tbl$.diversity < l, , drop = FALSE]
  rownames(violating) <- NULL

  satisfies <- nrow(violating) == 0L && nrow(diversity_tbl) > 0L
  summary_txt <- sprintf(
    "l=%d: %s (min diversity=%d; %d/%d classes below threshold)",
    l,
    if (satisfies) "SATISFIED" else "VIOLATED",
    as.integer(min_div),
    nrow(violating),
    nrow(diversity_tbl)
  )

  structure(
    list(
      satisfies         = satisfies,
      l                 = l,
      min_diversity     = as.integer(min_div),
      n_classes         = nrow(diversity_tbl),
      n_violations      = nrow(violating),
      violating_classes = violating,
      summary           = summary_txt
    ),
    class = "morie_l_div"
  )
}

#' Cell suppression with complementary suppression and a recoverability audit
#'
#' Suppresses (sets to `NA`) every count below `threshold`, then, when
#' `return_complementary = TRUE`, hides further cells until no suppressed
#' value can be solved exactly from the table's row and column totals, which
#' a published table normally carries.
#'
#' Complements are added to a fixed point. A row or column holding exactly
#' one hidden cell gives that cell away by subtraction, so every line with a
#' hidden cell gets a second one; a complement placed for a row is a hidden
#' cell in its column too, so the passes repeat until no line holds a lone
#' hidden cell. That condition is necessary but not sufficient, so the
#' result is then audited exactly: a hidden cell is recoverable when the
#' linear system of row and column totals determines it (its indicator lies
#' in the row space of the constraints over the hidden cells). Any
#' recoverable cell receives another complement in its row, and the audit
#' repeats. Complements are taken from positive cells, preferring one in a
#' line that already holds a hidden cell (which creates no new lone cell),
#' then the largest such cell, which leaves the widest range for the hidden
#' values. A zero cell is never used as a complement: it would bound the
#' hidden values from below at nothing.
#'
#' The audit covers exact recovery from the margins. It does not compute
#' the feasible interval of each hidden cell, which bounds from
#' non-negativity can narrow; a table whose hidden values must stay inside
#' a wide interval needs an interval audit (linear programming) on top.
#'
#' Only finite numeric cells are eligible for suppression. \code{NA} cells
#' in the input pass through unchanged and are treated as unpublished.
#'
#' @param tbl A numeric matrix or 2-D table of counts. Will be coerced to
#'   matrix; row/column names are preserved.
#' @param threshold Minimum count to remain unsuppressed. Default 5.
#' @param return_complementary Logical; if \code{TRUE} (default), add
#'   complementary suppressions until no hidden cell is recoverable from the
#'   row and column totals.
#' @return A list with class \code{"morie_cell_suppress"}:
#' \describe{
#'   \item{\code{suppressed}}{numeric matrix, suppressed cells set to NA.}
#'   \item{\code{primary_mask}}{logical matrix, TRUE for primary suppressions.}
#'   \item{\code{complementary_mask}}{logical matrix, TRUE for complementary
#'     suppressions (all FALSE when \code{return_complementary = FALSE}).}
#'   \item{\code{recoverable_mask}}{logical matrix, TRUE for a hidden cell
#'     whose value the row and column totals determine exactly.}
#'   \item{\code{protected}}{logical, TRUE when no hidden cell is
#'     recoverable. Test this before publishing.}
#'   \item{\code{n_primary}}{integer.}
#'   \item{\code{n_complementary}}{integer.}
#'   \item{\code{n_recoverable}}{integer.}
#'   \item{\code{threshold}}{the threshold used.}
#' }
#' @export
#' @examples
#' tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60),
#'   nrow = 3,
#'   dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
#' )
#'
#' res <- morie_cell_suppress(tbl, threshold = 5)
#' res$suppressed # NA where suppressed
#' res$protected # no hidden cell can be solved from the totals
#' res$n_primary # cells below threshold
#' res$n_complementary # extra cells hidden to protect them
#'
#' # Without complements the small cells are hidden but recoverable.
#' bare <- morie_cell_suppress(tbl, threshold = 5, return_complementary = FALSE)
#' bare$protected
#' bare$recoverable_mask
#'
#' # Works on a 2-D table too; NA cells pass through untouched.
#' t2 <- as.table(matrix(c(2, 40, 30, 1), 2,
#'   dimnames = list(c("a", "b"), c("c", "d"))
#' ))
#' morie_cell_suppress(t2, threshold = 5)$suppressed
morie_cell_suppress <- function(tbl, threshold = 5, return_complementary = TRUE) {
  if (length(threshold) != 1L || !is.numeric(threshold) ||
    is.na(threshold) || threshold < 1) {
    stop("`threshold` must be a single positive number.", call. = FALSE)
  }
  if (length(return_complementary) != 1L ||
    !is.logical(return_complementary) || is.na(return_complementary)) {
    stop("`return_complementary` must be TRUE or FALSE.", call. = FALSE)
  }

  m <- as.matrix(tbl)
  if (!is.numeric(m)) {
    stop("`tbl` must be a numeric matrix or table.", call. = FALSE)
  }
  if (length(dim(m)) != 2L) {
    stop("`tbl` must be 2-dimensional.", call. = FALSE)
  }

  primary <- !is.na(m) & m > 0 & m < threshold
  hidden <- primary
  if (return_complementary && any(primary)) {
    budget <- length(m)
    repeat {
      added <- FALSE
      # lone hidden cells, rows then columns, to a fixed point
      for (pass in 1:2) {
        lines <- if (pass == 1L) seq_len(nrow(m)) else seq_len(ncol(m))
        for (k in lines) {
          h <- if (pass == 1L) hidden[k, ] else hidden[, k]
          if (sum(h) == 1L) {
            pick <- .morie_complement(m, hidden, k, by_row = pass == 1L)
            if (!is.na(pick)) {
              if (pass == 1L) hidden[k, pick] <- TRUE else hidden[pick, k] <- TRUE
              added <- TRUE
            }
          }
        }
      }
      if (added) next
      # exact audit: a cell the margins determine needs another complement in its row
      rec <- .morie_recoverable(m, hidden)
      if (!any(rec)) break
      cell <- which(rec, arr.ind = TRUE)[1L, ]
      j <- .morie_complement(m, hidden, cell[[1L]], by_row = TRUE)
      if (!is.na(j)) {
        hidden[cell[[1L]], j] <- TRUE
      } else {
        i <- .morie_complement(m, hidden, cell[[2L]], by_row = FALSE)
        if (is.na(i)) break # nothing left to hide in its row or column: reported below
        hidden[i, cell[[2L]]] <- TRUE
      }
      budget <- budget - 1L
      if (budget <= 0L) break
    }
  }
  complementary <- hidden & !primary
  recoverable <- .morie_recoverable(m, hidden)

  suppressed <- m
  suppressed[hidden] <- NA_real_

  structure(
    list(
      suppressed         = suppressed,
      primary_mask       = primary,
      complementary_mask = complementary,
      recoverable_mask   = recoverable,
      protected          = !any(recoverable),
      n_primary          = sum(primary),
      n_complementary    = sum(complementary),
      n_recoverable      = sum(recoverable),
      threshold          = threshold
    ),
    class = "morie_cell_suppress"
  )
}

# The complement for line k (a row when by_row, else a column): a positive,
# published cell, preferring one whose crossing line already holds a hidden cell,
# then the largest. NA when the line has none to give.
.morie_complement <- function(m, hidden, k, by_row) {
  vals <- if (by_row) m[k, ] else m[, k]
  h <- if (by_row) hidden[k, ] else hidden[, k]
  cand <- which(!h & !is.na(vals) & vals > 0)
  if (!length(cand)) return(NA_integer_)
  crossing <- vapply(cand, function(j) {
    if (by_row) any(hidden[, j]) else any(hidden[j, ])
  }, logical(1))
  cand[order(-crossing, -vals[cand])[1L]]
}

# Hidden cells the row and column totals determine exactly: cell c is determined iff its
# indicator vector lies in the row space of the margin constraints over the hidden cells.
.morie_recoverable <- function(m, hidden) {
  out <- matrix(FALSE, nrow(m), ncol(m), dimnames = dimnames(m))
  idx <- which(hidden, arr.ind = TRUE)
  if (!nrow(idx)) return(out)
  nh <- nrow(idx)
  # one constraint per row and per column total, over the hidden cells (lines x cells)
  A <- rbind(
    outer(seq_len(nrow(m)), idx[, 1L], "==") * 1,
    outer(seq_len(ncol(m)), idx[, 2L], "==") * 1
  )
  A <- A[rowSums(A) > 0, , drop = FALSE]
  r0 <- qr(A)$rank
  for (c in seq_len(nh)) {
    e <- numeric(nh)
    e[c] <- 1
    if (qr(rbind(A, e))$rank == r0) out[idx[c, 1L], idx[c, 2L]] <- TRUE
  }
  out
}
