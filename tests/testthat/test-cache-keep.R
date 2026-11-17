# SPDX-License-Identifier: AGPL-3.0-or-later
# A cached or downloaded copy is deleted only when its bytes are proven bad: they do
# not match their digest, or the file itself is damaged. Memory that runs short, a
# read that fails, a session option or a parse error leave it in place, and the call
# says what happened. The full Chicago cache is read a column chunk at a time through
# one open of the file, never held whole.

# A full Chicago cache of `n` rows of six double columns, uncompressed, with its
# sidecar, in `d`.
keep_cache <- function(d, n) {
  path <- file.path(d, "arrests_full.parquet")
  x <- stats::setNames(lapply(1:6, function(i) seq_len(n) / (i + 0.5)), paste0("v", 1:6))
  df <- structure(x, class = "data.frame", row.names = .set_row_names(n))
  morie_write_parquet(df, path, compression = NULL)
  writeLines(.rmd_digest(path), paste0(path, ".sha256"))
  list(path = path, df = df)
}

# chiload(full = TRUE) of `d`'s cache, offline: no row count and no export to fetch.
keep_load <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    .rmd_full_count_or_na = function(type) NA_real_,
    .rmd_full_url = function(type, n) "file:///nonexistent/rmoriedata-export.csv",
    .package = "rmoriedata", .env = env
  )
}

test_that("the full cache is read without holding the file whole", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 3e5)
  size <- file.size(fx$path) / 2^20
  before <- gc(reset = TRUE)
  before <- sum(before[, which(colnames(before) == "max used") + 1L])
  # a collection every 50 allocations, so that "max used" is near what is live and not
  # garbage waiting for the collector (a fixed step: the count is the same every run)
  gctorture2(50)
  got <- tryCatch(.rmd_cache_read(fx$path), finally = gctorture2(0))
  g <- gc()
  peak <- sum(g[, which(colnames(g) == "max used") + 1L]) - before
  expect_identical(got, fx$df)
  # measured (14 MB file): 3.3 times its size, the frame returned being once its size;
  # with the file held whole as well, 4.8 times
  expect_lt(peak, 4 * size)
})

test_that("a cache that cannot be read for want of memory is kept, and said so", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  keep_load()
  testthat::local_mocked_bindings(morie_read_parquet = function(path, columns = NULL) {
    stop("parquet: cannot allocate vector of size 1.5 Gb", call. = FALSE)
  })
  expect_error(.rmd_fetch_full("arrests", NULL),
               "arrests_full.parquet could not be read .*cannot allocate .*left in place")
  expect_true(file.exists(fx$path))
  expect_true(file.exists(paste0(fx$path, ".sha256")))
})

test_that("a read refused by an option, or a file not opened, keeps the cache", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  keep_load()
  withr::with_options(list(rmoriedata.parquet_max_rows = 10), {
    expect_error(.rmd_fetch_full("arrests", NULL),
                 "footer claims 100 rows.*left in place")
  })
  testthat::with_mocked_bindings(
    expect_error(.rmd_fetch_full("arrests", NULL),
                 "cannot be read \\(Input/output error\\).*left in place"),
    .rmd_vopen = function(f, verify = TRUE, fail = TRUE) {
      stop(basename(f), " cannot be read (Input/output error)", call. = FALSE)
    })
  expect_true(file.exists(fx$path))
  expect_identical(.rmd_fetch_full("arrests", NULL)$v1, fx$df$v1)
})

test_that("a cache whose bytes fail its sidecar, or are not Parquet, is deleted", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  side <- paste0(fx$path, ".sha256")
  writeLines(strrep("0", 64), side)
  expect_error(.rmd_cache_read(fx$path), class = "rmd_damage")
  expect_null(.rmd_cache_use(fx$path))
  expect_false(file.exists(fx$path) || file.exists(side))
  # matches its sidecar, but is no Parquet file
  writeLines("not parquet", fx$path)
  writeLines(.rmd_digest(fx$path), side)
  expect_error(.rmd_cache_read(fx$path), "is not a Parquet file", class = "rmd_damage")
  expect_null(.rmd_cache_use(fx$path))
  expect_false(file.exists(fx$path))
})

test_that("a cache without a usable sidecar is not read and not deleted", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  side <- paste0(fx$path, ".sha256")
  unlink(side)
  expect_null(.rmd_cache_use(fx$path))
  writeLines("not a digest", side)
  expect_null(.rmd_cache_use(fx$path))
  expect_true(file.exists(fx$path))
})

