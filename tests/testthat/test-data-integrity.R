test_that("the signed manifest covers every shipped file and verifies", {
  v <- mdverify()
  expect_true(isTRUE(attr(v, "signature")))
  # an install from the source directory (not a built tarball) also carries the
  # .Rbuildignore-d legacy sqlite store, which verify rightly reports as unlisted
  v <- v[!grepl("[.]sqlite$", v$path), ]
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
  cat <- mdcat()
  expect_true(all(cat$source_path %in% v$path))
})

test_that("a modified file or manifest is refused", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  old <- options(rmoriedata.store = tmp)
  on.exit({
    options(old)
    rmoriedata:::.rmoriedata_reset_cache()
  })
  rmoriedata:::.rmoriedata_reset_cache()
  expect_true(all(mdverify()$ok))
  # tamper with one table: its load must fail, the others still pass
  tb <- mdcat()
  tb <- tb[tb$kind == "table" & !grepl("gz$", tb$source_path), ]
  f <- file.path(tmp, tb$source_path[1L])
  writeLines(c(readLines(f, warn = FALSE), "tampered,row"), f)
  rmoriedata:::.rmoriedata_reset_cache()
  slug <- tb$slug[1L]
  expect_error(mdload(slug, refresh = TRUE), "does not match")
  expect_false(all(mdverify()$ok))
  # tamper with the manifest itself: the signature no longer verifies
  mf <- file.path(tmp, "_checksums.csv")
  writeLines(sub("^\"?bytes", "bytes", readLines(mf, warn = FALSE))[-2], mf)
  rmoriedata:::.rmoriedata_reset_cache()
  expect_error(mdverify(), "does not verify")
})

test_that("a file added to the store is reported, not ignored", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  old <- options(rmoriedata.store = tmp)
  on.exit({
    options(old)
    rmoriedata:::.rmoriedata_reset_cache()
  })
  rmoriedata:::.rmoriedata_reset_cache()
  writeLines("x,y\n1,2", file.path(tmp, "planted.csv"))
  v <- mdverify()
  expect_true("planted.csv" %in% v$path)
  expect_false(v$listed[v$path == "planted.csv"])
  expect_false(v$ok[v$path == "planted.csv"])
  expect_true(all(v$ok[v$listed]))
  ck <- mdsums()
  expect_true(all(ck$in_manifest[ck$path %in% v$path[v$listed]]))
})

test_that("refresh = TRUE checks a file again: a change mid-session is refused", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  withr::local_options(rmoriedata.store = tmp)
  withr::defer(rmoriedata:::.rmoriedata_reset_cache())
  rmoriedata:::.rmoriedata_reset_cache()
  tb <- mdcat()
  tb <- tb[tb$kind == "table" & !grepl("gz$", tb$source_path), ]
  slug <- tb$slug[1L]
  expect_s3_class(mdload(slug), "data.frame")
  expect_s3_class(mdload(slug, format = "parquet"), "data.frame")
  f <- file.path(tmp, tb$source_path[1L])
  writeLines(c(readLines(f, warn = FALSE), "tampered,row"), f)
  pq <- file.path(tmp, tb$parquet_path[1L])
  b <- readBin(pq, "raw", file.size(pq))
  b[10] <- xor(b[10], as.raw(1))
  writeBin(b, pq)
  # no reset of the session cache here: the file was verified once already
  expect_error(mdload(slug, refresh = TRUE), "does not match")
  expect_error(mdload(slug, refresh = TRUE, format = "parquet"), "does not match")
})

