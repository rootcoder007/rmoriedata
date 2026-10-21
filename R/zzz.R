# SPDX-License-Identifier: AGPL-3.0-or-later
#' rmoriedata: Bundled datasets for rmorie
#'
#' Open data fixtures for the rmorie package
#' (https://github.com/rootcoder007/rmorie), with the functions that read
#' them: [mdcat()] lists the bundled tables and
#' [mdload()] loads one; [siuload()],
#' [chiload()], [cihitbls()] and [cihiget()]
#' read their datasets, [mdverify()] checks the bundle's
#' checksums; [hostlogin()],
#' [hostcat()] and [hostload()] reach the
#' tables served at data.rmorie.com; [mdask()] asks a language model about
#' the catalogue; and the differential-privacy and k-anonymity helpers
#' release aggregates safely. The raw files are also at
#' `system.file("extdata", package = "rmoriedata")`.
#'
#' @keywords internal
"_PACKAGE"

.onLoad <- function(libname, pkgname) {
  # src/rmoriedata_init.c calls rmbl_* routines that rmoriebricklayer
  # registers via R_RegisterCCallable (LinkingTo). R_GetCCallable only
  # resolves them once the provider's DLL is loaded, which a DESCRIPTION
  # Imports: alone does not do -- so load its namespace (triggering its
  # useDynLib + registration) before any C call.
  requireNamespace("rmoriebricklayer", quietly = TRUE)
}

.onAttach <- function(libname, pkgname) {
  note <- .rmd_bl_note(utils::packageVersion("rmoriebricklayer"))
  if (!is.null(note)) packageStartupMessage(note)
}
