# SPDX-License-Identifier: AGPL-3.0-or-later
# Session settings the package's results must not follow. Each entry applies one
# setting until the frame `env` ends; `under_settings()` runs a block under each and
# expects what it gives to be identical() to what it gives under the defaults.

hostile_settings <- function() {
  set <- list(
    "scipen -100" = function(env) {
      suppressWarnings(withr::local_options(scipen = -100, .local_envir = env))
    },
    "scipen 100" = function(env) withr::local_options(scipen = 100, .local_envir = env),
    "OutDec ," = function(env) withr::local_options(OutDec = ",", .local_envir = env),
    "warn 2, partial matches" = function(env) {
      withr::local_options(warn = 2, warnPartialMatchDollar = TRUE,
                           warnPartialMatchArgs = TRUE, warnPartialMatchAttr = TRUE,
                           .local_envir = env)
    },
    "digits, width, quotes, encoding" = function(env) {
      withr::local_options(digits = 3, width = 30, max.print = 5, useFancyQuotes = TRUE,
                           nwarnings = 1, encoding = "latin1", .local_envir = env)
    },
    "TZ Pacific/Kiritimati" = function(env) {
      withr::local_envvar(TZ = "Pacific/Kiritimati", .local_envir = env)
    },
    "TZ America/St_Johns" = function(env) {
      withr::local_envvar(TZ = "America/St_Johns", .local_envir = env)
    },
    "LC_ALL C" = function(env) {
      withr::local_locale(.settings_cats(c(LC_CTYPE = "C", LC_COLLATE = "C",
                                           LC_TIME = "C", LC_MONETARY = "C",
                                           LC_MESSAGES = "C")), .local_envir = env)
      withr::local_envvar(LANGUAGE = "en", .local_envir = env)
    }
  )
  # Turkish (dotted and dotless i) and a language whose base-R messages are
  # translated, only where the system has them
  for (loc in c("tr_TR.UTF-8", "fr_FR.UTF-8", "de_DE.UTF-8")) {
    ok <- suppressWarnings(nzchar(Sys.setlocale("LC_CTYPE", loc)))
    Sys.setlocale("LC_CTYPE", .settings_ctype)
    if (ok) {
      set[[paste("LC_ALL", loc)]] <- local({
        l <- loc
        function(env) {
          withr::local_locale(.settings_cats(c(LC_CTYPE = l, LC_COLLATE = l,
                                               LC_TIME = l, LC_MESSAGES = l)),
                              .local_envir = env)
          withr::local_envvar(LANGUAGE = substr(l, 1L, 2L), .local_envir = env)
        }
      })
    }
  }
  set
}

.settings_ctype <- Sys.getlocale("LC_CTYPE")

# The locale categories this system has: Windows has no LC_MESSAGES, and setting it
# there only warns.
.settings_cats <- function(x) {
  if (.Platform$OS.type == "windows") x[names(x) != "LC_MESSAGES"] else x
}

# `block()` under the defaults, then under each setting: identical results.
under_settings <- function(block, label = "") {
  ref <- block()
  for (nm in names(hostile_settings())) {
    got <- local({
      hostile_settings()[[nm]](environment())
      block()
    })
    testthat::expect_identical(got, ref, info = paste(label, "under", nm))
  }
  invisible(ref)
}

# A copy of the installed data store in a temporary folder, named by
# options(rmoriedata.store = ) until `env` ends.
local_store_copy <- function(env = parent.frame()) {
  ed <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(withr::local_tempdir(.local_envir = env), "extdata")
  dir.create(tmp)
  file.copy(list.files(ed, full.names = TRUE, all.files = TRUE, no.. = TRUE), tmp,
            recursive = TRUE)
  withr::local_options(rmoriedata.store = tmp, .local_envir = env)
  withr::defer(rmoriedata:::.rmoriedata_reset_cache(), envir = env)
  rmoriedata:::.rmoriedata_reset_cache()
  tmp
}
