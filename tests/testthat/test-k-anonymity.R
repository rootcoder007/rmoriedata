# SPDX-License-Identifier: AGPL-3.0-or-later

# Synthetic dataset with hand-counted equivalence classes:
#   (25, "F") -> 3 rows
#   (32, "M") -> 2 rows
#   (40, "M") -> 1 row
synth_df <- function() {
  data.frame(
    age = c(25, 25, 25, 32, 32, 40),
    sex = c("F", "F", "F", "M", "M", "M"),
    stringsAsFactors = FALSE
  )
}

test_that("k_anonymity returns the expected class sizes", {
  df <- synth_df()
  result <- kanonvrf(df, c("age", "sex"), k = 2)
  expect_s3_class(result, "morie_k_anon")
  expect_equal(result$n_classes, 3L)
  expect_equal(result$min_class_size, 1L)
  expect_false(result$satisfies)
  expect_equal(result$n_violations, 1L)
  expect_true("age" %in% names(result$violating_classes))
  expect_true("sex" %in% names(result$violating_classes))
  expect_equal(result$violating_classes$.n, 1L)
  expect_equal(result$violating_classes$age, 40)
  expect_equal(result$violating_classes$sex, "M")
})

test_that("k_anonymity with k=1 always satisfies non-empty data", {
  df <- synth_df()
  result <- kanonvrf(df, c("age", "sex"), k = 1)
  expect_true(result$satisfies)
  expect_equal(result$n_violations, 0L)
})

test_that("k_anonymity with k larger than every class fails", {
  df <- synth_df()
  result <- kanonvrf(df, c("age", "sex"), k = 100)
  expect_false(result$satisfies)
  expect_equal(result$n_violations, result$n_classes)
})

test_that("k_anonymity input validation", {
  df <- synth_df()
  expect_error(
    kanonvrf(list(a = 1), "a"),
    "data.frame"
  )
  expect_error(
    kanonvrf(df, character(0)),
    "non-empty character vector"
  )
  expect_error(
    kanonvrf(df, "not_a_column"),
    "Columns not found"
  )
  expect_error(
    kanonvrf(df, "age", k = 0),
    "positive integer"
  )
  expect_error(
    kanonvrf(df, "age", k = 2.5),
    "positive integer"
  )
})

test_that("l_diversity computes correct per-class distinct counts", {
  df <- data.frame(
    age = c(25, 25, 25, 25, 32, 32, 32),
    sex = c("F", "F", "F", "F", "M", "M", "M"),
    dx = c("A", "B", "C", "A", "X", "Y", "Z"),
    stringsAsFactors = FALSE
  )
  # (25,F) -> distinct {A,B,C} = 3
  # (32,M) -> distinct {X,Y,Z} = 3
  result <- ldivvrf(df, c("age", "sex"), "dx", l = 3)
  expect_s3_class(result, "morie_l_div")
  expect_true(result$satisfies)
  expect_equal(result$min_diversity, 3L)
  expect_equal(result$n_violations, 0L)

  # Tightening to l=4 should violate both classes.
  result_strict <- ldivvrf(df, c("age", "sex"), "dx", l = 4)
  expect_false(result_strict$satisfies)
  expect_equal(result_strict$n_violations, 2L)
})

test_that("l_diversity input validation", {
  df <- data.frame(a = 1:3, s = c("x", "y", "z"))
  expect_error(ldivvrf(list(), "a", "s"), "data.frame")
  expect_error(
    ldivvrf(df, character(0), "s"),
    "non-empty character vector"
  )
  expect_error(
    ldivvrf(df, "a", c("s", "extra")),
    "single column name"
  )
  expect_error(
    ldivvrf(df, "missing", "s"),
    "Columns not found"
  )
  expect_error(
    ldivvrf(df, "a", "s", l = 0),
    "positive integer"
  )
})

test_that("cell_suppress suppresses primary cells below threshold", {
  tbl <- matrix(
    c(
      120, 47, 88,
      3, 99, 14,
      51, 60, 2
    ),
    nrow = 3, byrow = TRUE,
    dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
  )
  res <- cellsupp(tbl, threshold = 5, retcomp = FALSE)
  expect_s3_class(res, "cellsupp")
  expect_equal(res$n_primary, 2L)
  expect_equal(res$n_complementary, 0L)
  expect_true(is.na(res$suppressed["B", "X"]))
  expect_true(is.na(res$suppressed["C", "Z"]))
  # Non-suppressed cells preserved.
  expect_equal(res$suppressed["A", "X"], 120)
  expect_equal(res$suppressed["B", "Y"], 99)
})

