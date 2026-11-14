# SPDX-License-Identifier: AGPL-3.0-or-later
#' rmoriedata: Disclosure control for aggregate releases, with open datasets
#'
#' Tools for releasing aggregate statistics safely: differential privacy
#' ([dplapcnt()] and [dplaphist()] for counts, [dpgmean()] for means, with
#' the budget kept by [dpbudget()] and [dpspent()]), checks of k-anonymity
#' and l-diversity ([kanonvrf()], [ldivvrf()]), and cell suppression audited
#' for exact recovery from the margins ([cellsupp()]).
#'
#' Open datasets to use them on come with the package: [mdcat()] lists the
#' bundled tables and [mdload()] loads one; [siuload()], [chiload()],
#' [cihitbls()] and [cihiget()] read their datasets; [mdverify()] checks
#' the bundle's checksums; [hostcat()] and [hostload()] reach the tables
#' served at data.rmorie.com; and [mdask()] asks a language model about the
#' catalogue. The raw files are also at
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
