# data.rmorie.com: key from the shared credentials file, manifest cache, table cache.

test_that("hosted catalog and load use the shared MORIE key and cache locally", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA,
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_null(.rmd_hosted_key())
  expect_error(morie_data_hosted_catalog(), "MORIE key")
  dir.create(file.path(cfg, "morie"), recursive = TRUE)
  writeLines('{"hosted_key": "sk-good", "hosted_user": "me"}',
             file.path(cfg, "morie", "credentials.json"))
  expect_equal(.rmd_hosted_key(), "sk-good")
  calls <- character()
  manifest <- paste0(
    '{"generated_utc":"2026-10-01T00:00:00Z","datasets":[{"db":"chicago_crime",',
    '"table":"incidents","key":"chicago_crime/incidents","rows":3,',
    '"columns":["id","type"],"bytes_gz":10,"sha256":"x",',
    '"source":"bigquery-public-data.chicago_crime.crime",',
    '"meta":{"description":"Chicago Police incidents"}}]}'
  )
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      calls <<- c(calls, path)
      if (path == "/manifest.json") {
        writeLines(manifest, dest)
      } else if (path == "/chicago_crime/incidents.csv.gz") {
        con <- gzfile(dest, "w")
        writeLines(c("id,type", "1,THEFT", "2,BATTERY", "3,THEFT"), con)
        close(con)
      } else {
        stop("404")
      }
      invisible(dest)
    })
  cat_ <- morie_data_hosted_catalog()
  expect_equal(cat_$key, "chicago_crime/incidents")
  expect_equal(cat_$name, "Chicago Police incidents")
  expect_equal(cat_$rows, 3L)
  morie_data_hosted_catalog()
  expect_equal(sum(calls == "/manifest.json"), 1L)
  df <- morie_data_hosted_load("chicago_crime/incidents")
  expect_equal(nrow(df), 3L)
  morie_data_hosted_load("chicago_crime/incidents")
  expect_equal(sum(calls == "/chicago_crime/incidents.csv.gz"), 1L)
  expect_error(morie_data_hosted_load("nokey"), "db/table")
})

test_that("morie_data_hosted_login stores a key via rmoriebricklayer; the hub reads it", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA)
  seen <- NULL
  local_mocked_bindings(
    bricklayer_llm_login = function(token = NULL, email = NULL, code = NULL,
                                    open_browser = FALSE, ...) {
      seen <<- list(token = token, email = email, code = code)
      dir.create(file.path(cfg, "morie"), recursive = TRUE, showWarnings = FALSE)
      writeLines('{"hosted_key": "sk-from-login"}',
                 file.path(cfg, "morie", "credentials.json"))
      invisible("sk-from-login")
    },
    .package = "rmoriebricklayer"
  )
  expect_identical(morie_data_hosted_login(token = "sk-from-login"), "sk-from-login")
  expect_identical(seen$token, "sk-from-login")
  expect_identical(.rmd_hosted_key(), "sk-from-login")
  morie_data_hosted_login(email = "someone@example.org", code = "123456",
                          open_browser = FALSE)
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
      con <- gzfile(dest, "w")
      writeLines(c("id,name,value", "1,a,1", "2,b", "3,c,3"), con)
      close(con)
      invisible(dest)
    },
    .package = "rmoriedata"
  )
  dest <- file.path(rmoriedata:::.rmd_data_cache_dir(), "chicago_crime__incidents.csv.gz")
  expect_error(morie_data_hosted_load("chicago_crime/incidents"),
               "did not parse.*damaged copy was removed")
  expect_false(file.exists(dest))
})
