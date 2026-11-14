# Large curated tables come down in byte-range parts: kept once whole, resumed
# from the first missing part, joined in order. No network: the transport is a
# stub that serves the range asked for from memory.

test_that("a large table comes in parts, resumed and joined in order", {
  st <- new.env()
  set.seed(1)
  bytes <- as.raw(sample(0:255, 5000, replace = TRUE))
  st$seen <- character()
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, headers = NULL, ...) {
      r <- as.numeric(strsplit(sub("^bytes=", "", headers[["Range"]]), "-")[[1]])
      st$seen <- c(st$seen, headers[["Range"]])
      writeBin(bytes[(r[1] + 1):(r[2] + 1)], dest)
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(readBin(dest, "raw", 6000), bytes)
  expect_length(st$seen, 5L)
  expect_false(dir.exists(paste0(dest, ".parts")))
  unlink(dest)
  pd <- paste0(dest, ".parts")
  dir.create(pd)
  writeBin(bytes[1:1024], file.path(pd, "00001"))
  writeBin(bytes[1025:1100], file.path(pd, "00002"))
  st$seen <- character()
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(readBin(dest, "raw", 6000), bytes)
  expect_identical(st$seen, c("bytes=1024-2047", "bytes=2048-3071", "bytes=3072-4095",
                           "bytes=4096-4999"))
})

test_that("a short or failed part is refused and can be resumed", {
  fail <- NULL
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, ...) {
      if (!is.null(fail)) stop(fail, call. = FALSE)
      writeBin(as.raw(1:10), dest)
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  expect_error(.rmd_get_parts("/db/t.csv.gz", dest, character(), "db/t", 5000, 1024, 60),
               "part 1 of db/t came back with 10 bytes, not 1024; run again to resume")
  expect_false(file.exists(file.path(paste0(dest, ".parts"), "00001")))
  fail <- "bldl: https://data.example.test/x answered HTTP 410"
  expect_error(.rmd_get_parts("/icpsr_9/t.csv.gz", dest, character(), "icpsr_9/t",
                              5000, 1024, 60),
               "icpsr_9/t is not served by data.rmorie.com")
})

test_that("only a table more than twice the part size goes in parts", {
  st <- new.env()
  withr::local_options(rmoriedata.dpart = 10)
  expect_error(.rmd_part_bytes(), "at least 1 MB")
  withr::local_options(rmoriedata.dpart = NULL)
  expect_identical(.rmd_part_bytes(), 90 * 2^20)
  st$called <- NULL
  testthat::local_mocked_bindings(
    .rmd_hosted_size = function(path) 300 * 2^20,
    .rmd_get_parts = function(path, dest, hdr, label, size, part, timeout) {
      st$called <- c(size, part)
      invisible(dest)
    }
  )
  .rmd_data_get("/db/t.csv.gz", withr::local_tempfile())
  expect_identical(st$called, c(300 * 2^20, 90 * 2^20))
})

test_that("a server that answers a range with the whole file is used whole", {
  set.seed(2)
  bytes <- as.raw(sample(0:255, 5000, replace = TRUE))
  st <- new.env()
  st$n <- 0L
  st$body <- bytes
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, headers = NULL, ...) {
      st$n <- st$n + 1L
      st$range <- c(st$range, "Range" %in% names(headers))
      writeBin(st$body, dest) # HTTP 200: the Range header is ignored
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(readBin(dest, "raw", 6000), bytes)
  expect_identical(st$n, 1L)
  expect_false(dir.exists(paste0(dest, ".parts")))
  # a body longer than a part but not the size listed: fetched once in one piece
  unlink(dest)
  st$n <- 0L
  st$range <- NULL
  st$body <- c(bytes, bytes)
  .rmd_get_parts("/db/t.csv.gz", dest, c(`User-Agent` = "x"), "db/t", 5000, 1024, 60)
  expect_identical(st$range, c(TRUE, FALSE))
  expect_identical(file.size(dest), 10000)
  expect_false(dir.exists(paste0(dest, ".parts")))
})

