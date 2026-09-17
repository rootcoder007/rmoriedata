# Extracted from test-data-store.R:20

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "rmoriedata", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
cat <- morie_data_catalog()
tb <- cat[cat$kind == "table", ]
s <- rmoriedata:::.rmoriedata_schema()
expect_setequal(unique(s$slug), tb$slug)
expect_true(all(s$class %in% c("character", "integer", "numeric",
                                 "logical", "Date")))
for (i in seq_len(nrow(tb))) {
    d <- morie_data_load(tb$slug[i], refresh = TRUE)
    ss <- s[s$slug == tb$slug[i], ]
    ss <- ss[order(ss$position), ]
    expect_identical(names(d), ss$name, info = tb$slug[i])
    expect_identical(unname(vapply(d, function(z) class(z)[1L], "")),
                     ss$class, info = tb$slug[i])
    expect_equal(nrow(d), tb$n_rows[i], info = tb$slug[i])
    expect_equal(ncol(d), tb$n_cols[i], info = tb$slug[i])
  }
