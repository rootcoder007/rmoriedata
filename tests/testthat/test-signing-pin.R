test_that("the shipped signing key matches the root pinned in code", {
  pub <- rmoriedata:::.rmoriedata_json("_signing_key.json",
                                       "bricklayer_public_key")
  expect_identical(as.character(pub$root), rmoriedata:::.rmoriedata_signing_root)
  expect_identical(as.character(pub$pub_seed),
                   rmoriedata:::.rmoriedata_signing_seed)
})

test_that("a re-signed store with a foreign key is refused", {
  skip_if_not_installed("rmoriebricklayer")
  src <- system.file("extdata", package = "rmoriedata")
  tmp <- file.path(tempdir(), "rd_forged")
  dir.create(tmp, showWarnings = FALSE)
  file.copy(list.files(src, full.names = TRUE), tmp, overwrite = TRUE)
  key <- rmoriebricklayer::pqc_keygen(height = 2)
  man <- file.path(tmp, "_checksums.csv")
  bytes <- readBin(man, "raw", n = file.size(man))
  sig <- rmoriebricklayer::capsule_sign(rmoriebricklayer::core_sha256(bytes), key)
  writeLines(rmoriebricklayer::bricklayer_json_to_json(unclass(sig), auto_unbox = TRUE),
             file.path(tmp, "_checksums.sig"))
  writeLines(rmoriebricklayer::bricklayer_json_to_json(
    unclass(rmoriebricklayer::signing_public_key(key)), auto_unbox = TRUE),
    file.path(tmp, "_signing_key.json"))
  withr::with_options(list(rmoriedata.store = tmp), {
    rmoriedata:::.rmoriedata_reset_cache()
    expect_error(rmoriedata::morie_data_verify(), "does not match the root pinned")
  })
  rmoriedata:::.rmoriedata_reset_cache()
})

test_that("every table loads its declared rows in a C locale", {
  withr::with_locale(c(LC_CTYPE = "C", LC_COLLATE = "C"), {
    rmoriedata:::.rmoriedata_reset_cache()
    cat_ <- rmoriedata::morie_data_catalog()
    cat_ <- cat_[cat_$kind == "table", ]
    short <- 0L
    for (i in seq_len(nrow(cat_))) {
      d <- rmoriedata::morie_data_load(cat_$slug[i])
      if (nrow(d) != cat_$n_rows[i]) short <- short + 1L
    }
    expect_equal(short, 0L)
  })
  rmoriedata:::.rmoriedata_reset_cache()
})
