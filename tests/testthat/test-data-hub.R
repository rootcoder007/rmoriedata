# data.rmorie.com: no key is read or sent; manifest cache, table cache.

test_that("hosted catalog and load need no key and cache locally", {
  cfg <- withr::local_tempdir()
  withr::local_envvar(XDG_CONFIG_HOME = cfg, MORIE_HOSTED_KEY = NA,
                      MORIE_DATA_URL = "https://data.example.test")
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  # no key: nothing is refused locally, and the request goes out, with no key
  # in it. Tests that R CMD check runs on CRAN (NOT_CRAN unset) must not touch
  # the network, so there the transport is replaced; elsewhere the real one
  # also tries the .test name, which never resolves.
  sent <- list()
  testthat::with_mocked_bindings(
    expect_error(hostcat(), "data.example.test"),
    .rmd_dl = function(url, dest, headers = NULL, ...) {
      sent[[length(sent) + 1L]] <<- list(url = url, headers = headers)
      stop("bldl: ", url, ": could not resolve host", call. = FALSE)
    })
  expect_identical(sent[[1L]]$url, "https://data.example.test/manifest.json")
  expect_false(any(tolower(names(sent[[1L]]$headers)) == "authorization"))
  if (identical(Sys.getenv("NOT_CRAN"), "true")) {
    expect_error(hostcat(), "data.example.test")
  }
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
  dest <- rmoriedata:::.rmd_host_file("chicago_crime/incidents")
  # listed without a digest: used with a warning (once per session), then refused
  expect_warning(expect_error(hostload("chicago_crime/incidents"),
                              "did not parse.*damaged copy was removed, try again$"),
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
  dest <- rmoriedata:::.rmd_host_file("chicago_crime/incidents")
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
  f <- rmoriedata:::.rmd_host_file(key)
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
  # another cache folder holds another manifest: said again
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  expect_warning(hostload("statcan_health/tbl_1"), "without a SHA-256")
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

test_that("a refusal is read from the status answered, not from the table's name", {
  f <- function(msg, label) {
    tryCatch(.rmd_data_failed(simpleError(msg), label), error = conditionMessage)
  }
  k <- "statcan_indigenous/tbl_41100401"
  u <- paste0("bldl: https://data.rmorie.com/", k, ".csv.gz answered HTTP ")
  # told in the package's words, without the transport's function name
  expect_match(f(paste0(u, "404"), k),
               paste0("^rmoriedata could not download ", k,
                      ": https://.* answered HTTP 404$"))
  expect_match(f(paste0(u, "500"), "statcan_indigenous/tbl_41100403"),
               "^rmoriedata could not download .* answered HTTP 500$")
  expect_match(f(paste0(u, "403"), k), "need no sign-in")
  expect_match(f(paste0(u, "401"), "fec/t"), "need no sign-in")
  expect_match(f(paste0(u, "410"), "fec/t"),
               "fec/t is no longer served .* its source does not allow")
  expect_match(f(paste0(u, "410"), "icpsr_9/t"), "ICPSR's terms")
  expect_match(f("could not resolve host", "fec/t410"),
               paste0("^rmoriedata could not download fec/t410 from data.rmorie.com: ",
                      "could not resolve host$"))
})

test_that("a damaged cached manifest is fetched again, once, and says so", {
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  p <- file.path(rmoriedata:::.rmd_data_cache_dir(), "manifest.json")
  good <- paste0('{"datasets":[{"key":"db/t","rows":1,"sha256":"', strrep("a", 64),
                 '","meta":{"description":"T"}}]}')
  calls <- 0L
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      calls <<- calls + 1L
      writeLines(good, dest)
      invisible(dest)
    })
  for (damaged in c('{"datasets":[{"key":', "15")) {
    writeLines(damaged, p)
    calls <- 0L
    expect_message(out <- hostcat(),
                   "the cached manifest of data.rmorie.com could not be read")
    expect_identical(out$key, "db/t")
    expect_identical(calls, 1L)
  }
  writeLines('{"datasets":', p)
  expect_message(d <- .rmd_manifest_entry("db/t"), "fetching it again")
  expect_identical(d$key, "db/t")
  # a manifest that is damaged as it arrives is an error in words, not a parser's
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) writeLines("{", dest))
  expect_error(hostcat(refresh = TRUE),
               "data.rmorie.com sent a manifest that could not be read")
})

