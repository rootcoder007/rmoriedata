# SPDX-License-Identifier: AGPL-3.0-or-later
#' rmoriedata: Bundled datasets for rmorie
#'
#' This package ships fixtures consumed by the rmorie package
#' (https://github.com/rootcoder007/rmorie). It has no exported
#' functions; access the data via
#' `system.file("extdata", "<file>", package = "rmoriedata")`.
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
