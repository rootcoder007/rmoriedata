test_that("every catalog entry points at a shipped file", {
  cat <- morie_data_catalog()
  ed <- system.file("extdata", package = "rmoriedata")
  expect_true(all(file.exists(file.path(ed, cat$source_path))))
  expect_setequal(unique(cat$kind), c("table", "dictionary"))
  expect_false(anyDuplicated(cat$slug) > 0)
  tb <- cat[cat$kind == "table", ]
  expect_true(all(!is.na(tb$n_rows) & tb$n_rows >= 0))
  expect_true(all(!is.na(tb$n_cols) & tb$n_cols > 0))
})

test_that("the schema covers every table and every table loads to it", {
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
})

test_that("loads are cached and refresh re-reads", {
  d1 <- morie_data_load("arsau_2023_uof_main_records")
  d2 <- morie_data_load("arsau_2023_uof_main_records")
  expect_identical(d1, d2)
  t <- system.time(for (i in 1:50) morie_data_load("arsau_2023_uof_main_records"))
  expect_lt(t[["elapsed"]], 1)
  d3 <- morie_data_load("arsau_2023_uof_main_records", refresh = TRUE)
  expect_identical(d1, d3)
  expect_error(morie_data_load("no_such_table"), "No dataset")
  expect_error(morie_data_load(c("a", "b")), "single dataset slug")
})

test_that("dictionaries are the shipped JSON, parseable, one per catalog row", {
  cat <- morie_data_catalog()
  dn <- cat[cat$kind == "dictionary", ]
  expect_gt(nrow(dn), 0)
  skip_if_not_installed("jsonlite")
  for (s in dn$slug) {
    txt <- morie_data_dictionary(s)
    expect_type(txt, "character")
    expect_length(txt, 1L)
    expect_type(jsonlite::fromJSON(txt, simplifyVector = FALSE), "list")
  }
  expect_message(out <- morie_data_dictionary("no_such_dictionary"),
                 "No dictionary bundled")
  expect_null(out)
})

test_that("no table is shipped twice", {
  ed <- system.file("extdata", package = "rmoriedata")
  expect_false(dir.exists(file.path(ed, "parquet")))
  expect_false(dir.exists(file.path(ed, "samples")))
  files <- list.files(ed, recursive = TRUE)
  tabular <- files[grepl("\\.(csv|csv\\.gz|parquet)$", files)]
  key <- sub("\\.(csv|csv\\.gz|parquet)$", "", tabular)
  expect_false(anyDuplicated(key) > 0,
               info = paste(key[duplicated(key)], collapse = ", "))
})
