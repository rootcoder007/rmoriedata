# SPDX-License-Identifier: AGPL-3.0-or-later
# A file that is checked against a digest is read once: the bytes that were hashed
# are the bytes that are parsed, so a file replaced between the two is never
# returned unchecked; and what is not a regular file is reported or refused, never
# waited on. Keys and column names are held to what they can be.

# Runs `run()` with the file at `f` replaced by `with` right after the reader has
# taken its bytes: the race of a second process, made to happen every time.
# Returns what run() gave and how often `f` was read.
swap_after_read <- function(f, with, run) {
  hits <- 0L
  value <- testthat::with_mocked_bindings(run(), .rmd_bytes = function(p, max = Inf) {
    b <- .Call(C_rmd_readfile, p, as.numeric(max))
    if (identical(normalizePath(p, mustWork = FALSE), normalizePath(f))) {
      hits <<- hits + 1L
      writeBin(with, f)
    }
    b
  })
  list(value = value, hits = hits)
}

test_that("a store file replaced after its check is never read", {
  ed <- local_store_copy()
  cat0 <- mdcat()
  tb <- cat0[cat0$kind == "table", ][1L, ]
  junk <- charToRaw("a,b\n1,2\n")
  cases <- list(
    list(rel = tb$parquet_path, run = function() mdload(tb$slug, TRUE, "parquet")),
    list(rel = tb$source_path, run = function() mdload(tb$slug, TRUE, "csv")),
    list(rel = cat0$source_path[cat0$kind == "dictionary"][1L],
         run = function() mddict(cat0$slug[cat0$kind == "dictionary"][1L])),
    list(rel = "siu_directors_reports.csv.gz", run = function() siuload()),
    list(rel = "cihi_data_tables.csv", run = function() cihitbls()))
  for (k in cases) {
    f <- file.path(ed, k$rel)
    orig <- readBin(f, "raw", file.size(f))
    want <- k$run()
    got <- swap_after_read(f, junk, k$run)
    expect_identical(got$value, want, info = k$rel)
    expect_identical(got$hits, 1L, info = k$rel)
    # the file now differs, and the next read refuses it
    expect_error(k$run(), "does not match the signed manifest", info = k$rel)
    writeBin(orig, f)
  }
})

test_that("the full Chicago cache and a hosted table are read once", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "arrests_full.parquet")
  d <- data.frame(a = 1:3, b = c("x", "y", "z"), stringsAsFactors = FALSE)
  .rmd_cache_write(d, path)
  junk <- charToRaw("PAR1 not parquet PAR1")
  # the cache is replaced right after it is opened and hashed: renamed over (another
  # session writing it), the open file is still the one hashed; rewritten in place,
  # every range the reader takes is checked against what was hashed, and it stops
  swap <- function(how) {
    real <- .rmd_vopen
    testthat::with_mocked_bindings(.rmd_cache_read(path), .rmd_vopen = function(...) {
      v <- real(...)
      if (how == "rename") {
        tmp <- tempfile(tmpdir = dir)
        writeBin(junk, tmp)
        # refused on Windows while the file is open: the reader keeps the one hashed
        suppressWarnings(file.rename(tmp, path))
      } else {
        writeBin(junk, path)
      }
      v
    })
  }
  orig <- readBin(path, "raw", file.size(path))
  expect_identical(swap("rename"), d)
  writeBin(orig, path)
  expect_error(swap("in place"), "the file was changed while it was read")
  # the replaced file no longer matches its sidecar: its bytes are proven bad
  expect_error(.rmd_cache_read(path), class = "rmd_damage")
})

test_that("mdverify() reports whatever is at a listed path and drops its caches", {
  skip_on_os("windows")
  ed <- local_store_copy()
  cat0 <- mdcat()
  tb <- cat0[cat0$kind == "table", ]
  kinds <- c("dir", "fifo", "loop", "unreadable")
  for (i in seq_along(kinds)) {
    slug <- tb$slug[i]
    rel <- tb$parquet_path[i]
    f <- file.path(ed, rel)
    mdload(slug, format = "parquet")
    unlink(f)
    switch(kinds[i],
      dir = dir.create(f),
      fifo = if (system2("mkfifo", shQuote(f)) != 0L) skip("no mkfifo"),
      loop = file.symlink(basename(f), f),
      unreadable = {
        writeBin(as.raw(1:9), f)
        Sys.chmod(f, "000")
      })
    t0 <- Sys.time()
    v <- mdverify()
    expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 60)
    expect_false(v$ok[v$path == rel], info = kinds[i])
    expect_true(sum(!v$ok[v$listed]) == 1L, info = kinds[i])
    # the cached table is dropped: the next load reads the path and refuses it
    expect_error(mdload(slug, format = "parquet"), "does not match|missing",
                 info = kinds[i])
    expect_error(mdpath(slug), "does not match|missing", info = kinds[i])
    Sys.chmod(f, "644")
    unlink(f, recursive = TRUE)
    file.copy(file.path(system.file("extdata", package = "rmoriedata"), rel), f)
  }
  expect_true(all(mdverify()$ok))
})

