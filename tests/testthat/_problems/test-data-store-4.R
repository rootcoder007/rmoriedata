# Extracted from test-data-store.R:4

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "rmoriedata", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
cat <- morie_data_catalog()
ed <- system.file("extdata", package = "rmoriedata")
expect_true(all(file.exists(file.path(ed, cat$source_path))))
