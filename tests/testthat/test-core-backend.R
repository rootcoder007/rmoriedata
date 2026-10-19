# SPDX-License-Identifier: AGPL-3.0-or-later

test_that("mdsha matches the FIPS 180-4 standard vectors", {
  expect_equal(
    mdsha(""),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  )
  expect_equal(
    mdsha("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
  expect_equal(mdsha(charToRaw("abc")), mdsha("abc"))
})

test_that("rmoriedata uses the SAME shared core as rmoriebricklayer (not a copy)", {
  # If LinkingTo resolved to the shared kernels, these are byte-identical.
  expect_equal(
    mdsha("provenance"),
    rmoriebricklayer::csha256("provenance")
  )
  expect_equal(
    mdmean(c(2, 4, 4, 4, 5, 5, 7, 9)),
    rmoriebricklayer::cmn(c(2, 4, 4, 4, 5, 5, 7, 9))
  )
})

test_that("mdmean matches base R", {
  expect_equal(mdmean(1:10), mean(1:10))
})

test_that("mdmean refuses text instead of averaging NA", {
  expect_no_warning(expect_error(mdmean("abc"), "numeric vector"))
  expect_equal(mdmean(c(TRUE, FALSE)), 0.5)
})
