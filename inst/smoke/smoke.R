# Clean-user smoke for rmoriedata: the exported entry points run for real in an empty HOME.
tree <- Sys.getenv("MORIE_SMOKE_TREE", "")
if (nzchar(tree)) suppressPackageStartupMessages(pkgload::load_all(tree, quiet = TRUE)) else suppressPackageStartupMessages(library(rmoriedata))
home <- tempfile("rmd-smoke-"); dir.create(home); setwd(home)
Sys.setenv(HOME = home, XDG_CONFIG_HOME = file.path(home, "cfg"))
key <- Sys.getenv("MORIE_SMOKE_KEY", "")
Sys.unsetenv("MORIE_HOSTED_KEY")  # the key reaches the hub only through morie_data_hosted_login()
options(timeout = 600, rmoriedata.cache_dir = file.path(home, "cache"))
check <- function(cond, what) if (!isTRUE(cond)) stop(what, call. = FALSE)
cases <- list(
  catalog = function() { d <- morie_data_catalog(); check(is.data.frame(d) && nrow(d) > 10, "catalog") },
  load_every_slug = function() {
    d <- morie_data_catalog()
    for (s in d$slug[d$kind == "table"]) { x <- morie_data_load(s); check(is.data.frame(x) && nrow(x) > 0, paste("slug", s)) }
    for (s in d$slug[d$kind == "dictionary"]) check(!is.null(morie_data_dictionary(s)), paste("dictionary", s))
  },
  verify = function() { v <- morie_data_verify(); check(is.data.frame(v) && nrow(v) > 100 && all(v$ok) && isTRUE(attr(v, "signature")), "morie_data_verify: every file must match its SHA-256 and the signature must hold") },
  dictionary = function() { d <- morie_data_dictionary(morie_data_catalog()$slug[1]); check(!is.null(d), "dictionary") },
  hosted = function() {
    if (!nzchar(key)) { check(inherits(try(morie_data_hosted_catalog(), silent = TRUE), "try-error"), "no key must error clearly"); return(message("  hosted: SKIP (no key)")) }
    check(identical(morie_data_hosted_login(token = key, open_browser = FALSE), key), "login(token=) must return the key")
    check(file.exists(file.path(home, "cfg", "morie", "credentials.json")), "login must write the shared credentials file")
    cat_ <- morie_data_hosted_catalog(); check(nrow(cat_) > 100 && "chicago_crime/incidents" %in% cat_$key, "hosted catalog")
    df <- morie_data_hosted_load("fec_cm_2020/fec_cm_2020"); check(nrow(df) > 1000, "hosted load")
  },
  ask = function() {
    if (!nzchar(key)) {
      check(grepl("morie_data_hosted_login", ask("hello"), fixed = TRUE), "no key: ask must say how to sign in")
      return(message("  ask: SKIP (no key)"))
    }
    morie_data_hosted_login(token = key, open_browser = FALSE)
    a <- ask("Reply with the single word pong.", model = "gpt-oss-120b:cf")
    if (grepl("429", a, fixed = TRUE)) { Sys.sleep(45); a <- ask("Reply with the single word pong.", model = "gpt-oss-120b:cf") }
    check(nzchar(trimws(a)) && !grepl("morie_data_hosted_login", a, fixed = TRUE), paste("ask:", a))
  },
  dp = function() { x <- morie_dp_laplace_count(10, epsilon = 1); check(is.numeric(x), "dp") }
)
exports <- getNamespaceExports("rmoriedata")
failed <- 0L
for (n in names(cases)) {
  out <- tryCatch({ cases[[n]](); "OK" }, error = function(e) { failed <<- failed + 1L; paste("FAIL", substr(conditionMessage(e), 1, 400)) })
  cat(sprintf("[%s] %s\n", substr(out, 1, 4), n)); if (startsWith(out, "FAIL")) cat("      ", out, "\n")
}
cat(sprintf("\nsmoke (rmoriedata): %d ok, %d failed; %d exports\n", length(cases) - failed, failed, length(exports)))
quit(status = if (failed) 1L else 0L)