test_that("the file reader takes regular files only and says why", {
  skip_on_os("windows")
  d <- withr::local_tempdir()
  expect_match(.rmd_bytes(d), "not a regular file")
  expect_match(.rmd_bytes(file.path(d, "none")), "cannot be read")
  f <- file.path(d, "x")
  writeBin(as.raw(1:10), f)
  expect_identical(.rmd_bytes(f), as.raw(1:10))
  expect_match(.rmd_bytes(f, 9), "larger")
  expect_identical(.rmd_bytes(f, 10), as.raw(1:10))
  fifo <- file.path(d, "p")
  skip_if(system2("mkfifo", shQuote(fifo)) != 0L, "no mkfifo")
  expect_match(.rmd_bytes(fifo), "not a regular file")
  expect_identical(.rmd_digest(fifo), NA_character_)
  expect_error(morie_read_parquet(fifo), "^parquet: .* not a regular file")
  expect_identical(.rmd_digest(f), mdsha(as.raw(1:10)))
})

test_that("a hosted key is held to the manifest's form before anything is asked", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  asked <- character()
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    asked <<- c(asked, path)
    writeLines('{"datasets":[{"key":"db/t","access":"closed"},{"key":"db/../x"}]}', dest)
    invisible(dest)
  })
  bad <- c("db/./t", "db/x/../t", "./db/t", "db/t/.", "db/..", "../db/t", "db//t",
           "db/t/", "/db/t", "db\\t", "db/%2e%2e/t", "db/t\n", "db/ t", "db", "",
           "db/.t", "db/t?x=1", "db/t#x", NA_character_)
  for (k in bad) {
    expect_error(hostload(k), "key must be db/table", info = k)
  }
  expect_identical(asked, character())
  expect_false(.rmd_key_ok(c("a/b", "c/d")))
  expect_true(.rmd_key_ok("a2aj_onca/onca_decisions_meta"))
  expect_true(.rmd_key_ok("statcan_indigenous/tbl_41100401.v2-x"))
  # the closed table is refused by its key; an entry whose key is not one is not served
  expect_error(hostload("db/t"), "not served")
  expect_message(cat0 <- hostcat(), "2 tables are not served")
  expect_identical(nrow(cat0), 0L)
})

test_that("column names may be empty, and a name of two columns is refused in words", {
  d <- data.frame(a = c(1, 1, 2), b = c("x", "y", "y"), c = 1:3)
  names(d) <- c("", "s", "c")
  r <- kanonvrf(d, "", k = 2)
  expect_identical(r$n_classes, 2L)
  expect_identical(names(r$violating_classes), c("", ".n"))
  r <- ldivvrf(d, "", "s", l = 2)
  expect_identical(r$min_diversity, 1L)
  names(d) <- c("s", "", "")
  expect_error(kanonvrf(d, ""), "more than one column named \"\"")
  expect_error(ldivvrf(d, "s", ""), "more than one column named \"\"")
  expect_identical(kanonvrf(d, "s", k = 2)$n_classes, 2L)
  expect_error(kanonvrf(d, NA_character_), "holds NA")
  expect_error(kanonvrf(d, c("s", "zz")), "Columns not found in `data`: zz")
  names(d) <- c("s", ".n", "x")
  expect_error(kanonvrf(d, ".n"), "column named \".n\" cannot be checked")
  expect_identical(ldivvrf(d, "s", ".n", l = 1)$satisfies, TRUE)
})

test_that("a hosted table replaced after its check is never read", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  cache <- withr::local_tempdir()
  withr::local_options(rmoriedata.cache_dir = cache)
  served <- withr::local_tempfile(fileext = ".csv.gz")
  con <- gzfile(served, "w")
  writeLines(c("id,v", "1,a", "2,b"), con)
  close(con)
  manifest <- paste0('{"datasets":[{"key":"db/t","sha256_gz":"', .rmd_digest(served),
                     '"}]}')
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    if (path == "/manifest.json") writeLines(manifest, dest)
    else file.copy(served, dest, overwrite = TRUE)
    invisible(dest)
  })
  want <- hostload("db/t")
  dest <- file.path(cache, "hosted", "tables", "db_-t.csv.gz")
  bad <- withr::local_tempfile(fileext = ".csv.gz")
  con <- gzfile(bad, "w")
  writeLines(c("id,v", "1,EVIL"), con)
  close(con)
  got <- swap_after_read(dest, readBin(bad, "raw", file.size(bad)),
                         function() hostload("db/t"))
  expect_identical(got$value, want)
  expect_identical(got$hits, 1L)
  expect_identical(nrow(want), 2L)
})
