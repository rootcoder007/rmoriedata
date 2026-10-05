
test_that("the csv bundle is the corpus and the parquet copy matches it", {
  d <- load_siu_reports()
  cat <- utils::read.csv(system.file("extdata", "_catalog.csv", package = "rmoriedata"))
  expect_equal(nrow(d), cat$n_rows[cat$slug == "siu_directors_reports"])
  expect_identical(d, load_siu_reports(format = "csv"))
  expect_identical(load_siu_reports(format = "parquet"), d)
})

test_that("each report names its subject officials' service, once per language", {
  d <- load_siu_reports()
  expect_true(all(nzchar(d$police_service)))
  expect_false(anyDuplicated(paste(d$drid, d[["_language"]])) > 0L)
  expect_setequal(unique(d[["_language"]]), c("en", "fr"))
})

test_that("round 8: French legacy reports are French, with their own service", {
  d <- load_siu_reports()
  lang <- d[["_language"]]
  row <- function(drid) d[d$drid == drid, , drop = FALSE]
  expect_false(any(d$police_service == "Guelph Police Service" &
                     d$case_number %in% c("05-TCD-004", "10-PFD-078", "10-OOD-009")))
  for (k in c("3556", "3559", "3561", "3658", "3674", "3682")) {
    expect_identical(row(k)[["_language"]], "fr", info = k)
  }
  expect_identical(row("3658")$police_service, "Service de police de Toronto")
  expect_identical(row("3561")$police_service, "Police provinciale de l'Ontario")
  expect_identical(row("3682")$police_service, "Service de police d'Ottawa")
  # each (case, language) holds one report, except cases the SIU reported twice
  expect_identical(row("925")$case_number, "19-TCI-073a")
  expect_identical(row("2209")$case_number, "22-PCI-191")
  expect_identical(row("2209")$police_service, "Police provinciale de l'Ontario")
})

test_that("round 8: a corrigendum is carried on the report it corrects, not counted", {
  d <- load_siu_reports()
  expect_false(any(d$drid %in% c("385", "620", "621", "5065")))
  corrected <- d$drid[nzchar(d$corrigenda)]
  expect_true(all(c("328", "329", "521", "522", "4561", "4572") %in% corrected))
  expect_match(d$corrigenda[d$drid == "4561"], "drid 5065, 2026-04-29", fixed = TRUE)
  expect_match(d$corrigenda[d$drid == "328"], "drid 385, 2019-07-15", fixed = TRUE)
  # second copies of one report are gone
  expect_false(any(d$drid %in% c("3185", "3186", "3652", "3913", "3924", "4580")))
})

test_that("round 8: one coding per column; French rows hold the English case facts", {
  d <- load_siu_reports()
  expect_setequal(setdiff(unique(d$charges_recommended), ""), c("FALSE", "TRUE"))
  # the typed table reads it as logical, as panel_reviewed
  typed <- morie_data_load("siu_directors_reports")
  expect_type(typed$charges_recommended, "logical")
  expect_identical(sum(typed$charges_recommended, na.rm = TRUE),
                   sum(d$charges_recommended == "TRUE"))
  expect_setequal(setdiff(unique(d$sex_gender_affected), ""), c("male", "female"))
  expect_false("City of Kawartha Lakes Police Service" %in% d$police_service)
  expect_false("Cornwall Community Police Service" %in% d$police_service)
  # French rows: the English report's reviewed case facts
  en <- d[d[["_language"]] == "en", ]
  fr <- d[d[["_language"]] == "fr", ]
  one <- names(which(table(en$case_number) == 1L))
  fr1 <- fr[fr$case_number %in% one, ]
  tw <- en[match(fr1$case_number, en$case_number), ]
  for (f in c("date_of_incident_iso", "number_of_subject_officials", "age_affected",
              "charges_recommended")) {
    expect_identical(fr1[[f]], tw[[f]], info = f)
  }
  expect_gt(mean(nzchar(fr$date_of_incident_iso)), 0.95)
  # page chrome is gone from the text columns
  expect_false(any(grepl("twitter\\.com|ontario\\.ca/en/general/004228",
                         d$supplemental_materials)))
  expect_false(any(grepl("^The Special Investigations Unit is a civilian law enforc",
                         d$narrative_summary)))
})

test_that("narrative_summary is the report's own account of the incident", {
  d <- load_siu_reports()
  n <- d$narrative_summary
  # every report whose page has an incident account carries it (8 pages have none)
  expect_gte(sum(nzchar(n)), 4600L)
  expect_true(all(nchar(n) <= 1500L))
  # definition notes and the mandate boilerplate are not the account
  boilerplate <- "A complainant is an individual|Un plaignant est une personne"
  expect_false(any(grepl(boilerplate, n)))
  expect_false(any(grepl("^Note\\s*:", n)))
  # French reports carry the French account, English reports the English one
  fr <- n[d$`_language` == "fr" & nzchar(n)]
  en <- n[d$`_language` == "en" & nzchar(n)]
  expect_gt(mean(grepl("\\b(le|la|les|du|des)\\b", fr)), 0.95)
  expect_gt(mean(grepl("\\b(the|and|of)\\b", en)), 0.95)
  # drid 3422 (2016): its "Incident narrative" section, not the notification above it
  r <- n[d$drid == "3422" & d$`_language` == "en"]
  expect_match(r, "^On May 23, 2016, a woman made a 911 call")
  expect_match(r, "taken to the police station in SO #2's cruiser\\.$")
})