test_that("complementary suppression leaves no hidden cell recoverable from the totals", {
  # One small cell in row B. The 0.3.5 passes hid one complement in row B and one in
  # column X and stopped: row C then held a lone hidden cell, readable off row C's total.
  tbl <- matrix(
    c(
      120, 47, 88,
      3, 99, 14,
      51, 60, 60
    ),
    nrow = 3, byrow = TRUE,
    dimnames = list(c("A", "B", "C"), c("X", "Y", "Z"))
  )
  res <- cellsupp(tbl, threshold = 5, retcomp = TRUE)
  expect_equal(res$n_primary, 1L)
  expect_true(is.na(res$suppressed["B", "X"]))
  expect_true(res$protected)
  expect_equal(res$n_recoverable, 0L)
  hidden <- is.na(res$suppressed)
  # no row or column holds exactly one hidden cell
  expect_false(any(rowSums(hidden) == 1L))
  expect_false(any(colSums(hidden) == 1L))
  # published cells are untouched
  expect_equal(res$suppressed[!hidden], tbl[!hidden])
  # without complements the lone cell is recoverable, and the result says so
  bare <- cellsupp(tbl, threshold = 5, retcomp = FALSE)
  expect_false(bare$protected)
  expect_true(bare$recoverable_mask["B", "X"])
})

test_that("a primary cell is not recoverable from the margins (review reproducer)", {
  # 0.3.5 published (NA NA 57 / NA 10 10 / 90 5 5): R2C1 = 100 - 20 = 80, then
  # R1C1 = 173 - 90 - 80 = 3, the primary cell, exactly
  tbl <- matrix(c(3, 40, 57, 80, 10, 10, 90, 5, 5), nrow = 3, byrow = TRUE,
                dimnames = list(c("R1", "R2", "R3"), c("C1", "C2", "C3")))
  res <- cellsupp(tbl, threshold = 5)
  expect_true(is.na(res$suppressed["R1", "C1"]))
  expect_true(res$protected)
  hidden <- is.na(res$suppressed)
  expect_false(any(rowSums(hidden) == 1L))
  expect_false(any(colSums(hidden) == 1L))
  # complements are never zero cells
  expect_false(any(tbl[res$complementary_mask] == 0))
})

test_that("k-anonymity counts rows with a missing quasi-identifier (review reproducer)", {
  d <- data.frame(zip = c(NA, NA, NA, "60601", "60601", "60601", "60601", "60601"),
                  sex = c("M", "F", "M", "F", "F", "F", "F", "F"))
  r <- kanonvrf(d, c("zip", "sex"), k = 3)
  expect_false(r$satisfies)
  expect_equal(r$min_class_size, 1L)
  expect_equal(r$n_classes, 3L)
  expect_true(any(is.na(r$violating_classes$zip)))
  # every row is accounted for
  # at k = 1 every class passes, the NA classes included
  expect_true(kanonvrf(d, c("zip", "sex"), k = 1)$satisfies)
})

test_that("l-diversity counts only known sensitive values (review reproducer)", {
  C <- data.frame(
    g = c("a", "a", "a", "b", "b", "b"),
    s = c("HIV", NA, NA, "FLU", "FLU", NA)
  )
  r <- ldivvrf(C, "g", "s", l = 2)
  expect_false(r$satisfies)
  expect_equal(r$min_diversity, 1L)
  # a missing quasi-identifier is its own class here too
  D <- data.frame(g = c("a", "a", NA, NA), s = c("x", "y", "z", "z"))
  r2 <- ldivvrf(D, "g", "s", l = 2)
  expect_equal(r2$n_classes, 2L)
  expect_false(r2$satisfies)
})

test_that("cell_suppress input validation", {
  tbl <- matrix(1:9, nrow = 3)
  expect_error(
    cellsupp(tbl, threshold = 0),
    "positive number"
  )
  expect_error(
    cellsupp(tbl,
      threshold = 5,
      retcomp = NA
    ),
    "TRUE or FALSE"
  )
  char_tbl <- matrix(letters[1:9], nrow = 3)
  expect_error(
    cellsupp(char_tbl, threshold = 5),
    "numeric matrix or table"
  )
})

