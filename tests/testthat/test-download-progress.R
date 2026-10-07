# SPDX-License-Identifier: AGPL-3.0-or-later

test_that(".rmd_dl refuses file:// and plain http before sending any header", {
  src <- tempfile(fileext = ".txt")
  writeLines("LOCAL-SECRET", src)
  dest <- tempfile()
  on.exit(unlink(c(src, dest)), add = TRUE)
  expect_error(
    .rmd_dl(paste0("file://", normalizePath(src)), dest,
            headers = c(Authorization = "Bearer SECRET"), quiet = TRUE)
  )
  leaked <- file.exists(dest) && any(grepl("LOCAL-SECRET", readLines(dest, warn = FALSE)))
  expect_false(leaked)
  expect_error(
    .rmd_dl("http://example.com/x.csv.gz", dest,
            headers = c(Authorization = "Bearer SECRET"), quiet = TRUE)
  )
})

test_that(".rmd_dl hands every argument to bricklayer's transport, file:// off", {
  seen <- NULL
  local_mocked_bindings(
    bricklayer_download = function(...) {
      seen <<- list(...)
      invisible(..2)
    },
    .package = "rmoriebricklayer"
  )
  .rmd_dl("https://data.rmorie.com/x.csv.gz", "d", headers = c(A = "b"),
          label = "x", size = 10, timeout = 5, quiet = TRUE, tty = FALSE)
  expect_identical(seen[[1]], "https://data.rmorie.com/x.csv.gz")
  expect_identical(seen$headers, c(A = "b"))
  expect_identical(seen$size, 10)
  expect_identical(seen$timeout, 5)
  expect_false(seen$allow_file)
})
