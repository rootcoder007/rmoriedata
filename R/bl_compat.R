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
  if (name %in% ex) return(getExportedValue("rmoriebricklayer", name))
  old <- .rmd_bl_old[name]
  if (!is.na(old) && old %in% ex) return(getExportedValue("rmoriebricklayer", old))
  stop(sprintf("this needs rmoriebricklayer 1.0.0 or later (installed: %s): %s",
               format(utils::packageVersion("rmoriebricklayer")),
               "install.packages(\"rmoriebricklayer\")"), call. = FALSE)
}

# the installed rmoriebricklayer's exports, named so a test can stand in another release
.rmd_bl_exports <- function() getNamespaceExports("rmoriebricklayer")

# The note shown when rmoriedata is attached with a rmoriebricklayer older than 1.0.0: an
# install that already had 0.5.1 keeps it, since it meets the minimum.
.rmd_bl_note <- function(v) {
  if (v >= "1.0.0") return(NULL)
  sprintf(paste0("rmoriedata: rmoriebricklayer %s is installed; signing in, mdask() and ",
                 "keyed downloads need 1.0.0:\n  install.packages(\"rmoriebricklayer\")"),
          format(v))
}
