# SPDX-License-Identifier: AGPL-3.0-or-later
#' rmoriedata: Bundled datasets for rmorie
#'
#' Open data fixtures for the rmorie package
#' (https://github.com/rootcoder007/rmorie), with the functions that read
#' them: [morie_data_catalog()] lists the bundled tables and
#' [morie_data_load()] loads one; [load_siu_reports()],
#' [load_chicago_data()], [load_cihi_data_tables()] and [fetch_cihi_table()]
#' read their datasets, [morie_data_verify()] checks the bundle's
#' checksums; [morie_data_hosted_login()],
#' [morie_data_hosted_catalog()] and [morie_data_hosted_load()] reach the
#' tables served at data.rmorie.com; [ask()] asks a language model about
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
