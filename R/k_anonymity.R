# SPDX-License-Identifier: AGPL-3.0-or-later

#' k-anonymity verification
#'
#' Checks whether a data.frame satisfies k-anonymity over the supplied
#' quasi-identifier columns. A dataset is k-anonymous if every combination
#' of quasi-identifier values appears in at least `k` rows.
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
#' res$violating_classes        # the offending quasi-identifier combos
#'
#' # Loosening to k = 1 always holds; the default k = 5 is stricter.
#' morie_k_anonymity_verify(df, c("age", "sex"), k = 1)$satisfies
#' morie_k_anonymity_verify(df, c("age", "sex"))$satisfies   # k = 5
#'
#' # A single quasi-identifier is fine too.
#' morie_k_anonymity_verify(df, "sex", k = 3)$min_class_size
#'
#' # On real bundled data: are (year, arrest) cells 5-anonymous?
#' morie_k_anonymity_verify(complaint_sample,
#'   c("year", "arrest"), k = 5)$summary
morie_k_anonymity_verify <- function(data, quasi_identifiers, k = 5) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data.frame.", call. = FALSE)
  }
  if (!is.character(quasi_identifiers) || length(quasi_identifiers) == 0L) {
    stop("`quasi_identifiers` must be a non-empty character vector.",
         call. = FALSE)
  }
  missing_cols <- setdiff(quasi_identifiers, names(data))
  if (length(missing_cols) > 0L) {
    stop("Columns not found in `data`: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  if (length(k) != 1L || !is.numeric(k) || is.na(k) ||
        k < 1 || k != as.integer(k)) {
    stop("`k` must be a single positive integer.", call. = FALSE)
  }
  k <- as.integer(k)

  qi <- data[, quasi_identifiers, drop = FALSE]
  class_sizes <- stats::aggregate(
    list(.n = rep(1L, nrow(qi))),
    by = as.list(qi),
    FUN = sum
  )
  names(class_sizes)[names(class_sizes) == ".n"] <- ".n"

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
         call. = FALSE)
  }
  if (!is.character(sensitive) || length(sensitive) != 1L) {
    stop("`sensitive` must be a single column name.", call. = FALSE)
  }
  missing_cols <- setdiff(c(quasi_identifiers, sensitive), names(data))
  if (length(missing_cols) > 0L) {
    stop("Columns not found in `data`: ",
         paste(missing_cols, collapse = ", "), call. = FALSE)
  }
  if (length(l) != 1L || !is.numeric(l) || is.na(l) ||
        l < 1 || l != as.integer(l)) {
    stop("`l` must be a single positive integer.", call. = FALSE)
  }
  l <- as.integer(l)

  qi <- data[, quasi_identifiers, drop = FALSE]
  sens <- data[[sensitive]]
  diversity_tbl <- stats::aggregate(
    list(.diversity = sens),
    by = as.list(qi),
    FUN = function(v) length(unique(v))
  )
  diversity_tbl$.diversity <- as.integer(diversity_tbl$.diversity)
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

#' Cell suppression with optional complementary suppression
#'
#' Standard StatCan / open-data complementary-suppression: identifies
#' counts below `threshold`, suppresses them by setting to `NA`, and
#' (if `return_complementary = TRUE`) also suppresses the smallest other
#' count in each affected row and column so the suppressed value can't be
#' reconstructed from marginals.
#'
#' Only finite numeric cells are eligible for suppression. \code{NA} cells
#' in the input pass through unchanged.
#'
#' @param tbl A numeric matrix or 2-D table of counts. Will be coerced to
#'   matrix; row/column names are preserved.
#' @param threshold Minimum count to remain unsuppressed. Default 5.
#' @param return_complementary Logical; if \code{TRUE} (default), apply
#'   complementary suppression so primary-suppressed cells can't be
#'   recovered from marginal sums.
#' @return A list with class \code{"morie_cell_suppress"}:
#' \describe{
#'   \item{\code{suppressed}}{numeric matrix, suppressed cells set to NA.}
#'   \item{\code{primary_mask}}{logical matrix, TRUE for primary suppressions.}
#'   \item{\code{complementary_mask}}{logical matrix, TRUE for complementary
#'     suppressions (all FALSE when \code{return_complementary = FALSE}).}
#'   \item{\code{n_primary}}{integer.}
#'   \item{\code{n_complementary}}{integer.}
#'   \item{\code{threshold}}{the threshold used.}
#' }
#' @export
#' @examples
#' tbl <- matrix(c(120, 3, 47, 88, 2, 99, 14, 51, 60), nrow = 3,
#'               dimnames = list(c("A", "B", "C"), c("X", "Y", "Z")))
#'
#' # Default: primary suppression (cells 1..4) PLUS complementary suppression
#' # so a suppressed cell can't be recovered from row/column marginals.
#' res <- morie_cell_suppress(tbl, threshold = 5)
#' res$suppressed              # NA where suppressed
#' res$n_primary              # cells below threshold
#' res$n_complementary        # extra cells hidden to protect the marginals
#' res$primary_mask
#'
#' # Turn complementary suppression off: only the small cells are hidden.
#' morie_cell_suppress(tbl, threshold = 5,
#'                     return_complementary = FALSE)$suppressed
#'
#' # A higher threshold suppresses more cells.
#' morie_cell_suppress(tbl, threshold = 50)$n_primary
#'
#' # Works on a 2-D table too; NA cells pass through untouched.
#' t2 <- as.table(matrix(c(2, 40, 30, 1), 2,
#'                       dimnames = list(c("a", "b"), c("c", "d"))))
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
  complementary <- matrix(FALSE, nrow = nrow(m), ncol = ncol(m),
                          dimnames = dimnames(m))

  if (return_complementary && any(primary)) {
    # ROW pass: any row with exactly one primary-suppressed cell needs
    # at least one extra suppression so the marginal sum can't recover
    # the suppressed value.
    for (i in seq_len(nrow(m))) {
      row_primary <- primary[i, ]
      if (sum(row_primary) >= 1L) {
        candidates <- !row_primary & !is.na(m[i, ])
        if (any(candidates)) {
          # smallest other cell in the row
          vals <- m[i, ]
          vals[!candidates] <- Inf
          j <- which.min(vals)
          complementary[i, j] <- TRUE
        }
      }
    }
    # COLUMN pass: same reasoning down each column.
    for (j in seq_len(ncol(m))) {
      col_primary <- primary[, j]
      if (sum(col_primary) >= 1L) {
        candidates <- !col_primary & !is.na(m[, j]) & !complementary[, j]
        if (any(candidates)) {
          vals <- m[, j]
          vals[!candidates] <- Inf
          i <- which.min(vals)
          complementary[i, j] <- TRUE
        }
      }
    }
  }

  suppressed <- m
  suppressed[primary | complementary] <- NA_real_

  structure(
    list(
      suppressed         = suppressed,
      primary_mask       = primary,
      complementary_mask = complementary,
      n_primary          = sum(primary),
      n_complementary    = sum(complementary),
      threshold          = threshold
    ),
    class = "morie_cell_suppress"
  )
}
