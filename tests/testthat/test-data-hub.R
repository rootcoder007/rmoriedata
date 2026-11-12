# data.rmorie.com: key from the shared credentials file, manifest cache, table cache.

test_that("hosted catalog and load use the shared MORIE key and cache locally", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA,
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_null(.rmd_hosted_key())
  # no key: nothing is refused locally, the request goes out (to a .test name
  # that never resolves)
  expect_error(hostcat(), "data.example.test")
  dir.create(file.path(cfg, "morie"), recursive = TRUE)
  writeLines('{"hosted_key": "sk-good", "hosted_user": "me"}',
             file.path(cfg, "morie", "credentials.json"))
  expect_equal(.rmd_hosted_key(), "sk-good")
  calls <- character()
  # the table as served, and its digest in the manifest
  served <- tempfile(fileext = ".csv.gz")
  con <- gzfile(served, "w")
  writeLines(c("id,type", "1,THEFT", "2,BATTERY", "3,THEFT"), con)
  close(con)
  manifest <- paste0(
    '{"generated_utc":"2026-10-01T00:00:00Z","datasets":[{"db":"chicago_crime",',
    '"table":"incidents","key":"chicago_crime/incidents","rows":3,',
    '"columns":["id","type"],"bytes_gz":10,"sha256":"',
    .rmd_bl("sha256file")(served), '",',
    '"source":"bigquery-public-data.chicago_crime.crime",',
    '"meta":{"description":"Chicago Police incidents"}}]}'
  )
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      calls <<- c(calls, path)
      if (path == "/manifest.json") {
        writeLines(manifest, dest)
      } else if (path == "/chicago_crime/incidents.csv.gz") {
        file.copy(served, dest, overwrite = TRUE)
      } else {
        stop("404")
      }
      invisible(dest)
    })
  cat_ <- hostcat()
  expect_equal(cat_$key, "chicago_crime/incidents")
  expect_equal(cat_$name, "Chicago Police incidents")
  expect_equal(cat_$rows, 3L)
  hostcat()
  expect_equal(sum(calls == "/manifest.json"), 1L)
  df <- hostload("chicago_crime/incidents")
  expect_equal(nrow(df), 3L)
  hostload("chicago_crime/incidents")
  expect_equal(sum(calls == "/chicago_crime/incidents.csv.gz"), 1L)
  expect_error(hostload("nokey"), "db/table")
})

test_that("hostlogin stores a key via rmoriebricklayer; the hub reads it", {
  skip_if_old_bricklayer()
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA)
  seen <- NULL
  local_mocked_bindings(
    dlogin = function(token = NULL, email = NULL, code = NULL,
                                    openbro = FALSE, ...) {
      seen <<- list(token = token, email = email, code = code)
      dir.create(file.path(cfg, "morie"), recursive = TRUE, showWarnings = FALSE)
      writeLines('{"hosted_key": "sk-from-login"}',
                 file.path(cfg, "morie", "credentials.json"))
      invisible("sk-from-login")
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(hostlogin(token = "sk-from-login"), "sk-from-login")
  expect_identical(seen$token, "sk-from-login")
  expect_identical(.rmd_hosted_key(), "sk-from-login")
  hostlogin(email = "someone@example.org", code = "123456",
                          openbro = FALSE)
  expect_identical(seen$email, "someone@example.org")
  expect_identical(seen$code, "123456")
})

test_that("a damaged hosted table (a short row) is refused and its copy removed", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA,
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      if (path == "/manifest.json") {  # listed without a digest, as some tables are
        writeLines('{"datasets":[{"key":"chicago_crime/incidents","rows":3}]}', dest)
        return(invisible(dest))
      }
      con <- gzfile(dest, "w")
      writeLines(c("id,name,value", "1,a,1", "2,b", "3,c,3"), con)
      close(con)
      invisible(dest)
    },
    .package = "rmoriedata"
  )
  dest <- file.path(rmoriedata:::.rmd_data_cache_dir(), "chicago_crime__incidents.csv.gz")
  expect_error(hostload("chicago_crime/incidents"),
               "did not parse.*damaged copy was removed")
  expect_false(file.exists(dest))
})

