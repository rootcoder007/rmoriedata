# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Round-8 rules over the shipped SIU corpus, after apply_siu_review.R has applied
# data-raw/siu_round8_review.csv:
#
#   Rscript data-raw/apply_siu_review.R data-raw/siu_round8_review.csv
#   Rscript data-raw/siu_round8_rules.R
#   Rscript data-raw/build_parquet_store.R && Rscript data-raw/sign_store.R
#
# 1. A French row carries its English report's reviewed case facts. The SIU publishes every
#    report in both languages; the facts (dates, team, counts, the affected person's age and
#    sex, the charges and the director's view) are the same, and the English values are the
#    reviewed ones. Filled only when the case has exactly one English report; the French
#    text fields (location, injuries, legislation, the raw dates) stay French.
# 2. sex_gender_affected is coded one way: male / female (man, boy -> male; woman, girl ->
#    female); a value that is not one of these words is a parse fragment and is emptied.
# 3. narrative_summary held the SIU's mandate paragraph (or its FIPPA paragraph), the page
#    title, the news release's title or a section heading on all but three rows, not a
#    narrative: those values are emptied.
# 4. supplemental_materials held the page's chrome on every row -- social-media share links
#    and ontario.ca's privacy, terms and copyright pages: removed; the links to legislation
#    and case law stay.
path <- file.path("inst", "extdata", "siu_directors_reports.csv.gz")
s <- utils::read.csv(gzfile(path), colClasses = "character", check.names = FALSE,
                     encoding = "UTF-8", na.strings = character())
lang <- s[["_language"]]
facts <- c("date_of_incident_iso", "date_siu_notified_iso", "date_of_director_decision_iso",
           "siu_investigators", "siu_forensics_investigators", "number_of_officers_involved",
           "number_of_civilian_witnesses", "number_of_subject_officials", "number_of_witness_officials",
           "subject_official_interviewed_or_notes", "age_affected", "sex_gender_affected",
           "charges_recommended", "directors_decision_reasonable", "directors_name")
en <- s[lang == "en", , drop = FALSE]
one <- names(which(table(en$case_number) == 1L))
en <- en[en$case_number %in% one, , drop = FALSE]
fr <- which(lang == "fr" & s$case_number %in% one)
tw <- match(s$case_number[fr], en$case_number)
filled <- 0L
for (f in facts) {
  v <- en[[f]][tw]
  changed <- !is.na(v) & s[[f]][fr] != v
  filled <- filled + sum(changed)
  s[[f]][fr[changed]] <- v[changed]
}
sx <- tolower(trimws(s$sex_gender_affected))
s$sex_gender_affected <- ifelse(sx %in% c("male", "man", "boy"), "male",
                         ifelse(sx %in% c("female", "woman", "girl"), "female", ""))
junk <- grepl("^(The Special Investigations Unit is a civilian law enforc|Pursuant to section 14 of FIPPA|L.Unité des enquêtes spéciales (\\(|est un organisme)|Special Investigations Unit -- |Unité des Enquêtes Spéciales -- )",
              s$narrative_summary) |
  (nzchar(s$narrative_summary) & s$narrative_summary == s$news_release_title) |
  grepl("\\?$", trimws(s$narrative_summary))  # a section heading, not a narrative
s$narrative_summary[junk] <- ""
social <- paste0("^https?://(www\\.)?(twitter\\.com|x\\.com|facebook\\.com|linkedin\\.com)/|",
                 "^https?://www\\.ontario\\.ca/(en/general/00423[01]|en/general/004228|page/copyright-information)")
s$supplemental_materials <- vapply(strsplit(s$supplemental_materials, ";\\s*"), function(u) {
  paste(u[!grepl(social, u) & nzchar(u)], collapse = "; ")
}, "")
con <- gzfile(path, "w", encoding = "UTF-8")
utils::write.csv(s, con, row.names = FALSE, na = "", fileEncoding = "UTF-8")
close(con)
message(sprintf("French rows from their English report: %d values on %d rows; narrative_summary emptied on %d rows (boilerplate or title); %d rows",
                filled, length(fr), sum(junk), nrow(s)))