test_that("a damaged cache is deleted only while it still holds the bytes found bad", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  good <- readBin(fx$path, "raw", file.size(fx$path))
  writeLines(strrep("0", 64), paste0(fx$path, ".sha256"))
  # another session writes a new cache between the check and the deletion
  real <- .rmd_drop
  testthat::local_mocked_bindings(.rmd_drop = function(f, sha, also = character()) {
    writeBin(c(good, as.raw(0L)), f)
    real(f, sha, also)
  })
  expect_null(.rmd_cache_use(fx$path))
  expect_true(file.exists(fx$path))
})

test_that("a sidecar replaced while the cache is checked is read again", {
  d <- local_chicago_cache()
  fx <- keep_cache(d, 100)
  side <- paste0(fx$path, ".sha256")
  right <- readLines(side)
  writeLines(strrep("0", 64), side)
  real <- .rmd_vopen
  # the writer's second rename lands just after the file was hashed
  testthat::local_mocked_bindings(.rmd_vopen = function(...) {
    v <- real(...)
    writeLines(right, side)
    v
  })
  expect_identical(.rmd_cache_read(fx$path), fx$df)
})

test_that("a file opened once is read in ranges checked against what was hashed", {
  set.seed(7)
  b <- as.raw(sample(0:255, 3e5, TRUE))
  f <- withr::local_tempfile()
  writeBin(b, f)
  v <- .rmd_vopen(f)
  expect_identical(v$sha256, .Call(C_morie_core_sha256, b))
  for (i in 1:200) {
    s <- sample(0:(3e5 + 10), 1L)
    n <- sample(0:150000, 1L)
    want <- if (n == 0 || s >= 3e5) raw(0) else b[seq.int(s + 1, min(3e5, s + n))]
    expect_identical(.Call(C_rmd_vread, v$handle, s, n), want)
  }
  # renamed over: the open file is still the one that was hashed
  # (Windows refuses to rename over a file that is open: the file stays as it was)
  tmp <- withr::local_tempfile()
  writeBin(rev(b), tmp)
  over <- suppressWarnings(file.rename(tmp, f))
  expect_identical(over, .Platform$OS.type != "windows")
  now <- if (over) rev(b) else b
  expect_identical(.Call(C_rmd_vread, v$handle, 7e4, 10), b[70001:70010])
  .rmd_vclose(v)
  expect_error(.Call(C_rmd_vread, v$handle, 0, 1), "no longer open")
  # rewritten in place after it was hashed: refused, block by block
  v <- .rmd_vopen(f)
  con <- file(f, "r+b")
  seek(con, 70000, rw = "write")
  writeBin(as.raw(1:3), con)
  close(con)
  expect_identical(.Call(C_rmd_vread, v$handle, 0, 100), now[1:100])
  expect_error(.Call(C_rmd_vread, v$handle, 66000, 10), "changed while it was read")
  .rmd_vclose(v)
  # an empty file, and what is not a regular file
  e <- withr::local_tempfile()
  file.create(e)
  v <- .rmd_vopen(e)
  expect_identical(v$sha256, .Call(C_morie_core_sha256, raw(0)))
  expect_identical(.Call(C_rmd_vread, v$handle, 0, 10), raw(0))
  .rmd_vclose(v)
  expect_identical(.rmd_vopen(tempdir(), fail = FALSE), "is not a regular file")
  expect_error(.rmd_vopen(file.path(tempdir(), "no-such-file")),
               "no-such-file cannot be read")
})