test_that("ldivvrf counts each class's distinct known values as a per-class scan would", {
  set.seed(11)
  n <- 4000L
  df <- data.frame(a = sample(40L, n, TRUE), b = sample(letters[1:6], n, TRUE),
                   s = sample(c(0.3, 0.1 + 0.2, 1, NA, 7), n, TRUE))
  got <- ldivvrf(df, c("a", "b"), "s", l = 2)
  cls <- rmoriedata:::.morie_qi_classes(df[, c("a", "b")])
  ref <- vapply(seq_len(nrow(cls$keys)), function(g) {
    length(unique(df$s[cls$id == g & !is.na(df$s)]))
  }, integer(1))
  expect_identical(got$min_diversity, min(ref))
  expect_identical(nrow(got$violating_classes), sum(ref < 2L))
  # a class whose values are all missing has diversity 0
  one <- data.frame(a = c(1, 1, 2), s = c(NA, NA, "x"))
  expect_identical(ldivvrf(one, "a", "s", l = 1)$min_diversity, 0L)
  # many classes: one pass
  big <- data.frame(a = seq_len(60000L), s = 1L)
  expect_lt(system.time(ldivvrf(big, "a", "s", l = 1))[["elapsed"]], 20)
})

test_that("cellsupp refuses a table of three or more dimensions", {
  expect_error(cellsupp(array(1:8, c(2, 2, 2))), "must be 2-dimensional")
  expect_error(cellsupp(table(c(1, 2), c(1, 2), c(1, 2))), "must be 2-dimensional")
  expect_error(cellsupp(NULL), "must be 2-dimensional")
  expect_silent(cellsupp(matrix(c(20, 30, 40, 50), 2)))
})

test_that("extreme arguments are refused in the package's own words", {
  df <- data.frame(a = c(1, 1, 2), s = c("x", "y", "z"))
  for (big in list(Inf, 1e10, 2^60)) {
    expect_error(kanonvrf(df, "a", k = big), "`k` must be a single positive integer")
    expect_error(ldivvrf(df, "a", "s", l = big), "`l` must be a single positive integer")
  }
  expect_error(dplapcnt(5, .Machine$double.xmax), "above 2\\^20")
  expect_error(dplapcnt(5, 1e300), "above 2\\^20")
  expect_true(is.numeric(dplapcnt(5, 64)))
  expect_error(mdsha(c("abc", "zzz")), "single string")
  expect_error(mdsha(list(1, 2)), "single string")
  expect_error(mdsha(NA), "single string")
  a <- "caf\u00e9"
  b <- iconv(a, "UTF-8", "latin1")
  expect_identical(mdsha(a), mdsha(b))
  expect_identical(mdsha("abc"), mdsha(charToRaw("abc")))
  for (bad in list(NA, c("a", "b"), data.frame(), 1, "")) {
    expect_error(mddict(bad), "`slug` must be a single name")
  }
})

