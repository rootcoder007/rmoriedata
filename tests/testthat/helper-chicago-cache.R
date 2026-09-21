# A throwaway cache dir for the Chicago loader, so no test writes to
# the user's home; every test file sees this helper.
local_chicago_cache <- function(env = parent.frame()) {
  d <- file.path(tempfile("cache"), "rmoriedata")
  dir.create(d, recursive = TRUE)
  testthat::local_mocked_bindings(.rmd_cache_dir = function() d,
                                  .package = "rmoriedata", .env = env)
  d
}
