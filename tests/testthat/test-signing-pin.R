test_that("the shipped signing key matches the root pinned in code", {
  pub <- rmoriedata:::.rmoriedata_json("_signing_key.json",
                                       "bricklayer_public_key")
  expect_identical(as.character(pub$root), rmoriedata:::.rmoriedata_signing_root)
  expect_identical(as.character(pub$pub_seed),
                   rmoriedata:::.rmoriedata_signing_seed)
})

test_that("a re-signed store with a foreign key is refused", {
  skip_if_old_bricklayer()
  skip_if_not_installed("rmoriebricklayer")
  src <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempdir(), "rd_forged")
  dir.create(tmp, showWarnings = FALSE)
  file.copy(list.files(src, full.names = TRUE), tmp, overwrite = TRUE)
  key <- rmoriebricklayer::pqckg(height = 2)
  man <- file.path(tmp, "_checksums.csv")
  bytes <- readBin(man, "raw", n = file.size(man))
  sig <- rmoriebricklayer::cpssign(.rmd_bl("csha256")(bytes),
                                        key)
  writeLines(rmoriebricklayer::tojs(unclass(sig),
                                                       auto_unbox = TRUE),
             file.path(tmp, "_checksums.sig"))
  writeLines(rmoriebricklayer::tojs(
    unclass(rmoriebricklayer::signpubkey(key)), auto_unbox = TRUE),
    file.path(tmp, "_signing_key.json"))
  op <- options(rmoriedata.store = tmp)
  rmoriedata:::.rmoriedata_reset_cache()
  expect_error(rmoriedata::mdverify(),
               "does not match the root pinned")
  options(op)
  rmoriedata:::.rmoriedata_reset_cache()
})

test_that("every table loads its declared rows in a C locale", {
  old_ctype <- Sys.getlocale("LC_CTYPE")
  old_collate <- Sys.getlocale("LC_COLLATE")
  Sys.setlocale("LC_CTYPE", "C")
  Sys.setlocale("LC_COLLATE", "C")
  rmoriedata:::.rmoriedata_reset_cache()
  cat_ <- rmoriedata::mdcat()
  cat_ <- cat_[cat_$kind == "table", ]
  short <- 0L
  for (i in seq_len(nrow(cat_))) {
    d <- rmoriedata::mdload(cat_$slug[i])
    if (nrow(d) != cat_$n_rows[i]) short <- short + 1L
  }
  Sys.setlocale("LC_CTYPE", old_ctype)
  Sys.setlocale("LC_COLLATE", old_collate)
  rmoriedata:::.rmoriedata_reset_cache()
  expect_equal(short, 0L)
})
