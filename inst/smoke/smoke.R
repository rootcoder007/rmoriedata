# Clean-user smoke for rmoriedata: the exported entry points run for real in an empty HOME.
tree <- Sys.getenv("MORIE_SMOKE_TREE", "")
if (nzchar(tree)) suppressPackageStartupMessages(pkgload::load_all(tree, quiet = TRUE)) else suppressPackageStartupMessages(library(rmoriedata))
home <- tempfile("rmd-smoke-"); dir.create(home); setwd(home)
Sys.setenv(HOME = home, XDG_CONFIG_HOME = file.path(home, "cfg"))
key <- Sys.getenv("MORIE_SMOKE_KEY", "")
Sys.unsetenv("MORIE_HOSTED_KEY")  # the key reaches the hub only through hostlogin()
options(timeout = 600, rmoriedata.cache_dir = file.path(home, "cache"))
check <- function(cond, what) if (!isTRUE(cond)) stop(what, call. = FALSE)
cases <- list(
  catalog = function() { d <- mdcat(); check(is.data.frame(d) && nrow(d) > 10, "catalog") },
  load_every_slug = function() {
    d <- mdcat()
    for (s in d$slug[d$kind == "table"]) { x <- mdload(s); check(is.data.frame(x) && nrow(x) > 0, paste("slug", s)) }
    for (s in d$slug[d$kind == "dictionary"]) check(!is.null(mddict(s)), paste("dictionary", s))
  },
  verify = function() { v <- mdverify(); check(is.data.frame(v) && nrow(v) > 100 && all(v$ok) && isTRUE(attr(v, "signature")), "mdverify: every file must match its SHA-256 and the signature must hold") },
  dictionary = function() { d <- mddict(mdcat()$slug[1]); check(!is.null(d), "dictionary") },
  hosted = function() {
    if (!nzchar(key)) { check(inherits(try(hostcat(), silent = TRUE), "try-error"), "no key must error clearly"); return(message("  hosted: SKIP (no key)")) }
    check(identical(hostlogin(token = key, openbro = FALSE), key), "login(token=) must return the key")
    check(file.exists(file.path(home, "cfg", "morie", "credentials.json")), "login must write the shared credentials file")
    cat_ <- hostcat(); check(nrow(cat_) > 100 && "chicago_crime/incidents" %in% cat_$key, "hosted catalog")
    df <- hostload("fec_cm_2020/fec_cm_2020"); check(nrow(df) > 1000, "hosted load")
  },
  ask = function() {
    # a runner has no language model of its own: with none set up, ask must say how to bring one
    a <- mdask("Reply with the single word pong.")
    check(nzchar(trimws(a)) && (!grepl("could not answer", a, fixed = TRUE) || grepl("bring your own key", a, fixed = TRUE)),
          paste("ask:", a))
  },
  dp = function() { x <- dplapcnt(10, epsilon = 1); check(is.numeric(x), "dp") }
)
exports <- getNamespaceExports("rmoriedata")
failed <- 0L
for (n in names(cases)) {
  out <- tryCatch({ cases[[n]](); "OK" }, error = function(e) { failed <<- failed + 1L; paste("FAIL", substr(conditionMessage(e), 1, 400)) })
  cat(sprintf("[%s] %s\n", substr(out, 1, 4), n)); if (startsWith(out, "FAIL")) cat("      ", out, "\n")
}
cat(sprintf("\nsmoke (rmoriedata): %d ok, %d failed; %d exports\n", length(cases) - failed, failed, length(exports)))
quit(status = if (failed) 1L else 0L)