test_that("hidden files in the store are reported, and readers read the verified store", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  withr::local_options(rmoriedata.store = tmp)
  withr::defer(rmoriedata:::.rmoriedata_reset_cache())
  rmoriedata:::.rmoriedata_reset_cache()
  writeLines("x", file.path(tmp, ".planted"))
  v <- mdverify()
  expect_true(".planted" %in% v$path)
  expect_false(v$ok[v$path == ".planted"])
  # mdsums() lists the store named by the option, hidden files included
  ck <- mdsums()
  expect_true(".planted" %in% ck$path)
  expect_false(ck$in_manifest[ck$path == ".planted"])
  # cihitbls() and siuload() read the file they verified: the store's copy
  cihi <- file.path(tmp, "cihi_data_tables.csv")
  full <- utils::read.csv(cihi, stringsAsFactors = FALSE, check.names = FALSE)
  utils::write.csv(full[1:2, ], cihi, row.names = FALSE)
  expect_error(cihitbls(), "does not match")
  siu <- file.path(tmp, "siu_directors_reports.csv.gz")
  con <- gzfile(siu, "w")
  writeLines(c("a,b", "1,2"), con)
  close(con)
  expect_error(siuload(), "does not match")
  testthat::local_mocked_bindings(.rmoriedata_check_file = function(rel) invisible(TRUE))
  expect_identical(nrow(cihitbls()), 2L)
  expect_identical(nrow(siuload()), 1L)
})

test_that("a listed file replaced by a link out of the store is refused", {
  skip_on_os("windows")
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  withr::local_options(rmoriedata.store = tmp)
  withr::defer(rmoriedata:::.rmoriedata_reset_cache())
  rmoriedata:::.rmoriedata_reset_cache()
  tb <- mdcat()
  tb <- tb[tb$kind == "table" & !grepl("gz$", tb$source_path), ]
  f <- file.path(tmp, tb$source_path[1L])
  out <- file.path(tempfile("elsewhere-"))
  file.copy(f, out)
  file.remove(f)
  file.symlink(out, f)
  rmoriedata:::.rmoriedata_reset_cache()
  v <- mdverify()
  expect_false(v$ok[v$path == tb$source_path[1L]])
  rmoriedata:::.rmoriedata_reset_cache()
  expect_error(mdload(tb$slug[1L]), "is a link out of the data store")
})

test_that("another store's files are checked, whatever the first store verified", {
  ed <- system.file("extdata", package = "rmoriedata")
  src <- list.files(ed, full.names = TRUE)
  copy <- function() {
    d <- file.path(tempfile("store-"), "extdata")
    dir.create(d, recursive = TRUE)
    file.copy(src[!grepl("[.]sqlite$", src)], d, recursive = TRUE)
    d
  }
  tampered <- copy()
  changed <- copy()
  withr::defer(rmoriedata:::.rmoriedata_reset_cache())
  rmoriedata:::.rmoriedata_reset_cache()
  slug <- "arsau_2023_uof_main_records"
  rel <- mdcat()$source_path[mdcat()$slug == slug]
  # the installed store: the file verified, its table, catalog and schema cached
  good <- mdload(slug)
  csv <- mdpath(slug, "csv")
  f <- file.path(tampered, rel)
  x <- readLines(f, warn = FALSE)
  x[2] <- sub("^([^,]*),", "\\1,TAMPERED", x[2])
  writeLines(x, f)
  withr::local_options(rmoriedata.store = tampered)
  expect_error(mdload(slug), "does not match the signed manifest")
  expect_error(mdpath(slug, "csv"), "does not match the signed manifest")
  # its untouched Parquet copy is its own file, verified in its own store
  expect_true(startsWith(mdpath(slug), normalizePath(tampered, winslash = "/")))
  # a store whose manifest was changed: not the cached manifest of the other
  mf <- file.path(changed, "_checksums.csv")
  writeLines(readLines(mf, warn = FALSE)[-2], mf)
  options(rmoriedata.store = changed)
  expect_error(mdpath(slug, "csv"), "does not verify")
  # back to the installed store: its own files, verified again
  options(rmoriedata.store = NULL)
  expect_identical(mdload(slug), good)
  expect_identical(mdpath(slug, "csv"), csv)
  options(rmoriedata.store = tampered)
  expect_error(mdload(slug), "does not match the signed manifest")
  # its catalog too, read again from that store
  cf <- file.path(tampered, "_catalog.csv")
  writeLines(c(readLines(cf, warn = FALSE), ""), cf)
  options(rmoriedata.store = NULL)
  expect_identical(mdcat()$slug[mdcat()$slug == slug], slug)
  options(rmoriedata.store = tampered)
  expect_error(mdcat(), "does not match the signed manifest")
})
