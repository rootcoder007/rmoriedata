test_that("mdsums paths resolve and are unique", {
  ck <- mdsums()
  skip_if(nrow(ck) == 0L)
  ed <- system.file("extdata", package = "rmoriedata")
  expect_true(all(file.exists(file.path(ed, ck$path))))
  expect_false(anyDuplicated(ck$path) > 0L)
  expect_identical(ck$file, basename(ck$path))
  v <- mdverify()
  expect_true(all(v$path %in% ck$path))
})

test_that("ask rejects NA like it rejects empty and NULL", {
  expect_error(mdask(NA_character_))
  expect_error(mdask(""))
  expect_error(mdask(NULL))
})

test_that("mdsums() and mdverify() list files in the same order in every locale", {
  ed <- local_store_copy()
  for (f in c("Zeta.txt", "_under.txt", "alpha.txt", "Beta.txt", ".hidden")) {
    writeLines("x", file.path(ed, f))
  }
  ref <- NULL
  old <- Sys.getlocale("LC_COLLATE")
  withr::defer(Sys.setlocale("LC_COLLATE", old))
  for (loc in c("C", "en_US.UTF-8", "tr_TR.UTF-8", "et_EE.UTF-8")) {
    if (!suppressWarnings(nzchar(Sys.setlocale("LC_COLLATE", loc)))) next
    s <- mdsums()$path
    v <- mdverify()
    expect_identical(s, sort(s, method = "radix"), info = loc)
    extra <- v$path[!v$listed]
    expect_identical(extra, sort(extra, method = "radix"), info = loc)
    if (is.null(ref)) ref <- list(s, extra) else expect_identical(list(s, extra), ref)
  }
})
