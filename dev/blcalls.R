# Lists every reference this package makes to rmoriebricklayer and checks
# each against two bricklayer source trees (the version the package was
# written for and the one it moves to).
#
# Rscript dev/blcalls.R <pkgdir> <bl-new-src> <bl-old-src> [out.tsv]
#
# Status per row:
#   ok          exported (or internal, for :::) in both, same formals, same body
#   behaviour   same formals, body differs (comments and layout ignored)
#   signature   formals differ
#   renamed     gone, with a new name (NEWS of the new version)
#   removed     gone, no new name
#   new         only in the new version
#   unknown     in neither tree
a <- commandArgs(TRUE)
pkg <- a[[1]]
bnew <- a[[2]]
bold <- a[[3]]
out <- if (length(a) >= 4) a[[4]] else ""

renames <- c(
  anltab = "anytab", plotecdf = "plotcdfs", plotsm = "plotmult",
  yoy = "yoychg", rate = "rtcalc", rate_change = "ratechg", share = "shrs"
)

defs <- function(src) {
  fs <- list.files(file.path(src, "R"), "\\.[Rr]$", full.names = TRUE)
  env <- list()
  for (f in fs) {
    ex <- tryCatch(parse(f, keep.source = FALSE), error = function(e) NULL)
    for (e in ex) {
      if (is.call(e) && as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) && is.call(e[[3]]) &&
        identical(as.character(e[[3]][[1]]), "function")) {
        nm <- as.character(e[[2]])
        fn <- e[[3]]
        env[[nm]] <- list(
          formals = paste(deparse(fn[[2]]), collapse = " "),
          body = paste(deparse(fn[[3]]), collapse = "\n")
        )
      }
    }
  }
  env
}
exps <- function(src) {
  ns <- parseNamespaceFile(basename(src), dirname(src))
  ns[["exports"]]
}

dn <- defs(bnew)
do <- defs(bold)
en <- exps(bnew)
eo <- exps(bold)

files <- system2("git", c("-C", pkg, "ls-files"), stdout = TRUE)
files <- files[!grepl("^(docs/|.*\\.(rds|rda|RData|parquet|sqlite|gz|png|jpg|pdf|svg|xz|zip|so|o)$)", files)]
rx <- "rmoriebricklayer(:::?)([A-Za-z.][A-Za-z0-9._]*)"
rows <- list()
for (f in files) {
  p <- file.path(pkg, f)
  if (!file.exists(p) || file.info(p)[["isdir"]]) next
  ln <- tryCatch(readLines(p, warn = FALSE, encoding = "UTF-8", skipNul = TRUE),
    error = function(e) character()
  )
  if (!length(ln)) next
  hit <- grep(rx, ln, perl = TRUE, useBytes = TRUE)
  for (i in hit) {
    m <- regmatches(ln[i], gregexpr(rx, ln[i], perl = TRUE))[[1]]
    for (s in m) {
      op <- sub(rx, "\\1", s, perl = TRUE)
      fn <- sub(rx, "\\2", s, perl = TRUE)
      rows[[length(rows) + 1]] <- c(f, i, op, fn)
    }
  }
  # importFrom(rmoriebricklayer, a, b)
  hit <- grep("importFrom\\(rmoriebricklayer", ln)
  for (i in hit) {
    fns <- strsplit(sub(".*importFrom\\(rmoriebricklayer,\\s*", "", sub("\\)\\s*$", "", ln[i])), ",\\s*")[[1]]
    for (fn in fns) rows[[length(rows) + 1]] <- c(f, i, "importFrom", gsub("[\"`]", "", fn))
  }
}
if (!length(rows)) {
  cat("no references\n")
  quit(save = "no")
}
t <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
names(t) <- c("file", "line", "op", "fn")
st <- function(fn, op) {
  inn <- if (op == ":::") !is.null(dn[[fn]]) else fn %in% en
  ino <- if (op == ":::") !is.null(do[[fn]]) else fn %in% eo
  if (!inn && !ino) {
    return("unknown")
  }
  if (!inn) {
    return(if (fn %in% names(renames)) paste0("renamed->", renames[[fn]]) else "removed")
  }
  if (!ino) {
    return("new")
  }
  a1 <- dn[[fn]]
  b1 <- do[[fn]]
  if (is.null(a1) || is.null(b1)) {
    return("ok(not a plain function)")
  }
  if (!identical(a1[["formals"]], b1[["formals"]])) {
    return("signature")
  }
  if (!identical(a1[["body"]], b1[["body"]])) {
    return("behaviour")
  }
  "ok"
}
t[["status"]] <- mapply(st, t[["fn"]], t[["op"]], USE.NAMES = FALSE)
t[["fn"]][t[["fn"]] == ""] <- "(package)"
if (nzchar(out)) write.table(t, out, sep = "\t", quote = FALSE, row.names = FALSE)
cat("rows:", nrow(t), "\n")
print(table(t[["status"]]))
cat("\nby function:\n")
agg <- aggregate(line ~ fn + op + status, data = transform(t, line = 1), FUN = length)
print(agg[order(agg[["status"]], agg[["fn"]]), ], row.names = FALSE)
cat("\nnon-ok rows:\n")
print(t[!startsWith(t[["status"]], "ok"), ], row.names = FALSE)
