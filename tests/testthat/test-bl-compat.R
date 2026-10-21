test_that(".rmd_bl: the 1.0.0 function, else the 0.5.1 one, else what is needed", {
  # names both releases export (1.0.0 keeps 0.5.x names as aliases): runs on either
  bl <- function(name) getExportedValue("rmoriebricklayer", name)
  # the name asked for, when the installed release has it
  local_mocked_bindings(.rmd_bl_exports = function() "sha256_file")
  expect_identical(.rmd_bl("sha256_file"), bl("sha256_file"))
  # a 1.0.0 name on a release that has only the 0.5.1 one: the older function
  local_mocked_bindings(.rmd_bl_exports = function() "sha256_file")
  expect_identical(.rmd_bl("sha256file"), bl("sha256_file"))
  # neither: a sentence naming the release that has it
  local_mocked_bindings(.rmd_bl_exports = function() character())
  expect_error(.rmd_bl("llmask"), "needs rmoriebricklayer 1.0.0 or later")
  expect_error(.rmd_bl("sha256file"), "needs rmoriebricklayer 1.0.0 or later")
})

test_that("the fetch seam hands bricklayer its four arguments by position", {
  # blfetch(url, dest, wb, tmout) in 1.0.0;
  # bricklayer_fetch(url, dest, wayback, timeout) in 0.5.1
  local_mocked_bindings(.rmd_bl = function(name) function(...) list(name, ...))
  expect_identical(.rmd_fetch_file("https://x.ca/t.csv", "t.csv", TRUE, 60L),
                   list("blfetch", "https://x.ca/t.csv", "t.csv", TRUE, 60L))
})

test_that("a table's size comes from the cached manifest, and a broken one gives none", {
  dir <- withr::local_tempdir()
  local_mocked_bindings(.rmd_data_cache_dir = function() dir)
  man <- file.path(dir, "manifest.json")
  writeLines('{"datasets": [{"key": "db/t", "bytes_gz": 123}]}', man)
  expect_identical(.rmd_hosted_size("/db/t.csv.gz"), 123L)
  expect_null(.rmd_hosted_size("/db/other.csv.gz"))
  expect_null(.rmd_hosted_size("/db/t.csv"))
  writeLines("{not json", man)
  expect_null(.rmd_hosted_size("/db/t.csv.gz"))
})

test_that("attaching with rmoriebricklayer older than 1.0.0 says what to update", {
  expect_null(.rmd_bl_note(package_version("1.0.0")))
  expect_null(.rmd_bl_note(package_version("1.2.3")))
  note <- .rmd_bl_note(package_version("0.5.1"))
  expect_match(note, "rmoriebricklayer 0.5.1 is installed", fixed = TRUE)
  expect_match(note, "install.packages(\"rmoriebricklayer\")", fixed = TRUE)
  local_mocked_bindings(.rmd_bl_note = function(v) "old bricklayer")
  expect_message(.onAttach("", "rmoriedata"), "old bricklayer")
  local_mocked_bindings(.rmd_bl_note = function(v) NULL)
  expect_silent(.onAttach("", "rmoriedata"))
})
