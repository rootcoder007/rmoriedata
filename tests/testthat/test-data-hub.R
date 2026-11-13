# data.rmorie.com: no key is read or sent; manifest cache, table cache.

test_that("hosted catalog and load need no key and cache locally", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA,
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  # no key: nothing is refused locally, the request goes out (to a .test name
  # that never resolves)
  expect_error(hostcat(), "data.example.test")
  # a credentials file left by an earlier version changes nothing
  dir.create(file.path(cfg, "morie"), recursive = TRUE)
  writeLines('{"hosted_key": "sk-good", "hosted_user": "me"}',
             file.path(cfg, "morie", "credentials.json"))
  expect_false(exists(".rmd_hosted_key", asNamespace("rmoriedata"), inherits = FALSE))
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
  # listed without a digest: used with a warning (once per session), then refused
  expect_warning(expect_error(hostload("chicago_crime/incidents"),
                              "did not parse.*damaged copy was removed"),
                 "without a SHA-256")
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

test_that("a table refused with 403 says no sign-in is needed, old key or not", {
  # no table is behind a key or accepted terms (ICPSR studies answer 410): a 403
  # is the service's refusal, and no stored key is involved
  withr::local_envvar(MORIE_HOSTED_KEY = "sk-x",
                      MORIE_DATA_URL = "https://data.example.test")
  testthat::local_mocked_bindings(.rmd_dl = function(...) stop("answered HTTP 403"),
                                  .rmd_services_data = function() {
                                    list(mode = "key",
                                         base_url = "https://data.example.test")
                                  },
                                  .package = "rmoriedata")
  expect_error(rmoriedata:::.rmd_data_get("/a2aj_onca/onca_meta.csv.gz", tempfile()),
               "refused a2aj_onca/onca_meta: the tables need no sign-in")
  expect_error(rmoriedata:::.rmd_data_get("/chicago_crime/incidents.csv.gz", tempfile()),
               "refused chicago_crime/incidents: the tables need no sign-in")
  expect_false(exists(".rmd_restricted", asNamespace("rmoriedata"), inherits = FALSE))
})

test_that("a refused table says why: ICPSR (410), or that no sign-in is needed", {
  fail <- "bldl: https://data.example.test/x answered HTTP 410"
  testthat::local_mocked_bindings(
    .rmd_data_url = function() "https://data.example.test",
    .rmd_hosted_size = function(path) NULL,
    .rmd_dl = function(...) stop(fail, call. = FALSE)
  )
  dest <- withr::local_tempfile()
  expect_error(.rmd_data_get("/icpsr_9/t.csv.gz", dest),
               "icpsr_9/t is not served by data.rmorie.com: ICPSR's terms")
  fail <- "bldl: https://data.example.test/x answered HTTP 401"
  expect_error(.rmd_data_get("/fec/t.csv.gz", dest),
               "data.rmorie.com refused fec/t: the tables need no sign-in")
  fail <- NULL
  st <- new.env()
  testthat::local_mocked_bindings(.rmd_dl = function(url, dest, headers = NULL, ...) {
    st$hdrs <- headers
    invisible(dest)
  })
  expect_identical(.rmd_data_get("/fec/t.csv.gz", dest), dest)
  expect_false("Authorization" %in% names(st$hdrs))
})

test_that("no key is ever sent: not one in the environment, not one stored earlier", {
  cfg <- withr::local_tempdir()
  dir.create(file.path(cfg, "morie"), recursive = TRUE)
  writeLines('{"hosted_key": "sk-stored"}', file.path(cfg, "morie", "credentials.json"))
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = "sk-x",
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
  expect_silent(.rmd_data_get("/fec/t.csv.gz", dest))
  expect_false("Authorization" %in% names(st$hdrs))
  expect_identical(st$url, "https://elsewhere.example.test/fec/t.csv.gz")
  # data.rmorie.com serves a table only to a package User-Agent
  expect_match(st$hdrs[["User-Agent"]],
               "^(rmoriebricklayer|rmoriedata|rmorie|morie)/[0-9]")
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test/")
  expect_silent(.rmd_data_get("/fec/t.csv.gz", dest))
  expect_false("Authorization" %in% names(st$hdrs))
  expect_false(any(grepl("sk-", unlist(st$hdrs), fixed = TRUE)))
})

# A manifest and a served table for the tests below: `fields` are the entry's
# digest fields, `extra` more entries. The table is the bytes of `served`.
hub_fixture <- function(fields, extra = list()) {
  served <- withr::local_tempfile(fileext = ".csv.gz", .local_envir = parent.frame())
  con <- gzfile(served, "w")
  writeLines(c("REF_DATE,VALUE", "2020,1", "2021,2"), con)
  close(con)
  ent <- c(list(key = "statcan_health/tbl_1", rows = 2), fields)
  m <- list(datasets = c(list(ent), extra))
  list(served = served, manifest = rmoriebricklayer::tojs(m, auto_unbox = TRUE))
}

hub_mock <- function(fx, calls_env, envir = parent.frame()) {
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      calls_env$calls <- c(calls_env$calls, path)
      if (path == "/manifest.json") {
        writeLines(fx$manifest, dest)
      } else {
        file.copy(fx$served, dest, overwrite = TRUE)
      }
      invisible(dest)
    },
    .package = "rmoriedata", .env = envir
  )
}

