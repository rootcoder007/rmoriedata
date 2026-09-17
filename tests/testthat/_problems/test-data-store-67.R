# Extracted from test-data-store.R:67

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "rmoriedata", path = "..")
attach(test_env, warn.conflicts = FALSE)

# test -------------------------------------------------------------------------
ed <- system.file("extdata", package = "rmoriedata")
expect_false(dir.exists(file.path(ed, "parquet")))
expect_false(dir.exists(file.path(ed, "samples")))
files <- list.files(ed, recursive = TRUE)
base <- sub("\\.(csv|csv\\.gz|parquet)$", "", basename(files))
base <- base[grepl("\\.(csv|csv\\.gz|parquet)$", basename(files))]
expect_false(anyDuplicated(base) > 0,
               info = paste(base[duplicated(base)], collapse = ", "))
