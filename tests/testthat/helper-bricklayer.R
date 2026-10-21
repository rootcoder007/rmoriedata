# Signing in, language models and keyed downloads need rmoriebricklayer 1.0.0; with
# 0.5.1 (the release before it on CRAN) rmoriedata runs without them and these tests
# are skipped.
skip_if_old_bricklayer <- function() {
  testthat::skip_if(utils::packageVersion("rmoriebricklayer") < "1.0.0",
                    "needs rmoriebricklayer 1.0.0 or later")
}