hub_tamper <- function(key) {
  f <- file.path(rmoriedata:::.rmd_data_cache_dir(),
                 paste0(gsub("/", "__", key, fixed = TRUE), ".csv.gz"))
  con <- gzfile(f, "w")
  writeLines(c("REF_DATE,VALUE", "2020,999999", "2021,2"), con)
  close(con)
  f
}

test_that("a table listed only with sha256_gz is verified, tampering refused (RD-H1)", {
  withr::local_envvar(MORIE_HOSTED_KEY = NA, MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  fx <- hub_fixture(list())
  dig <- rmoriebricklayer::sha256file(fx$served)
  # the digest under each of the three names bricklayer reads, alone
  for (f in c("sha256_gz", "sha256", "sha")) {
    fx <- hub_fixture(stats::setNames(list(dig), f))
    st <- new.env()
    hub_mock(fx, st)
    withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
    df <- expect_no_warning(hostload("statcan_health/tbl_1"))
    expect_identical(df$VALUE, c(1L, 2L))
    p <- hub_tamper("statcan_health/tbl_1")
    expect_error(hostload("statcan_health/tbl_1"),
                 paste0("does not match the manifest's SHA-256 .*", substr(dig, 1L, 12L)))
    expect_false(file.exists(p))
  }
  # sha256_gz is read first, and a "sha256:" prefix is accepted
  fx <- hub_fixture(list(sha256_gz = paste0("sha256:", toupper(dig)),
                         sha256 = strrep("0", 64)))
  st <- new.env()
  hub_mock(fx, st)
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_identical(hostload("statcan_health/tbl_1")$VALUE, c(1L, 2L))
  # a digest field that is not a digest is an error, not "no digest"
  fx <- hub_fixture(list(sha256_gz = "not-a-digest"))
  hub_mock(fx, st)
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_error(hostload("statcan_health/tbl_1"),
               "the manifest's sha256_gz for statcan_health/tbl_1 is not a SHA-256")
  fx <- hub_fixture(list(sha256_gz = list(dig, dig)))
  hub_mock(fx, st)
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_error(hostload("statcan_health/tbl_1"), "is not a SHA-256 hex digest")
})

test_that("a table listed without a digest loads with one warning per session", {
  withr::local_envvar(MORIE_HOSTED_KEY = NA, MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  rm(list = ls(rmoriedata:::.rmd_nodigest), envir = rmoriedata:::.rmd_nodigest)
  fx <- hub_fixture(list())
  st <- new.env()
  hub_mock(fx, st)
  expect_warning(df <- hostload("statcan_health/tbl_1"),
                 "statcan_health/tbl_1 is listed in the manifest .* without a SHA-256")
  expect_identical(df$VALUE, c(1L, 2L))
  expect_no_warning(hostload("statcan_health/tbl_1"))
  rm(list = ls(rmoriedata:::.rmd_nodigest), envir = rmoriedata:::.rmd_nodigest)
})

test_that("tables whose terms forbid redistribution are not listed (RD-M1)", {
  withr::local_envvar(MORIE_HOSTED_KEY = NA, MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  one <- function(k, ...) list(key = k, rows = 1, ...)
  fx <- hub_fixture(list(), extra = list(
    one("icpsr_21600/ds0001"), one("icpsr_34562/ds0002"), one("ncvs_38604/incident"),
    one("a2aj_onca/onca_decisions_meta"),
    one("justice_open/t1", meta = list(access = "open")),
    one("other/marked", meta = list(access = "restricted")),
    one("other/flagged", restricted = TRUE)
  ))
  st <- new.env()
  hub_mock(fx, st)
  expect_message(cat_ <- hostcat(),
                 paste("^5 tables are not served: their source terms do not",
                       "allow redistribution"))
  expect_identical(cat_$key, c("statcan_health/tbl_1", "a2aj_onca/onca_decisions_meta",
                               "justice_open/t1"))
  # an ICPSR key stops before any request, the manifest included
  st$calls <- NULL
  for (k in c("icpsr_21600/ds0001", "ncvs_38604/incident", "icpsr_99/new")) {
    msg <- paste0(k, " is not served by data.rmorie.com: ICPSR's terms do not allow ",
                  "redistribution; download it from ICPSR")
    expect_error(hostload(k), msg, fixed = TRUE)
  }
  expect_null(st$calls)
  # a table the manifest marks: the manifest is read, the table never requested
  expect_error(hostload("other/marked"),
               "other/marked is not served by data.rmorie.com: its source")
  expect_error(hostload("other/flagged", refresh = TRUE), "other/flagged is not served")
  expect_false(any(grepl("^/other/", st$calls)))
  # A2AJ case law is an ordinary open table
  expect_warning(expect_identical(nrow(hostload("a2aj_onca/onca_decisions_meta")), 2L),
                 "without a SHA-256")
  expect_true("/a2aj_onca/onca_decisions_meta.csv.gz" %in% st$calls)
  # one table: the singular
  fx1 <- hub_fixture(list(), extra = list(one("icpsr_21600/ds0001")))
  hub_mock(fx1, st)
  expect_message(hostcat(refresh = TRUE), "^1 table is not served: its source terms")
  # nothing left out (as the live manifest is now): no note at all
  fx0 <- hub_fixture(list(), extra = list(one("a2aj_onca/onca_decisions_meta")))
  hub_mock(fx0, st)
  expect_no_message(cat0 <- hostcat(refresh = TRUE))
  expect_identical(nrow(cat0), 2L)
})

test_that("a manifest fetched again after a mismatch decides: marked, or no digest", {
  withr::local_envvar(MORIE_HOSTED_KEY = NA, MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  rm(list = ls(rmoriedata:::.rmd_nodigest), envir = rmoriedata:::.rmd_nodigest)
  fx <- hub_fixture(list())
  dig <- rmoriebricklayer::sha256file(fx$served)
  # first manifest: the table with its digest; the one fetched again after the
  # mismatch: `then`
  for (then in list(list(meta = list(access = "restricted")), list())) {
    withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
    st <- new.env()
    st$n <- 0L
    testthat::local_mocked_bindings(
      .rmd_data_get = function(path, dest, timeout = 600) {
        if (path == "/manifest.json") {
          st$n <- st$n + 1L
          e <- c(list(key = "statcan_health/tbl_1"),
                 if (st$n == 1L) list(sha256_gz = dig) else then)
          writeLines(rmoriebricklayer::tojs(list(datasets = list(e)), auto_unbox = TRUE),
                     dest)
        } else {
          file.copy(fx$served, dest, overwrite = TRUE)
        }
        invisible(dest)
      },
      .package = "rmoriedata"
    )
    hostload("statcan_health/tbl_1")
    hub_tamper("statcan_health/tbl_1")
    if (length(then)) {
      expect_error(hostload("statcan_health/tbl_1"),
                   "statcan_health/tbl_1 is not served by data.rmorie.com")
    } else {
      expect_warning(df <- hostload("statcan_health/tbl_1"), "without a SHA-256")
      expect_identical(df$VALUE, c(999999L, 2L))
    }
  }
  rm(list = ls(rmoriedata:::.rmd_nodigest), envir = rmoriedata:::.rmd_nodigest)
})
