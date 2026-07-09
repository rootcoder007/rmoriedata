suppressMessages({ library(rmoriebricklayer) })
canon <- "/mnt/nvme/rootcoderfiles/data/datasets/oc/CPADS/2021-2022/cpads-2021-2022-pumf2.csv"
prov_out <- "/tmp/cpads_data_provenance.json"
fx_out   <- "/tmp/cpads_pumf_synthetic.csv"
reader <- if (requireNamespace("data.table", quietly=TRUE)) function(p) data.table::fread(p, data.table=FALSE, colClasses="character") else function(p) utils::read.csv(p, check.names=FALSE, colClasses="character")
real <- reader(canon)
cat("real:", nrow(real), "x", ncol(real), "\n")
CAP <- 300L
mk_col <- function(name, x) {
  if (name == "SEQID") return(list(type="sequence", from=1L))
  tb <- sort(table(x), decreasing=TRUE)
  lv <- names(tb); w <- as.integer(tb)
  if (length(lv) > CAP) { keep <- seq_len(CAP); lv <- lv[keep]; w <- w[keep] }
  # numeric-looking? keep values as-is (strings ok for sample())
  list(type="sample", values=as.list(lv), weights=as.list(w))
}
cols <- setNames(lapply(names(real), function(n) mk_col(n, real[[n]])), names(real))
recipe <- list(seed=20260709L, n_rows=500L, columns=cols)
prov <- list(
  schema_version="1.0",
  captured_at_utc="2026-07-09T03:44:31Z",
  captured_by="vsruhela@proton.me (rootcoder-reproducibility/1.0)",
  dataset=list(package_slug="canadian-postsecondary-alcohol-and-drug-survey",
    package_uuid="736fa9b2-62e4-4e31-aea4-51869605b363",
    catalogue_page="https://open.canada.ca/data/en/dataset/736fa9b2-62e4-4e31-aea4-51869605b363",
    ckan_api_endpoint="https://open.canada.ca/data/api/3/action/package_show?id=736fa9b2-62e4-4e31-aea4-51869605b363",
    publisher="Health Canada / Statistics Canada",
    source_system="CPADS 2021-2022 Public Use Microdata File",
    licence_name="Open Government Licence - Canada", licence_short="OGL-Canada"),
  resource=list(name="CPADS 2021-2022 PUMF", format="CSV", language="en",
    resource_uuid="d2639429-c304-45a6-90b3-770562f4d46d",
    filename="cpads-2021-2022-pumf2.csv",
    direct_url="https://open.canada.ca/data/en/datastore/dump/d2639429-c304-45a6-90b3-770562f4d46d",
    size_bytes=as.integer(file.size(canon)),
    sha256=sha256_file(canon),
    row_count_data_rows=nrow(real), header_row_present=TRUE),
  wayback=list(captured_at_utc="2026-07-09T03:49:35Z",
    catalogue_page_snapshot="https://web.archive.org/web/20260709034919/https://open.canada.ca/data/en/dataset/736fa9b2-62e4-4e31-aea4-51869605b363",
    csv_snapshot="submitted 2026-07-09 (async)",
    data_dictionary_snapshot="submitted 2026-07-09 (async)"),
  schema=list(expected_columns=as.list(names(real)),
    n_expected_columns=ncol(real), synthetic_recipe=recipe),
  fallback_chain=list("ckan_resolve","direct_url","wayback","synthetic"))
writeLines(jsonlite::toJSON(prov, auto_unbox=TRUE, pretty=TRUE, null="null"), prov_out)
cat("provenance written:", prov_out, " bytes=", file.size(prov_out), "\n")
res <- make_synthetic_csv(recipe, fx_out, n_rows=500L)
cat("fixture:", res$rows, "rows, seed", res$seed, " bytes=", file.size(fx_out), " cols=", ncol(utils::read.csv(fx_out, check.names=FALSE, nrows=1)), "\n")
