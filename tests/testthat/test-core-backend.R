# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("morie_core_sha256 matches the FIPS 180-4 standard vectors", {
  expect_equal(morie_core_sha256(""),
               "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
  expect_equal(morie_core_sha256("abc"),
               "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  expect_equal(morie_core_sha256(charToRaw("abc")), morie_core_sha256("abc"))
})

test_that("rmoriedata uses the SAME shared core as rmoriebricklayer (not a copy)", {
  # If LinkingTo resolved to the shared kernels, these are byte-identical.
  expect_equal(morie_core_sha256("provenance"),
               rmoriebricklayer::core_sha256("provenance"))
  expect_equal(morie_core_mean(c(2, 4, 4, 4, 5, 5, 7, 9)),
               rmoriebricklayer::core_mean(c(2, 4, 4, 4, 5, 5, 7, 9)))
})

test_that("morie_core_mean matches base R", {
  expect_equal(morie_core_mean(1:10), mean(1:10))
})
