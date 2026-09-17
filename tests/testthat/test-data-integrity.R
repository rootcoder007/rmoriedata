test_that("the signed manifest covers every shipped file and verifies", {
  v <- morie_data_verify()
  expect_true(isTRUE(attr(v, "signature")))
  expect_true(all(v$ok))
  ed <- system.file("extdata", package = "rmoriedata")
  shipped <- list.files(ed, recursive = TRUE)
  shipped <- setdiff(shipped, c("_checksums.csv", "_checksums.sig",
                                "_signing_key.json"))
  shipped <- shipped[!startsWith(basename(shipped), ".")]
  # an install from the source directory (not a built tarball) also carries
  # the .Rbuildignore-d legacy sqlite store; it never ships
  shipped <- shipped[!grepl("[.]sqlite$", shipped)]
  expect_setequal(v$path, shipped)
  cat <- morie_data_catalog()
  expect_true(all(cat$source_path %in% v$path))
})

test_that("a modified file or manifest is refused", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  file.copy(list.files(ed, full.names = TRUE), tmp, recursive = TRUE)
  old <- options(rmoriedata.store = tmp)
  on.exit({
    options(old)
    rmoriedata:::.rmoriedata_reset_cache()
  })
  rmoriedata:::.rmoriedata_reset_cache()
  expect_true(all(morie_data_verify()$ok))
  # tamper with one table: its load must fail, the others still pass
  tb <- morie_data_catalog()
  tb <- tb[tb$kind == "table" & !grepl("gz$", tb$source_path), ]
  f <- file.path(tmp, tb$source_path[1L])
  writeLines(c(readLines(f, warn = FALSE), "tampered,row"), f)
  rmoriedata:::.rmoriedata_reset_cache()
  slug <- tb$slug[1L]
  expect_error(morie_data_load(slug, refresh = TRUE), "does not match")
  expect_false(all(morie_data_verify()$ok))
  # tamper with the manifest itself: the signature no longer verifies
  mf <- file.path(tmp, "_checksums.csv")
  writeLines(sub("^\"?bytes", "bytes", readLines(mf, warn = FALSE))[-2], mf)
  rmoriedata:::.rmoriedata_reset_cache()
  expect_error(morie_data_verify(), "does not verify")
})