test_that("a failed first part leaves no empty parts directory", {
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_dl = function(url, dest, ...) {
      writeBin(as.raw(1:10), dest)
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  expect_error(.rmd_get_parts("/db/t.csv.gz", dest, character(), "db/t", 5000, 1024, 60),
               "came back with 10 bytes")
  expect_false(dir.exists(paste0(dest, ".parts")))
})

test_that("the join of the parts fails in words on a full disk, and frees the parts", {
  d <- withr::local_tempdir()
  p <- file.path(d, c("1", "2"))
  writeBin(as.raw(1:3), p[1L])
  writeBin(as.raw(4:5), p[2L])
  dest <- file.path(d, "t.csv.gz")
  .rmd_join(p, dest)
  expect_identical(readBin(dest, "raw", 10L), as.raw(1:5))
  expect_false(any(file.exists(p)))
  expect_false(file.exists(paste0(dest, ".join")))
  unlink(dest)
  writeBin(as.raw(1:3), p[1L])
  testthat::local_mocked_bindings(
    .rmd_write_raw = function(buf, out) warning("problem writing to connection")
  )
  expect_error(.rmd_join(p[1L], dest), "is full or cannot be written")
  expect_error(.rmd_join(p[1L], dest), "rmoriedata.cache_dir")
  expect_false(file.exists(dest))
  expect_false(file.exists(paste0(dest, ".join")))
})

test_that("a missing or unreadable part stops the join before any part is deleted", {
  d <- withr::local_tempdir()
  p <- file.path(d, sprintf("%05d", 1:3))
  mk <- function() for (i in 1:3) writeBin(as.raw(rep(i, 10)), p[i])
  mk()
  dest <- file.path(d, "t.gz")
  unlink(p[3L])
  expect_error(.rmd_join(p, dest),
               "part 3 (.*) is missing or cannot be read; no part was joined or deleted")
  expect_identical(file.exists(p), c(TRUE, TRUE, FALSE))
  expect_false(file.exists(dest))
  expect_length(list.files(d, pattern = "join"), 0L)
  mk()
  if (.Platform$OS.type == "unix") {
    Sys.chmod(p[2L], "000")
    if (file.access(p[2L], 4L) != 0L) {
      expect_error(.rmd_join(p, dest), "part 2 (.*) is missing or cannot be read")
      expect_true(all(file.exists(p)))
    }
    Sys.chmod(p[2L], "644")
  }
  .rmd_join(p, dest)
  expect_identical(readBin(dest, "raw", 100L), as.raw(rep(1:3, each = 10)))
  # a part that goes missing during the join is an error in words, not a base-R one
  mk()
  testthat::local_mocked_bindings(.rmd_write_raw = function(buf, out) {
    unlink(p[3L])
    writeBin(buf, out)
  })
  expect_error(.rmd_join(p, dest), "part 3 (.*) went missing or could not be read")
  expect_length(list.files(d, pattern = "join"), 0L)
})

test_that("two joins of one table at once write into files of their own", {
  d <- withr::local_tempdir()
  pa <- file.path(d, c("a1", "a2"))
  pb <- file.path(d, c("b1", "b2"))
  for (i in 1:2) {
    writeBin(as.raw(rep(i, 5)), pa[i])
    writeBin(as.raw(rep(i + 10, 7)), pb[i])
  }
  dest <- file.path(d, "t.gz")
  n <- 0L
  testthat::local_mocked_bindings(.rmd_write_raw = function(buf, out) {
    writeBin(buf, out)
    n <<- n + 1L
    # the other session joins the whole table while this one is half-way
    if (n == 1L) .rmd_join(pb, dest)
  })
  .rmd_join(pa, dest)
  expect_identical(readBin(dest, "raw", 100L), as.raw(rep(1:2, each = 5)))
  expect_length(list.files(d, pattern = "join"), 0L)
})

test_that("the table lock is held by one caller at a time and freed on error", {
  lock <- withr::local_tempfile()
  busy <- new.env()
  inner <- function() .Call(C_rmd_flock_with, lock, function() "inner", busy)
  # held by this caller: a second descriptor on the same file is refused at once
  expect_identical(.Call(C_rmd_flock_with, lock, inner, busy), busy)
  expect_identical(.Call(C_rmd_flock_with, lock, function() "free", busy), "free")
  expect_error(.rmd_locked(lock, "db/t", function() stop("boom")), "boom")
  expect_identical(.rmd_locked(lock, "db/t", function() 1L), 1L)
  expect_error(.Call(C_rmd_flock_with, withr::local_tempdir(), inner, busy),
               "cannot open the lock file|is not a regular file")
})

# Real R sessions downloading one hosted table at once, against a stub transport
# (no network) that serves the manifest and byte ranges of the table from files
# and logs every range it serves.
hub_child <- c(
  "a <- commandArgs(TRUE)",
  "suppressMessages(library(rmoriedata))",
  "body <- readBin(a[2], \"raw\", file.size(a[2]))",
  "man <- readLines(a[3])",
  "stub <- function(url, dest, headers = NULL, ...) {",
  "  if (grepl(\"manifest.json$\", url)) {",
  "    writeLines(man, dest)",
  "    return(invisible(dest))",
  "  }",
  "  r <- headers[[\"Range\"]]",
  "  ab <- as.numeric(strsplit(sub(\"^bytes=\", \"\", r), \"-\")[[1]])",
  "  b <- body[(ab[1] + 1):(ab[2] + 1)]",
  "  cat(r, \"\\n\", file = a[4], append = TRUE)",
  "  if (identical(a[5], \"hang\") && ab[1] >= 2 * 2^20) {",
  "    writeBin(b[1:100], dest)",
  "    writeLines(as.character(Sys.getpid()), paste0(a[6], \".tmp\"))",
  "    file.rename(paste0(a[6], \".tmp\"), a[6])",
  "    Sys.sleep(600)",
  "  }",
  "  Sys.sleep(0.05)",
  "  writeBin(b, dest)",
  "  invisible(dest)",
  "}",
  "utils::assignInNamespace(\".rmd_dl\", stub, \"rmoriedata\")",
  "utils::assignInNamespace(\".rmd_data_url\",",
  "                         function() \"https://data.example.test\", \"rmoriedata\")",
  "options(rmoriedata.cache_dir = a[1], rmoriedata.dpart = 2^20, morie.quiet = TRUE)",
  "out <- tryCatch({",
  "  df <- suppressMessages(rmoriedata::hostload(\"db/t\"))",
  "  paste(\"ok\", nrow(df), sum(df$v))",
  "}, error = function(e) paste(\"error:\", conditionMessage(e)))",
  "writeLines(out, paste0(a[6], \".tmp\"))",
  "file.rename(paste0(a[6], \".tmp\"), a[6])"
)

hub_table <- function(d) {
  served <- file.path(d, "served.csv.gz")
  n <- 150000L
  con <- gzfile(served, "w", compression = 0)
  writeLines(c("v,s", paste0(seq_len(n), ",", sprintf("%012d", seq_len(n) * 7L))), con)
  close(con)
  man <- file.path(d, "manifest.json")
  writeLines(sprintf(
    '{"datasets":[{"key":"db/t","rows":%d,"bytes_gz":%.0f,"sha256_gz":"%s"}]}',
    n, file.size(served), rmoriebricklayer::sha256file(served)), man)
  list(served = served, man = man, n = n, sum = sum(as.numeric(seq_len(n))),
       size = file.size(served))
}

hub_run <- function(d, cache, log, out, mode = "ok") {
  system2(file.path(R.home("bin"), "Rscript"),
          c("--vanilla",
            shQuote(c(file.path(d, "child.R"), cache, file.path(d, "served.csv.gz"),
                      file.path(d, "manifest.json"), log, mode, out))),
          stdout = FALSE, stderr = FALSE, wait = FALSE)
}

hub_wait <- function(files, secs = 120) {
  t0 <- Sys.time()
  while (!all(file.exists(files)) &&
         as.numeric(Sys.time() - t0, units = "secs") < secs) {
    Sys.sleep(0.1)
  }
  expect_true(all(file.exists(files)))
}

hub_ranges <- function(size) {
  a <- seq(0, size - 1, by = 2^20)
  sprintf("bytes=%.0f-%.0f", a, pmin(a + 2^20, size) - 1)
}

test_that("four R sessions downloading one table at once share it safely", {
  skip_on_cran()
  d <- withr::local_tempdir()
  writeLines(hub_child, file.path(d, "child.R"))
  fx <- hub_table(d)
  expect_gt(fx$size, 2 * 2^20)
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
                      R_TESTS = NA)
  for (k in 1:3) {
    cache <- file.path(d, paste0("cache", k))
    dir.create(cache)
    log <- file.path(d, paste0("log", k))
    out <- file.path(d, sprintf("out%d_%d", k, 1:4))
    for (o in out) hub_run(d, cache, log, o)
    hub_wait(out)
    res <- vapply(out, function(f) readLines(f), "")
    expect_identical(unname(res), rep(sprintf("ok %d %.0f", fx$n, fx$sum), 4L))
    # every part was served once: one session downloaded, the others waited and
    # used its finished, verified table
    expect_identical(sort(trimws(readLines(log))), sort(hub_ranges(fx$size)))
    left <- list.files(file.path(cache, "hosted"))
    expect_setequal(left, c("db__t.csv.gz", "db__t.csv.gz.lock", "manifest.json"))
    expect_identical(unname(tools::md5sum(file.path(cache, "hosted", "db__t.csv.gz"))),
                     unname(tools::md5sum(fx$served)))
  }
})

