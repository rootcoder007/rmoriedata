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
  testthat::local_mocked_bindings(.rmoriedata_bytes = function(rel) {
    .rmd_bytes(file.path(.rmoriedata_extdata(), rel))
  })
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

test_that("a file changed in place is refused at every read, and its cache dropped", {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempfile("store-"), "extdata")
  dir.create(tmp, recursive = TRUE)
  src <- list.files(ed, full.names = TRUE)
  file.copy(src[!grepl("[.]sqlite$", src)], tmp, recursive = TRUE)
  withr::local_options(rmoriedata.store = tmp)
  withr::defer(rmoriedata:::.rmoriedata_reset_cache())
  rmoriedata:::.rmoriedata_reset_cache()
  slug <- "arsau_2023_uof_main_records"
  row <- mdcat()[mdcat()$slug == slug, ]
  p <- mdpath(slug, "csv")
  d <- mdload(slug)
  dp <- mdload(slug, format = "parquet")
  # one digit of the first record made another digit (or byte `i` changed): the
  # same size, and the modification time put back
  edit <- function(f, i = NULL) {
    b <- readBin(f, "raw", file.size(f))
    t <- file.mtime(f)
    if (is.null(i)) {
      nl <- which(b == as.raw(10L))[1L]
      dg <- which(b %in% as.raw(0x30:0x39))
      i <- dg[dg > nl][1L]
    }
    b[i] <- xor(b[i], as.raw(1L))
    writeBin(b, f)
    Sys.setFileTime(f, t)
    invisible(NULL)
  }
  t0 <- as.numeric(file.mtime(p))
  s0 <- file.size(p)
  edit(p)
  expect_identical(file.size(p), s0)
  expect_lt(abs(as.numeric(file.mtime(p)) - t0), 0.01)
  expect_error(mdpath(slug, "csv"), "does not match the signed manifest")
  expect_error(mdpath(slug, "csv"), "does not match the signed manifest")
  # the table loaded before the change is what the file held when it was checked
  expect_identical(mdload(slug), d)
  v <- mdverify()
  expect_identical(v$path[!v$ok], row$source_path)
  # reported: its cached table is dropped, so the next load reads the file and refuses it
  expect_error(mdload(slug), "does not match the signed manifest")
  expect_identical(mdload(slug, format = "parquet"), dp)
  # its Parquet copy changed too: that cached table goes as well
  edit(file.path(tmp, row$parquet_path), 200L)
  expect_identical(mdload(slug, format = "parquet"), dp)
  mdverify()
  expect_error(mdload(slug, format = "parquet"), "does not match the signed manifest")
  # the schema types every CSV table: changed, every table read from a CSV is dropped
  tb <- mdcat()
  other <- tb$slug[tb$kind == "table" & tb$slug != slug &
                     !grepl("gz$", tb$source_path)][1L]
  o <- mdload(other)
  expect_identical(mdload(other), o)
  edit(file.path(tmp, "_schema.csv"))
  expect_identical(mdload(other), o)
  mdverify()
  expect_error(mdload(other), "does not match the signed manifest")
})