test_that("hostload checks refresh as hostcat does, before any request", {
  testthat::local_mocked_bindings(
    .rmd_data_get = function(...) stop("no request expected"),
    .rmd_manifest_entry = function(...) stop("no manifest expected"))
  for (bad in list(NA, "yes", NULL, c(TRUE, FALSE), 1)) {
    expect_error(hostload("db/t", refresh = bad), "`refresh` must be TRUE or FALSE",
                 fixed = TRUE)
    expect_error(hostcat(refresh = bad), "`refresh` must be TRUE or FALSE", fixed = TRUE)
    expect_error(mdload("arsau_2023_uof_main_records", refresh = bad),
                 "`refresh` must be TRUE or FALSE.", fixed = TRUE)
  }
})

# A csv.gz written byte for byte, as the service serves it.
hub_gz <- function(bytes) {
  f <- withr::local_tempfile(fileext = ".csv.gz", .local_envir = parent.frame())
  con <- gzfile(f, "wb")
  writeBin(bytes, con)
  close(con)
  f
}

test_that("hostload returns what the file holds (N9)", {
  b <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(
    "Code,Offence Description,% of All,txt,note,empty,lg,num,big,hex,frac\r\n",
    "046,Theft under,1.5,NA,\"a, b\",,TRUE,0.25,3000000000,0x1A,1.50\r\n",
    "120,\"Assault\r\nwith a weapon\",2,x,\"say \"\"hi\"\"\",,FALSE,1e-05,2,1,2\r\n",
    "871,caf\xc3\xa9,,,,,,-3,4,2,3\r\n")))
  d <- .rmd_read_hosted(hub_gz(b))
  # names as written, the byte-order mark dropped
  expect_identical(names(d), c("Code", "Offence Description", "% of All", "txt", "note",
                               "empty", "lg", "num", "big", "hex", "frac"))
  # a code keeps its leading zero; the text "NA" is a value; an empty text field is ""
  expect_identical(d$Code, c("046", "120", "871"))
  expect_identical(d$txt, c("NA", "x", ""))
  expect_identical(d$`% of All`, c(1.5, 2, NA))
  # quoted commas, quotes and line breaks (a CRLF inside a quoted field reads as \n)
  expect_identical(d$note, c("a, b", "say \"hi\"", ""))
  expect_identical(d$`Offence Description`[2L], "Assault\nwith a weapon")
  # a column with no value is logical NA; TRUE/FALSE is logical
  expect_identical(d$empty, rep(NA, 3L))
  expect_identical(d$lg, c(TRUE, FALSE, NA))
  # numbers only when written as R writes them ("1.50" is formatting): "0x1A" keeps
  # its column text
  expect_identical(d$num, c(0.25, 1e-05, -3))
  expect_identical(d$big, c(3e9, 2, 4))
  expect_identical(d$hex, c("0x1A", "1", "2"))
  expect_identical(d$frac, c(1.5, 2, 3))
  # UTF-8 text is marked UTF-8 whatever the locale
  expect_identical(Encoding(d$`Offence Description`[3L]), "UTF-8")
  expect_identical(charToRaw(d$`Offence Description`[3L]),
                   as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)))
  # other spellings of numbers stay text, every character kept
  for (v in c("+3", "007", "1e5", "Inf", "NaN", "-0", " 4", ".5", "1.",
              "1234567890123456", "0.300000000000000044")) {
    got <- .rmd_read_hosted(hub_gz(charToRaw(paste0("a\n", v, "\n1\n"))))$a
    expect_identical(got, c(v, "1"), info = v)
  }
  expect_identical(.rmd_read_hosted(hub_gz(charToRaw(
    "a\n6.0\n0.10\n-12.500\n0.30000000000000004\n123456789012345\n")))$a,
    c(6, 0.1, -12.5, 0.1 + 0.2, 123456789012345))
  # bytes that are not UTF-8 are marked "bytes", not mislabelled
  x <- .rmd_read_hosted(hub_gz(c(charToRaw("a\n"), as.raw(c(0x61, 0xff)), as.raw(10))))$a
  expect_identical(Encoding(x), "bytes")
  # a record with a field too many or too few is an error
  expect_error(.rmd_read_hosted(hub_gz(charToRaw("a,b\n1,2\n3\n"))),
               "record 3 has 1 fields, the header 2")
})