test_that("a download killed half-way resumes from its parts in the next session", {
  skip_on_cran()
  d <- withr::local_tempdir()
  writeLines(hub_child, file.path(d, "child.R"))
  fx <- hub_table(d)
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
                      R_TESTS = NA)
  cache <- file.path(d, "cache")
  dir.create(cache)
  log <- file.path(d, "log")
  hub_run(d, cache, log, file.path(d, "pid"), mode = "hang")
  hub_wait(file.path(d, "pid"))
  pid <- as.integer(readLines(file.path(d, "pid")))
  # killed while it holds the lock and is writing the third part; Windows has
  # no SIGKILL (it is NA there) and ends the process outright for any signal
  sig <- if (.Platform$OS.type == "windows") tools::SIGTERM else tools::SIGKILL
  expect_true(tools::pskill(pid, sig))
  hd <- file.path(cache, "hosted")
  expect_true(dir.exists(file.path(hd, "db__t.csv.gz.dl.parts")))
  expect_false(file.exists(file.path(hd, "db__t.csv.gz")))
  n1 <- length(readLines(log))
  hub_run(d, cache, log, file.path(d, "out"))
  hub_wait(file.path(d, "out"))
  expect_identical(readLines(file.path(d, "out")), sprintf("ok %d %.0f", fx$n, fx$sum))
  # the two whole parts were kept: the new session fetched the third part again
  # and the rest, nothing before
  r <- hub_ranges(fx$size)
  expect_identical(trimws(readLines(log))[-seq_len(n1)], r[-(1:2)])
  expect_setequal(list.files(hd), c("db__t.csv.gz", "db__t.csv.gz.lock", "manifest.json"))
})
