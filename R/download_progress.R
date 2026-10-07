# Downloads go through rmoriebricklayer's checked transport (libcurl in C++): https only,
# public hosts only, no file://, no cross-scheme redirects, a byte cap, and the same live
# progress bar as morie, rmorie and rmoriebricklayer (options(morie.quiet = TRUE) silences
# it). The curated-data path attaches the MORIE key as a bearer header, which is exactly the
# request that must never reach an unvalidated URL; an earlier copy of the progress loop
# here used base R url() and accepted any scheme.
.rmd_dl <- function(url, dest, headers = NULL, label = basename(dest),
                    size = NULL, timeout = 3600, quiet = NULL, tty = NULL) {
  rmoriebricklayer::bricklayer_download(url, dest, headers = headers, label = label,
                                        size = size, timeout = timeout, quiet = quiet,
                                        tty = tty, allow_file = FALSE)
}