test_that("hostload agrees with rmoriebricklayer's reader on a plain table", {
  rd <- get0(".bl_read_csv_gz", asNamespace("rmoriebricklayer"), inherits = FALSE)
  skip_if(is.null(rd), "this rmoriebricklayer has no .bl_read_csv_gz()")
  # names R keeps as they are, numbers as R writes them, text without leading zeros
  f <- hub_gz(charToRaw(paste0("id,name,rate,flag,when\n",
                               "1,THEFT,0.25,TRUE,2024-01-01\n",
                               "2,\"BATTERY, SIMPLE\",-3.5,FALSE,2024-01-02\n",
                               "3,ROBBERY,,,2024-01-03\n")))
  a <- .rmd_read_hosted(f)
  b <- rd(f)
  expect_identical(lapply(a, unname), lapply(b, unname))
  expect_identical(names(a), names(b))
})

test_that("hostload goes through the new reader and keeps a code's zero", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  served <- hub_gz(charToRaw("ISSUING CODE,n\n046,1\n120,2\n"))
  m <- rmoriebricklayer::tojs(list(datasets = list(list(
    key = "justice_open/t", rows = 2, sha256_gz = rmoriebricklayer::sha256file(served)))),
    auto_unbox = TRUE)
  testthat::local_mocked_bindings(.rmd_data_get = function(path, dest, timeout = 600) {
    if (path == "/manifest.json") writeLines(m, dest) else file.copy(served, dest)
    invisible(dest)
  })
  d <- hostload("justice_open/t")
  expect_identical(d, data.frame(`ISSUING CODE` = c("046", "120"), n = 1:2,
                                 check.names = FALSE))
})

test_that("a cached, verified table loads offline when the manifest is old (N14)", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  real_get <- .rmd_data_get
  dig <- rmoriebricklayer::sha256file(hub_fixture(list())$served)
  fx <- hub_fixture(list(sha256_gz = dig))
  st <- new.env()
  hub_mock(fx, st)
  expect_identical(hostload("statcan_health/tbl_1")$VALUE, c(1L, 2L))
  p <- file.path(rmoriedata:::.rmd_data_cache_dir(), "manifest.json")
  Sys.setFileTime(p, Sys.time() - 2 * 86400)
  rm(list = ls(rmoriedata:::.rmd_stale), envir = rmoriedata:::.rmd_stale)
  # offline: every request fails in the transport
  testthat::local_mocked_bindings(
    .rmd_data_get = real_get,
    .rmd_dl = function(url, ...) stop("bldl: ", url, ": refused: could not resolve"))
  expect_message(d <- hostload("statcan_health/tbl_1"),
                 "manifest of data.rmorie.com could not be refreshed .*using the copy")
  expect_identical(d$VALUE, c(1L, 2L))
  # a copy that fails the digest is never served, offline or not
  hub_tamper("statcan_health/tbl_1")
  expect_error(suppressMessages(hostload("statcan_health/tbl_1")),
               "^hostload\\(\\) could not download manifest.json: https://")
  # an explicit refresh needs the network
  expect_error(hostcat(refresh = TRUE),
               paste0("^hostcat\\(\\) could not download manifest.json: ",
                      "https://data.example.test/manifest.json: refused"))
  rm(list = ls(rmoriedata:::.rmd_stale), envir = rmoriedata:::.rmd_stale)
})

test_that("a cached copy is checked under the download lock", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  dig <- rmoriebricklayer::sha256file(hub_fixture(list())$served)
  fx <- hub_fixture(list(sha256_gz = dig))
  st <- new.env()
  hub_mock(fx, st)
  hostload("statcan_health/tbl_1")
  seen <- character()
  real <- .rmd_locked
  testthat::local_mocked_bindings(.rmd_locked = function(lock, label, fn) {
    seen <<- c(seen, basename(lock))
    real(lock, label, fn)
  })
  hostload("statcan_health/tbl_1")
  # the table under its own lock; the manifest it is checked against under the
  # manifest's (update 51)
  expect_identical(sum(seen == "statcan__health_-tbl__1.csv.gz.lock"), 1L)
  expect_setequal(seen, c("statcan__health_-tbl__1.csv.gz.lock", "manifest.json.lock"))
})

test_that("a stalled lock holder ends the wait with an error, not never", {
  lock <- withr::local_tempfile(fileext = ".lock")
  withr::local_options(rmoriedata.lockwait = 0.3)
  # flock() locks are per open file: the inner call, on a second descriptor, is
  # refused as another session would be, and nothing grows meanwhile
  t0 <- Sys.time()
  expect_error(suppressMessages(.rmd_locked(lock, "db/t", function() {
    .rmd_locked(lock, "db/t", function() "inner")
  })), "another R session has held the download of db/t for 0.3 seconds without the")
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 5)
  withr::local_options(rmoriedata.lockwait = -1)
  expect_error(.rmd_locked(lock, "db/t", function() 1), "rmoriedata.lockwait must be")
})