# The recoverability audit as 0.4.3 shipped it, one qr() per hidden cell: the
# reference the one-factorisation audit must agree with, cell for cell.
old_recoverable <- function(m, hidden) {
  out <- matrix(FALSE, nrow(m), ncol(m), dimnames = dimnames(m))
  idx <- which(hidden, arr.ind = TRUE)
  if (!nrow(idx)) return(out)
  nh <- nrow(idx)
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

cellsupp_same_as_old <- function(n, maxdim, seed) {
  set.seed(seed)
  bad <- character()
  for (i in seq_len(n)) {
    r <- sample(2:maxdim, 1L)
    k <- sample(2:maxdim, 1L)
    p <- runif(1L, 0.03, 0.5)
    m <- matrix(ifelse(runif(r * k) < p, sample(0:4, r * k, TRUE),
                       sample(5:200, r * k, TRUE)), r, k)
    rc <- i %% 4L != 0L
    h <- matrix(runif(r * k) < runif(1L, 0.1, 0.7), r, k)
    new <- cellsupp(m, 5, rc)
    old <- testthat::with_mocked_bindings(cellsupp(m, 5, rc),
                                          .morie_recoverable = old_recoverable)
    if (!identical(new, old) ||
        !identical(.morie_recoverable(m, h), old_recoverable(m, h))) {
      bad <- c(bad, sprintf("table %d (%dx%d)", i, r, k))
    }
  }
  bad
}

test_that("the one-factorisation audit suppresses what the per-cell audit did", {
  expect_identical(cellsupp_same_as_old(40L, 12L, 7L), character())
})

test_that("the audit agrees with the per-cell audit on 200 tables up to 30x30", {
  skip_on_cran()
  expect_identical(cellsupp_same_as_old(200L, 30L, 20261113L), character())
})

test_that("a 60x60 table with 1,400 small cells is suppressed in seconds", {
  skip_on_cran()
  set.seed(3)
  m <- matrix(sample(c(1:4, 5:200), 3600, TRUE, prob = c(rep(3, 4), rep(0.1, 196))), 60)
  # one qr() per hidden cell ran for over 17 minutes here
  t <- system.time(res <- cellsupp(m))[["elapsed"]]
  expect_lt(t, 30)
  expect_true(res$protected)
})

test_that("cellsupp publishes zero cells and refuses negative counts", {
  tbl <- matrix(c(0, 40, 57, 80, 10, 10, 90, 5, 5), nrow = 3, byrow = TRUE)
  res <- cellsupp(tbl, threshold = 5)
  expect_identical(res$n_primary, 0L)
  expect_identical(res$suppressed[1L, 1L], 0)
  expect_error(cellsupp(matrix(c(-1, 40, 57, 80), 2)),
               "`tbl` must hold counts: it has a negative cell.", fixed = TRUE)
  expect_error(cellsupp(NULL), "`tbl` must be 2-dimensional.", fixed = TRUE)
})

test_that("numeric quasi-identifiers are keyed exactly, not to 15 digits", {
  r <- kanonvrf(data.frame(x = c(0.1 + 0.2, 0.3, 0.3, 0.3, 0.3)), "x", k = 2)
  expect_false(r$satisfies)
  expect_identical(r$min_class_size, 1L)
  expect_identical(r$n_classes, 2L)
  # -0 and 0 are one value; NaN is missing, with NA
  z <- kanonvrf(data.frame(x = c(-0, 0, NaN, NA)), "x", k = 2)
  expect_identical(z$n_classes, 2L)
  expect_true(z$satisfies)
  l <- ldivvrf(data.frame(q = c(1 / 3, 1 - 2 / 3, 1 / 3), s = c("a", "b", "c")),
               "q", "s", l = 2)
  expect_identical(l$n_classes, 2L)
  expect_false(l$satisfies)
  # brute force: a row's class is every row equal to it in every column, NA with NA
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  set.seed(7)
  for (rep in 1:30) {
    n <- sample(5:40, 1)
    d <- data.frame(
      dbl = sample(c(0.3, 0.1 + 0.2, 1 / 3, 1 - 2 / 3, 2 / 3, 1e-17, 0, -0, NA, NaN),
                   n, TRUE),
      int = sample(c(1:3, NA), n, TRUE),
      chr = sample(c("a", "b", NA), n, TRUE),
      fac = factor(sample(c("u", "v"), n, TRUE)),
      lgl = sample(c(TRUE, FALSE, NA), n, TRUE),
      dte = as.Date("2020-01-01") + sample(0:2, n, TRUE),
      stringsAsFactors = FALSE
    )
    for (q in list("dbl", c("dbl", "int"), c("chr", "fac", "lgl"), c("dbl", "dte"),
                   names(d))) {
      sz <- vapply(seq_len(n), function(i) {
        sum(Reduce(`&`, lapply(q, function(cn) same(d[[cn]][i], d[[cn]]))))
      }, integer(1))
      ncls <- sum(1 / sz)
      got <- kanonvrf(d, q, k = 2)
      expect_identical(got$min_class_size, min(sz), info = paste(q, collapse = ","))
      expect_equal(got$n_classes, ncls, info = paste(q, collapse = ","))
    }
  }
})

test_that("cellsupp treats an NA cell as hidden and refuses non-counts in words", {
  r <- cellsupp(matrix(c(3, NA, 10, 10), 2), 5)
  expect_true(r$protected)
  expect_identical(r$n_recoverable, 0L)
  expect_identical(r$n_primary, 1L)
  # the unpublished cell is neither a primary nor a complement
  expect_false(r$complementary_mask[2, 1])
  bare <- cellsupp(matrix(c(3, NA, 10, 10), 2), 5, retcomp = FALSE)
  expect_false(bare$protected)
  # an NA cell alone in its row and column is hidden but recoverable from the totals
  one <- cellsupp(matrix(c(20, NA, 30, 40), 2), 5, retcomp = FALSE)
  expect_false(one$protected)
  expect_true(one$recoverable_mask[2, 1])
  expect_true(cellsupp(matrix(c(20, NA, 30, 40), 2), 5)$protected)
  expect_error(cellsupp(matrix(c(Inf, 1, 2, 3), 2)), "it has an infinite cell")
  expect_error(cellsupp(matrix(c(-Inf, 1, 2, 3), 2)), "negative cell")
  expect_error(cellsupp(matrix(c(1.5, 1, 2, 3), 2)), "not a whole number")
  msg <- "`tbl` must be a numeric matrix or table."
  expect_error(cellsupp(function() 1), msg, fixed = TRUE)
  expect_error(cellsupp(new.env()), msg, fixed = TRUE)
  expect_error(cellsupp(quote(x)), msg, fixed = TRUE)
})

test_that("classed and complex numbers are keyed exactly, odd columns refused by name", {
  t0 <- c(1e9, 1e9 + 1e-7)
  vals <- list(
    difftime = as.difftime(c(0.1 + 0.2, 0.3), units = "secs"),
    AsIs = I(c(0.1 + 0.2, 0.3)),
    POSIXct = as.POSIXct(t0, origin = "1970-01-01", tz = "UTC"),
    POSIXlt = as.POSIXlt(as.POSIXct(t0, origin = "1970-01-01", tz = "UTC")),
    Date = structure(c(19000, 19000.5), class = "Date"),
    complex = complex(real = c(0.1 + 0.2, 0.3)),
    imaginary = complex(real = 1, imaginary = c(0.1 + 0.2, 0.3))
  )
  for (nm in names(vals)) {
    d <- data.frame(x = 1:2, g = "a")
    d$q <- vals[[nm]]
    r <- kanonvrf(d, "q", k = 2)
    expect_identical(r$n_classes, 2L, info = nm)
    expect_false(r$satisfies, info = nm)
    expect_identical(kanonvrf(d, c("g", "q"), k = 2)$n_classes, 2L, info = nm)
    # as the sensitive attribute: two values, diversity 2
    expect_identical(ldivvrf(d, "g", "q", l = 2)$min_diversity, 2L, info = nm)
  }
  d <- data.frame(x = 1:2)
  d$q <- as.POSIXct(c(1e9, 1e9), origin = "1970-01-01", tz = "UTC")
  expect_true(kanonvrf(d, "q", k = 2)$satisfies)
  d$q <- complex(real = c(0, -0), imaginary = c(-0, 0))
  expect_true(kanonvrf(d, "q", k = 2)$satisfies)
  d$m <- matrix(1:4, 2)
  expect_error(kanonvrf(d, "m", k = 1), "column `m` is a matrix column", fixed = TRUE)
  d$l <- list(1, 2)
  expect_error(kanonvrf(d, "l", k = 1), "column `l` is a list column", fixed = TRUE)
  d$b <- structure(c(1, 2), class = "integer64")
  expect_error(kanonvrf(d, "b", k = 1), "column `b` is a bit64 integer64", fixed = TRUE)
  expect_error(ldivvrf(d, "x", "b", l = 1), "column `b` is a bit64 integer64",
               fixed = TRUE)
})

test_that("class keys cannot collide: separators in strings, NA against \"NA\"", {
  d <- data.frame(a = c("p", "p\003\002q"), b = c("q\003\002r", "r"))
  r <- kanonvrf(d, c("a", "b"), k = 2)
  expect_identical(r$n_classes, 2L)
  expect_false(r$satisfies)
  d <- data.frame(a = c("x\001", "x"), b = c("y", "\001y"))
  expect_identical(kanonvrf(d, c("a", "b"), k = 1)$n_classes, 2L)
  f <- factor(c(NA, "NA"), exclude = NULL)
  expect_identical(kanonvrf(data.frame(f = f), "f", k = 1)$n_classes, 2L)
  expect_identical(kanonvrf(data.frame(s = c(NA, "NA")), "s", k = 1)$n_classes, 2L)
  # a level that is NA is missing, with an NA code; "NA" is a value
  g <- structure(c(1L, NA, 2L, 3L), levels = c(NA, "NA", "x"), class = "factor")
  r <- kanonvrf(data.frame(g = g), "g", k = 1)
  expect_identical(r$n_classes, 3L)
  expect_identical(sort(r$violating_classes$.n), integer(0))
  expect_identical(kanonvrf(data.frame(g = g), "g", k = 2)$n_violations, 2L)
  # as a sensitive value the NA level is withheld, not a second value
  l <- ldivvrf(data.frame(q = "a", s = f), "q", "s", l = 2)
  expect_identical(l$min_diversity, 1L)
  # brute force over strings of separators and "NA"
  set.seed(11)
  pool <- c("", "\001", "\002", "\003", "a\003", "\003a", "NA", NA, "\002NA", "\001NA")
  same <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  for (rep in 1:20) {
    n <- sample(4:30, 1)
    d <- data.frame(a = sample(pool, n, TRUE), b = sample(pool, n, TRUE),
                    stringsAsFactors = FALSE)
    sz <- vapply(seq_len(n), function(i) {
      sum(same(d$a[i], d$a) & same(d$b[i], d$b))
    }, integer(1))
    got <- kanonvrf(d, c("a", "b"), k = 2)
    expect_identical(got$min_class_size, min(sz))
    expect_equal(got$n_classes, sum(1 / sz))
  }
})