test_that("the package's SHA-256 agrees with the shared core's", {
  set.seed(3)
  for (n in c(0:130, 1000, 65535:65537, 2e5)) {
    b <- as.raw(sample(0:255, n, TRUE))
    expect_identical(.Call(C_rmd_sha256, b), .Call(C_morie_core_sha256, b), info = n)
  }
  expect_identical(.Call(C_rmd_sha256, charToRaw("abc")),
                   "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
})

test_that("reading a Parquet file by its path leaves no descriptor open", {
  skip_if_not(dir.exists("/proc/self/fd"))
  f <- withr::local_tempfile(fileext = ".parquet")
  morie_write_parquet(data.frame(a = 1:3), f)
  n0 <- length(list.files("/proc/self/fd"))
  for (i in 1:50) morie_read_parquet(f)
  for (i in 1:50) try(morie_read_parquet(f, columns = "nope"), silent = TRUE)
  expect_identical(length(list.files("/proc/self/fd")), n0)
})

# ---- hosted tables -------------------------------------------------------------

keep_host <- function(served, digest = TRUE, env = parent.frame()) {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test", .local_envir = env)
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir(.local_envir = env),
                       .local_envir = env)
  sha <- if (digest) sprintf(',"sha256_gz":"%s"', .Call(C_morie_core_sha256, served))
  man <- sprintf('{"datasets":[{"key":"db/t"%s}]}', if (digest) sha else "")
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    if (path == "/manifest.json") writeLines(man, dest) else writeBin(served, dest)
    invisible(dest)
  }, .package = "rmoriedata", .env = env)
  .rmd_host_file("db/t")
}

keep_gz <- function(lines) {
  .Call(C_rmd_gzip_compress, charToRaw(paste0(lines, "\n", collapse = "")))
}

test_that("a hosted table that cannot be read for a reason not in its bytes is kept", {
  dest <- keep_host(keep_gz(c("a,b", "1,2")))
  expect_identical(hostload("db/t")$a, 1L)
  # a warning made an error by the session, memory, a read that failed: the copy stays
  testthat::with_mocked_bindings(
    expect_error(hostload("db/t"),
                 "could not be read \\(.*boom\\); the copy was left in place"),
    .rmd_read_hosted = function(b) {
      withr::local_options(warn = 2)
      warning("boom", call. = FALSE)
    })
  testthat::with_mocked_bindings(
    expect_error(hostload("db/t"), "cannot allocate vector.*left in place"),
    .rmd_read_hosted = function(b) stop("cannot allocate vector of size 2.0 Gb"))
  testthat::with_mocked_bindings(
    expect_error(hostload("db/t"),
                 "cannot be read \\(Input/output error\\); it was left"),
    .rmd_bytes = function(f, max = Inf) {
      if (grepl("db_-t", f)) return("cannot be read (Input/output error)")
      .Call(C_rmd_readfile, f, as.numeric(max))
    })
  expect_true(file.exists(dest))
  expect_identical(hostload("db/t")$b, 2L)
})

test_that("hosted tables load under check.bounds and warn = 2, and are kept", {
  dest <- keep_host(c(keep_gz(c("a,b", "1,2")), keep_gz("3,4")))
  # set around the package's calls alone: withr's own code warns under check.bounds
  old <- options(check.bounds = TRUE, warn = 2)
  got <- tryCatch(list(hostload("db/t"), hostload("db/t")), finally = options(old))
  expect_identical(got[[1L]]$a, c(1L, 3L))
  expect_identical(got[[2L]]$b, c(2L, 4L))
  expect_true(file.exists(dest))
})

test_that("a hosted table with a record of the wrong length is removed, unlisted kept", {
  dest <- keep_host(keep_gz(c("a,b", "1,2", "3")), digest = FALSE)
  expect_warning(expect_error(hostload("db/t"), "did not parse.*record 3.*removed"),
                 "without a SHA-256")
  expect_false(file.exists(dest))
  # a cached table the manifest no longer lists is refused, not deleted
  writeBin(keep_gz(c("a", "1")), dest)
  testthat::with_mocked_bindings(
    expect_error(.rmd_check_sha("db/t", dest), "not listed in the manifest"),
    .rmd_manifest_sha = function(key, refresh = FALSE) NULL)
  expect_true(file.exists(dest))
})

test_that("a cached manifest too large for the memory left is kept, and said so", {
  keep_host(keep_gz(c("a", "1")))
  hostcat()
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  before <- readBin(p, "raw", file.size(p))
  testthat::local_mocked_bindings(.rmd_bl = function(name) {
    function(...) stop("cannot allocate vector of size 3.1 Gb")
  })
  expect_error(.rmd_manifest_parse(p), "not enough memory to read the manifest")
  expect_identical(readBin(p, "raw", file.size(p)), before)
})