test_that("text that is not valid is refused before it reaches a pattern", {
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]))
  expect_error(hostload("db/\xff\xfe"), "`key` holds text that is not valid")
  expect_error(cihiget("\xff\xfe"), "`which` holds text that is not valid")
  expect_error(mdask("\xff\xfe"), "`question` holds text that is not valid")
})

test_that("a manifest not shaped as one is refused in words (F02)", {
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  body <- NULL
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      if (path != "/manifest.json") stop("no table request expected")
      writeLines(body, dest)
      invisible(dest)
    })
  for (body in c('{"datasets":"x"}', '{"datasets":[1,2]}', "[1,2]", "[]",
                 '{"datasets":{"a":{"key":"db/t"}}}', '{"tables":[]}')) {
    unlink(p)
    expect_error(hostcat(),
                 "^data.rmorie.com sent a manifest that could not be read",
                 info = body)
    unlink(p)
    expect_error(hostload("db/t"),
                 "^data.rmorie.com sent a manifest that could not be read",
                 info = body)
  }
  # an empty catalogue is a manifest; `meta` that is not an object names nothing
  body <- '{"datasets":[]}'
  expect_identical(nrow(hostcat(refresh = TRUE)), 0L)
  body <- '{"datasets":[{"key":"db/t","meta":"x","source":"bq.t"}]}'
  expect_identical(hostcat(refresh = TRUE)$name, "bq.t")
})

test_that("rows that are not a count are NA, with no warning (F03)", {
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test")
  rows <- c('"many"', "1e12", "-1", "2.5", '"12"', "12", "null", "[1,2]")
  ent <- sprintf('{"key":"db/t%d","rows":%s}', seq_along(rows), rows)
  testthat::local_mocked_bindings(
    .rmd_data_get = function(path, dest, timeout = 600) {
      writeLines(paste0('{"datasets":[', paste(ent, collapse = ","), "]}"),
                 dest)
      invisible(dest)
    })
  expect_no_warning(out <- hostcat())
  expect_identical(out$rows, c(NA, NA, NA, NA, 12L, 12L, NA, NA))
})

