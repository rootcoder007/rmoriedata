# rmoriebricklayer 1.0.0 renamed its functions; 0.5.1, the release before it on CRAN,
# has the older names. .rmd_bl("fromjs") is the 1.0.0 function, else its 0.5.1
# equivalent (same arguments, in the same order); what 0.5.1 lacks (signing in,
# language models, downloads that carry the data key) stops with a message naming
# the release that has it.
.rmd_bl_old <- c(fromjs = "bricklayer_json_from_json", sha256file = "sha256_file",
                 csha256 = "core_sha256", cpsvrf = "capsule_verify",
                 blfetch = "bricklayer_fetch", rndbytes = "random_bytes")

.rmd_bl <- function(name) {
  ex <- .rmd_bl_exports()
  if (name %in% ex) return(.rmd_bl_get(name))
  old <- unname(.rmd_bl_old[name])
  if (!is.na(old) && old %in% ex) return(.rmd_bl_get(old))
  # a development build between the rename and the old names' return can report 1.0.0 and
  # still lack a name, so the message names the function as well as the release
  stop(sprintf(paste("this needs rmoriebricklayer 1.0.0 or later, a release with %s()",
                     "(installed: %s): %s"),
               name, format(utils::packageVersion("rmoriebricklayer")),
               "install.packages(\"rmoriebricklayer\")"), call. = FALSE)
}

# the installed rmoriebricklayer's exports, and one of its functions: named so a test can
# stand in any release without depending on the one installed
.rmd_bl_exports <- function() getNamespaceExports("rmoriebricklayer")
.rmd_bl_get <- function(name) getExportedValue("rmoriebricklayer", name)

# R CMD check before R 4.6 counts an Imports package as used only through `::` or an
# import, not through getExportedValue(); yoy() has the same name in 0.5.1 and 1.0.0
.rmd_bl_ref <- function() rmoriebricklayer::yoy

# The note shown when rmoriedata is attached with a rmoriebricklayer older than 1.0.0: an
# install that already had 0.5.1 keeps it, since it meets the minimum.
.rmd_bl_note <- function(v) {
  if (v >= "1.0.0") return(NULL)
  sprintf(paste0("rmoriedata: rmoriebricklayer %s is installed; signing in, mdask() and ",
                 "keyed downloads need 1.0.0:\n  install.packages(\"rmoriebricklayer\")"),
          format(v))
}
