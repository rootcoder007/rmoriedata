# Decimal text to doubles: correctly rounded, the same on every platform. The
# expected doubles were derived once, independently of R, with Python's float()
# (correctly rounded on every platform): float(s).hex() and the 8 bytes of
# struct.pack(">d", float(s)), typed in here.

# text, the hex float and the 8 bytes of the correctly rounded double
# (h: the halfway case 1 + 2^-53 exactly, which rounds to even, and one digit above)
h <- "1.00000000000000011102230246251565404236316680908203125"
strtod_cases <- data.frame(matrix(c(
  "-8833541.51630376", "-0x1.0d940b0858f77p+23", "c160d940b0858f77",
  "1.239042694", "0x1.3d31e6e913e67p+0", "3ff3d31e6e913e67",
  "3573.71266885", "0x1.beb6ce2ee7741p+11", "40abeb6ce2ee7741",
  "0.30000000000000004", "0x1.3333333333334p-2", "3fd3333333333334",
  "0.1", "0x1.999999999999ap-4", "3fb999999999999a",
  "2.2250738585072011e-308", "0x0.fffffffffffffp-1022", "000fffffffffffff",
  "4.9406564584124654e-324", "0x0.0000000000001p-1022", "0000000000000001",
  "2.4703282292062328e-324", "0x0.0000000000001p-1022", "0000000000000001",
  "1e23", "0x1.52d02c7e14af6p+76", "44b52d02c7e14af6",
  "9007199254740993", "0x1.0000000000000p+53", "4340000000000000",
  "9007199254740995", "0x1.0000000000002p+53", "4340000000000002",
  h, "0x1.0000000000000p+0", "3ff0000000000000",
  sub("5$", "6", h), "0x1.0000000000001p+0", "3ff0000000000001",
  "1.7976931348623157e308", "0x1.fffffffffffffp+1023", "7fefffffffffffff",
  "123456789012345678", "0x1.b69b4ba630f35p+56", "437b69b4ba630f35",
  "0.000123456789012345678", "0x1.02e85be180b74p-13", "3f202e85be180b74",
  "-0", "-0x0.0p+0", "8000000000000000",
  "+.5", "0x1.0000000000000p-1", "3fe0000000000000",
  "7.", "0x1.c000000000000p+2", "401c000000000000"
), ncol = 3, byrow = TRUE, dimnames = list(NULL, c("text", "hex", "bits"))))

# the double whose 8 bytes, most significant first, are the 16 hex digits `b`
from_bits <- function(b) {
  readBin(as.raw(strtoi(substring(b, seq(1, 15, 2), seq(2, 16, 2)), 16L)), "double",
          size = 8L, endian = "big")
}

# a hex float, decoded with exact arithmetic: a whole mantissa below 2^53 times a
# power of two
from_hex <- function(h) {
  m <- regmatches(h, regexec("^(-?)0x([01])\\.([0-9a-f]*)p([-+][0-9]+)$", h))[[1L]]
  frac <- m[[4L]]
  dig <- strtoi(strsplit(frac, "")[[1L]], 16L)
  mant <- as.numeric(m[[3L]]) * 16^nchar(frac) + sum(dig * 16^rev(seq_along(dig) - 1L))
  (if (nzchar(m[[2L]])) -1 else 1) * mant * 2^(as.integer(m[[5L]]) - 4L * nchar(frac))
}

test_that("decimal text is read as the correctly rounded double", {
  for (i in seq_len(nrow(strtod_cases))) {
    want <- from_bits(strtod_cases$bits[i])
    # num.eq = FALSE: bit for bit, so -0 is not 0
    expect_true(identical(from_hex(strtod_cases$hex[i]), want, num.eq = FALSE),
                label = strtod_cases$hex[i])
    expect_true(identical(.rmd_num(strtod_cases$text[i]), want, num.eq = FALSE),
                label = strtod_cases$text[i])
  }
  # vectorised, in order
  expect_true(identical(.rmd_num(strtod_cases$text),
                        vapply(strtod_cases$bits, from_bits, 0, USE.NAMES = FALSE),
                        num.eq = FALSE))
})

test_that("only a plain decimal or exponent number is a number", {
  bad <- c("0x1A", "Inf", "-Inf", "NaN", "NA", " 1", "1 ", "1e", "e5", ".", "-", "",
           "1.2.3", "1,5", "1e+", "--1", "1d5", NA)
  expect_identical(.rmd_num(bad), rep(NA_real_, length(bad)))
  expect_identical(.rmd_num(c("Inf", "-Inf", "NaN", "1"), special = TRUE),
                   c(Inf, -Inf, NaN, 1))
  expect_identical(.rmd_num(c("1e400", "-1e400")), c(Inf, -Inf))
  expect_identical(.rmd_num(character()), numeric())
})

test_that("the conversion does not follow the session's decimal mark", {
  old <- Sys.getlocale("LC_NUMERIC")
  withr::defer(suppressWarnings(Sys.setlocale("LC_NUMERIC", old)))
  ok <- FALSE
  for (loc in c("de_DE.UTF-8", "de_DE.utf8", "fr_FR.UTF-8", "fr_FR.utf8", "German")) {
    if (nzchar(suppressWarnings(Sys.setlocale("LC_NUMERIC", loc)))) {
      ok <- TRUE
      break
    }
  }
  skip_if_not(ok, "no locale with a decimal comma")
  expect_identical(.rmd_num(c("1.239042694", "2,5")),
                   c(from_bits("3ff3d31e6e913e67"), NA))
})