test_that("refresh = TRUE fetches the manifest or stops (F04)", {
  withr::local_envvar(MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  withr::local_options(rmoriedata.cache_dir = withr::local_tempdir())
  real_get <- .rmd_data_get
  dig <- rmoriebricklayer::sha256file(hub_fixture(list())$served)
  st <- new.env()
  hub_mock(hub_fixture(list(sha256_gz = dig)), st)
  expect_identical(hostload("statcan_health/tbl_1")$VALUE, c(1L, 2L))
  # a fresh cached manifest is fetched again on refresh = TRUE
  st$calls <- NULL
  expect_identical(hostload("statcan_health/tbl_1", refresh = TRUE)$VALUE,
                   c(1L, 2L))
  expect_true("/manifest.json" %in% st$calls)
  p <- file.path(.rmd_data_cache_dir(), "manifest.json")
  Sys.setFileTime(p, Sys.time() - 2 * 86400)
  rm(list = ls(.rmd_stale), envir = .rmd_stale)
  testthat::local_mocked_bindings(
    .rmd_data_get = real_get,
    .rmd_dl = function(url, ...) stop("bldl: ", url, ": could not resolve"))
  for (call in list(quote(hostload("statcan_health/tbl_1", refresh = TRUE)),
                    quote(hostcat(refresh = TRUE)))) {
    expect_error(eval(call),
                 paste0("could not download manifest.json: .*; with ",
                        "refresh = TRUE the cached manifest is not used$"))
  }
  # without refresh the day-old copy still serves, with its message
  expect_message(d <- hostload("statcan_health/tbl_1"),
                 "could not be refreshed")
  expect_identical(d$VALUE, c(1L, 2L))
  rm(list = ls(.rmd_stale), envir = .rmd_stale)
})

test_that("a refresh that failed for one cache folder does not hold back another's", {
  rm(list = ls(.rmd_stale), envir = .rmd_stale)
  withr::defer(rm(list = ls(.rmd_stale), envir = .rmd_stale))
  fx <- hub_fixture(list())
  ps <- file.path(withr::local_tempdir(), c("a", "b"), "manifest.json")
  when <- Sys.time() - 2 * 86400
  for (p in ps) {
    dir.create(dirname(p))
    writeLines(fx$manifest, p)
    Sys.setFileTime(p, when)
  }
  tries <- 0
  testthat::local_mocked_bindings(.rmd_data_get = function(...) {
    tries <<- tries + 1
    stop("offline")
  })
  expect_message(.rmd_manifest_get(ps[1], FALSE), "could not be refreshed")
  expect_message(.rmd_manifest_get(ps[2], FALSE), "could not be refreshed")
  expect_identical(tries, 2)
  # the same copy again within five minutes: not tried again
  expect_no_message(.rmd_manifest_get(ps[2], FALSE))
  expect_identical(tries, 2)
})

test_that("a manifest mark the package does not know is a table not served", {
  withr::local_envvar(MORIE_HOSTED_KEY = NA, MORIE_DATA_URL = "https://data.example.test",
                      XDG_CONFIG_HOME = withr::local_tempdir())
  d <- withr::local_tempdir()
  dir.create(file.path(d, "hosted"))
  withr::local_options(rmoriedata.cache_dir = d)
  testthat::local_mocked_bindings(
    .rmd_data_get = function(...) stop("no request expected", call. = FALSE)
  )
  closed <- c('"access":["closed"]', '"access":["open"]', '"access":"closed"',
              '"access":""', '"access":null', '"access":1', '"access":true',
              '"access":["open","public"]', '"access":{"is":"open"}', '"access":" open"',
              '"restricted":"true"', '"restricted":"false"', '"restricted":1',
              '"restricted":0', '"restricted":null', '"restricted":true',
              '"restricted":[false]',
              '"meta":{"access":["closed"]}', '"meta":{"restricted":"yes"}',
              '"meta":[{"access":"closed"}]')
  open <- c('"access":"open"', '"access":"Public"', '"access":"OPEN"',
            '"restricted":false', '"meta":{"access":"open","restricted":false}',
            '"meta":"a description"', '"rows":1')
  ent <- function(k, mark) sprintf('{"key":"db/%s",%s}', k, mark)
  writeLines(paste0('{"datasets":[',
                    paste(c(ent(paste0("c", seq_along(closed)), closed),
                            ent(paste0("o", seq_along(open)), open),
                            '{"key":5}', '{"key":["db/k"]}', '{"key":null}',
                            # a key listed again, closed: not served at all
                            '{"key":"db/twice"}', '{"key":"db/twice","access":"closed"}',
                            # listed twice, differently: a damaged manifest
                            '{"key":"db/odd","rows":1}', '{"key":"db/odd","rows":2}'),
                          collapse = ","), "]}"),
             file.path(d, "hosted", "manifest.json"))
  expect_message(k <- hostcat()$key, "^25 tables are not served")
  expect_identical(k, c(paste0("db/o", seq_along(open)), "db/odd", "db/odd"))
  for (x in c(paste0("db/c", seq_along(closed)), "db/twice")) {
    expect_error(hostload(x), paste0(x, " is not served by data.rmorie.com"),
                 fixed = TRUE)
  }
  expect_error(hostload("db/odd"), "lists db/odd 2 times, not all the same")
})

test_that("a services document in another shape names no address", {
  withr::local_envvar(MORIE_DATA_URL = NA)
  svc <- NULL
  testthat::local_mocked_bindings(.rmd_services_data = function() svc)
  expect_identical(.rmd_data_url(), "https://data.rmorie.com")
  svc <- list(mode = "key", base_url = "https://data.example.test")
  expect_identical(.rmd_data_url(), "https://data.example.test")
  bad <- list(list(mode = "key", base_url = list("https://data.example.test")),
              list(mode = "key", base_url = c("https://a.test", "https://b.test")),
              list(mode = "key", base_url = NA_character_),
              list(mode = "key", base_url = 5),
              list(mode = "key", base_url = "data.example.test"),
              list(mode = list("key"), base_url = "https://data.example.test"),
              list(mode = "off", base_url = "https://data.example.test"),
              "https://data.example.test")
  for (svc in bad) {
    expect_error(.rmd_data_url(), "not available right now \\(see https://www.rmorie")
  }
  svc <- list(mode = "off", request_access = list("x", "y"))
  expect_error(.rmd_data_url(), "(see https://www.rmorie.com/access/)", fixed = TRUE)
})