test_that("every key has a cache file of its own, also where case is ignored", {
  keep_host(keep_gz(c("a", "1")))
  keys <- c("a__b/c", "a/b__c", "a_/b", "a/_b", "db/T", "db/t", "DB/t", "a-b/c",
            "a/-b_c", "x/y/z", "x/y_-z", "x_-y/z", "A_b/C-d.x")
  names <- basename(vapply(keys, .rmd_host_file, ""))
  expect_identical(anyDuplicated(.rmd_lower(names)), 0L)
  expect_false(any(grepl("[A-Z]", names)))
  # the same folder, however the system writes its separators
  where <- function(d) normalizePath(d, winslash = "/", mustWork = TRUE)
  expect_identical(unique(where(dirname(vapply(keys, .rmd_host_file, "")))),
                   where(file.path(.rmd_data_cache_dir(), "tables")))
  # the name decodes to the key: "__" is "_", "_-" is "/", "_x" is "X"
  dec <- function(n) {
    n <- sub("\\.csv\\.gz$", "", n)
    out <- character()
    i <- 1L
    while (i <= nchar(n)) {
      ch <- substr(n, i, i)
      if (ch == "_") {
        nx <- substr(n, i + 1L, i + 1L)
        ch <- if (nx == "_") "_" else if (nx == "-") "/" else toupper(nx)
        i <- i + 1L
      }
      out <- c(out, ch)
      i <- i + 1L
    }
    paste(out, collapse = "")
  }
  expect_identical(unname(vapply(names, dec, "")), keys)
})

test_that("two keys that shared a cache file under the old names both load", {
  t1 <- keep_gz(c("k", "first"))
  t2 <- keep_gz(c("k", "second"))
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  man <- sprintf(paste0('{"datasets":[{"key":"a__b/c","sha256_gz":"%s"},',
                        '{"key":"a/b__c","sha256_gz":"%s"}]}'),
                 .Call(C_morie_core_sha256, t1), .Call(C_morie_core_sha256, t2))
  calls <- character()
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    calls <<- c(calls, path)
    if (path == "/manifest.json") writeLines(man, dest)
    else writeBin(if (path == "/a__b/c.csv.gz") t1 else t2, dest)
    invisible(dest)
  })
  # a file under the old name is never read as either table
  old <- file.path(.rmd_data_cache_dir(), "a__b__c.csv.gz")
  writeBin(t2, old)
  for (i in 1:2) {
    expect_identical(hostload("a__b/c")$k, "first")
    expect_identical(hostload("a/b__c")$k, "second")
  }
  expect_identical(sum(calls != "/manifest.json"), 2L)
  # and it goes once a table it could be is held under its own name
  expect_false(file.exists(old))
})

test_that("exported functions run under check.bounds and warn = 2, and restore them", {
  df <- data.frame(a = c(1, 1, 2), b = c("x", "y", "x"))
  calls <- list(
    function() mdcat(), function() mdload(mdcat()$slug[mdcat()$kind == "table"][1L]),
    function() mdverify(), function() mdsums(), function() siuload("en"),
    function() cihitbls(), function() chiload("arrests", limit = 5),
    function() kanonvrf(df, "a", 1), function() ldivvrf(df, "a", "b", 1),
    function() cellsupp(matrix(c(1, 9, 9, 9), 2)), function() dplaphist(c(a = 1), 1)
  )
  for (i in seq_along(calls)) {
    # base options only: withr's own code warns under check.bounds
    old <- options(check.bounds = TRUE, warn = 2)
    got <- tryCatch(list(value = calls[[i]](), after = getOption("check.bounds")),
                    error = function(e) conditionMessage(e), finally = options(old))
    expect_true(is.list(got), info = paste(i, got))
    expect_true(isTRUE(got$after), info = i)
  }
})

test_that("a copy cached under the earlier name goes once the table is held anew", {
  keep_host(keep_gz(c("a", "1")))
  old <- file.path(.rmd_data_cache_dir(), "db__t.csv.gz")
  writeLines("stale", old)
  d <- suppressWarnings(hostload("db/t"))
  expect_identical(d$a, 1L)
  expect_false(file.exists(old))
  expect_true(file.exists(.rmd_host_file("db/t")))
})

test_that("gzip data of many blocks inflates whole, counted and written", {
  set.seed(3)
  # past 4 MiB, so the count passes its interrupt check, and of two members
  x <- as.raw(sample(0:255, 5e6, TRUE))
  z <- c(.Call(C_rmd_gzip_compress, x[1:3e6]),
         .Call(C_rmd_gzip_compress, x[-(1:3e6)]))
  expect_identical(.Call(C_rmd_gunzip, z), x)
})