test_that("a table failing the manifest's SHA-256 is deleted after a refresh", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = "sk-x",
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  manifest <- '{"datasets":[{"key":"chicago_crime/incidents","rows":1,"sha256":"%s"}]}'
  calls <- character()
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      calls <<- c(calls, path)
      if (path == "/manifest.json") writeLines(sprintf(manifest, strrep("a", 64)), dest)
      else writeLines("not the served table", dest)
      invisible(dest)
    },
    .package = "rmoriedata"
  )
  dest <- file.path(rmoriedata:::.rmd_data_cache_dir(), "chicago_crime__incidents.csv.gz")
  expect_error(hostload("chicago_crime/incidents"),
               "does not match the manifest's SHA-256 .*aaaaaaaaaaaa")
  expect_false(file.exists(dest))
  # the manifest is fetched again before the file is called bad
  expect_identical(sum(calls == "/manifest.json"), 2L)
  # a table the manifest does not list is not kept either
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      writeLines(if (path == "/manifest.json") '{"datasets":[]}' else "x", dest)
      invisible(dest)
    },
    .package = "rmoriedata"
  )
  expect_error(hostload("chicago_crime/incidents", refresh = TRUE),
               "not listed in the manifest")
})

test_that("a table refused with 403 names the stored key, not a terms sign-in", {
  # no table is behind accepted terms any more (the tables open without sign-in,
  # and ICPSR studies answer 410): a 403 with a key sent means the key was refused
  withr::local_envvar(MORIE_HOSTED_KEY = "sk-x",
                      MORIE_DATA_URL = "https://data.example.test")
  # the services document names that address, so the stored key is sent there
  testthat::local_mocked_bindings(.rmd_dl = function(...) stop("answered HTTP 403"),
                                  .rmd_services_data = function() {
                                    list(mode = "key",
                                         base_url = "https://data.example.test")
                                  },
                                  .package = "rmoriedata")
  expect_error(rmoriedata:::.rmd_data_get("/a2aj_onca/onca_meta.csv.gz", tempfile()),
               "rejected the stored key")
  expect_error(rmoriedata:::.rmd_data_get("/chicago_crime/incidents.csv.gz", tempfile()),
               "rejected the stored key")
  expect_false(exists(".rmd_restricted", asNamespace("rmoriedata"), inherits = FALSE))
})

test_that("a refused table says why: ICPSR (410), a key asked for, a key rejected", {
  fail <- "bldl: https://data.example.test/x answered HTTP 410"
  key <- NULL
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_hosted_key = function() key,
    .rmd_hosted_size = function(path) NULL,
    .rmd_dl = function(...) stop(fail, call. = FALSE)
  )
  dest <- withr::local_tempfile()
  expect_error(.rmd_data_get("/icpsr_9/t.csv.gz", dest),
               "icpsr_9/t is not served by data.rmorie.com: ICPSR's terms")
  fail <- "bldl: https://data.example.test/x answered HTTP 401"
  expect_error(.rmd_data_get("/fec/t.csv.gz", dest),
               "data.rmorie.com asked for a key for fec/t")
  key <- "sk-x"
  expect_error(.rmd_data_get("/fec/t.csv.gz", dest), "rejected the stored key")
  fail <- NULL
  key <- NULL
  st <- new.env()
  testthat::local_mocked_bindings(.rmd_dl = function(url, dest, headers = NULL, ...) {
    st$hdrs <- headers
    invisible(dest)
  })
  expect_identical(.rmd_data_get("/fec/t.csv.gz", dest), dest)
  expect_false("Authorization" %in% names(st$hdrs))
})

test_that("the stored key goes only to the services document's address", {
  withr::local_envvar(MORIE_HOSTED_KEY = "sk-x",
                      MORIE_DATA_URL = "https://elsewhere.example.test")
  st <- new.env()
  testthat::local_mocked_bindings(
    .rmd_services_data = function() {
      list(mode = "key", base_url = "https://data.example.test")
    },
    .rmd_hosted_size = function(path) NULL,
    .rmd_dl = function(url, dest, headers = NULL, ...) {
      st$url <- url
      st$hdrs <- headers
      invisible(dest)
    }
  )
  dest <- withr::local_tempfile()
  expect_message(.rmd_data_get("/fec/t.csv.gz", dest), "the stored key is not sent")
  expect_false("Authorization" %in% names(st$hdrs))
  expect_identical(st$url, "https://elsewhere.example.test/fec/t.csv.gz")
  # data.rmorie.com serves a table without a key only to a package User-Agent
  expect_match(st$hdrs[["User-Agent"]],
               "^(rmoriebricklayer|rmoriedata|rmorie|morie)/[0-9]")
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test/")
  expect_silent(.rmd_data_get("/fec/t.csv.gz", dest))
  expect_identical(st$hdrs[["Authorization"]], "Bearer sk-x")
})
