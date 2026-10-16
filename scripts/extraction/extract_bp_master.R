# ============================================================================
# Extract endorsements from Ballotpedia: "Presidential election endorsements"
# (the master endorsements table)
#
# Input: data/raw/Ballotpedia/bp_master_endorsements.html
# Output: data/raw/Ballotpedia/extracted/bp_master_endorsements_extracted.csv
#
# NOTE: this page is not limited to one election. It is
# Ballotpedia's master table of every presidential endorsement it tracks:
# 2,823 rows covering four cycles --
#   2012: 853 rows | 2016: 673 rows | 2020: 495 rows | 2024: 802 rows.
# All rows are extracted; election_year/contest_id record the cycle.
#
# Layout: one sortable table (class "widget-table") with five columns:
#   Endorser | Endorsee (+ "source" link and the candidate's party labels,
#   e.g. "(D, Working Families Party)") | Election | Stage | Outcome
#
# What this table does NOT have (unlike the 2020/2024 summary pages):
#   - No endorsement dates. date_raw is blank for every row.
#   - No endorser office, state or party. endorser_description, state and
#     endorser_party_note are blank. endorser_url (the endorser's
#     Ballotpedia "Endorsements_by_..." page) is kept so endorsers can be
#     matched to the other Ballotpedia files or looked up later.
#   - No switch order. Because there are no dates, a switch cannot be told
#     apart from a dual endorsement; endorsers with more than one candidate
#     in the same cycle are flagged multiple_endorsees_same_cycle = TRUE.
#
# `stage` ("Primary", "General", "Primary, General", or blank) and
# `outcome` (the CANDIDATE's result, e.g. "Won General", "Withdrew in
# Convention") are kept as written.
#
# Column conventions follow the other extraction scripts: `party` and
# `contest_id` are the candidate's party (from the lookup table below; the
# page's own labels are kept in endorsee_party_label). Gary Johnson
# (Libertarian, 2012 and 2016) gets party "L". Candidate names are
# standardized ("Kamala D. Harris" -> "Kamala Harris", "Julian Castro");
# the page's form is kept in endorsee_raw. record_type = "endorsement".
#
# NOTE on overlap: the 2020 and 2024 rows overlap heavily with
# bp_2020_crossparty.html and bp_2024_endorsements.html (which have dates
# and offices), and the 2012/2016 rows overlap with Democracy in Action.
# De-duplication across files is left to harmonization; endorser_url is the
# best join key between Ballotpedia files.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Ballotpedia/bp_master_endorsements.html"
output_path <- "data/raw/Ballotpedia/extracted/bp_master_endorsements_extracted.csv"

# ---- Helper functions -------------------------------------------------------

node_text <- function(x) str_squish(str_replace_all(xml_text(x), "\u00a0", " "))

candidate_names <- setNames(
  c("Kamala Harris", "Julian Castro"),
  c("Kamala D. Harris", "Juli\u00e1n Castro")
)
standardize_name <- function(x) unname(ifelse(x %in% names(candidate_names), candidate_names[x], x))

# Candidate (standardized) + cycle -> party of the contest. Keyed by
# "year|name" because a candidate's party could differ across cycles.
candidate_party <- c(
  # 2012
  "2012|Mitt Romney" = "R", "2012|Newt Gingrich" = "R", "2012|Rick Santorum" = "R",
  "2012|Ron Paul" = "R", "2012|Rick Perry" = "R", "2012|Jon Huntsman" = "R",
  "2012|Michele Bachmann" = "R", "2012|Herman Cain" = "R", "2012|Gary Johnson" = "L",
  # 2016
  "2016|Hillary Clinton" = "D", "2016|Bernie Sanders" = "D", "2016|Martin O'Malley" = "D",
  "2016|Donald Trump" = "R", "2016|Marco Rubio" = "R", "2016|Ted Cruz" = "R",
  "2016|Jeb Bush" = "R", "2016|John Kasich" = "R", "2016|Chris Christie" = "R",
  "2016|Rand Paul" = "R", "2016|Carly Fiorina" = "R", "2016|Mike Huckabee" = "R",
  "2016|Gary Johnson" = "L",
  # 2020
  "2020|Joe Biden" = "D", "2020|Elizabeth Warren" = "D", "2020|Bernie Sanders" = "D",
  "2020|Michael Bloomberg" = "D", "2020|Kamala Harris" = "D", "2020|Cory Booker" = "D",
  "2020|Pete Buttigieg" = "D", "2020|Amy Klobuchar" = "D", "2020|Beto O'Rourke" = "D",
  "2020|Julian Castro" = "D", "2020|Michael Bennet" = "D", "2020|Jay Inslee" = "D",
  "2020|Steve Bullock" = "D", "2020|Tom Steyer" = "D", "2020|John Delaney" = "D",
  "2020|Eric Swalwell" = "D", "2020|Kirsten Gillibrand" = "D", "2020|John Hickenlooper" = "D",
  # 2024
  "2024|Donald Trump" = "R", "2024|Kamala Harris" = "D", "2024|Joe Biden" = "D",
  "2024|Ron DeSantis" = "R", "2024|Nikki Haley" = "R", "2024|Mike Pence" = "R",
  "2024|Doug Burgum" = "R", "2024|Tim Scott" = "R", "2024|Vivek Ramaswamy" = "R"
)

# ---- Step 1: Read HTML and find the table -----------------------------------

doc <- read_html(input_path, encoding = "UTF-8")
tbl <- xml_find_first(doc, "//table[contains(@class, 'widget-table')]")
stopifnot(!inherits(tbl, "xml_missing"))

rows <- xml_find_all(tbl, ".//tr[td]")   # data rows only (the header row uses <th>)
stopifnot(length(rows) == 2823)

# ---- Step 2: Pull each column -----------------------------------------------
# xml_find_first() on a set of rows returns one result per row (or a
# "missing" placeholder), so each column is read in one vectorized call.

endorser_cell <- xml_find_first(rows, "./td[1]")
endorsee_cell <- xml_find_first(rows, "./td[2]")
election_cell <- xml_find_first(rows, "./td[3]")
stage_cell    <- xml_find_first(rows, "./td[4]")
outcome_cell  <- xml_find_first(rows, "./td[5]")

endorsee_text <- node_text(endorsee_cell)

df <- tibble(
  endorser_name        = node_text(endorser_cell),
  endorser_url         = xml_attr(xml_find_first(endorser_cell, ".//a"), "href"),
  endorsee_raw         = node_text(xml_find_first(endorsee_cell, "./a")),   # candidate link, not the source link
  endorsee_party_label = str_match(endorsee_text, "\\(([^()]*)\\)\\s*$")[, 2],
  evidence_url         = xml_attr(xml_find_first(endorsee_cell, ".//cite//a"), "href"),
  election_raw         = node_text(election_cell),
  stage                = na_if(node_text(stage_cell), ""),
  outcome              = na_if(node_text(outcome_cell), ""),
  raw_text             = paste(node_text(endorser_cell), endorsee_text, node_text(election_cell),
                               node_text(stage_cell), node_text(outcome_cell), sep = " | ")
)

# ---- Step 3: Derived fields -------------------------------------------------

df <- df %>%
  mutate(
    year         = as.integer(str_match(election_raw, "\\((\\d{4})\\)")[, 2]),
    endorsee     = standardize_name(endorsee_raw),
    party        = unname(candidate_party[paste(year, endorsee, sep = "|")]),
    contest_id   = paste0(year, party),
    endorser_url = if_else(str_starts(endorser_url, "/"),
                           paste0("https://ballotpedia.org", endorser_url), endorser_url)
  ) %>%
  group_by(year, endorser_key = coalesce(endorser_url, endorser_name)) %>%
  mutate(multiple_endorsees_same_cycle = n_distinct(endorsee) > 1) %>%
  ungroup() %>%
  select(-endorser_key)

# ---- Step 4: Constant fields and column order --------------------------------

df <- df %>%
  mutate(
    endorser_description = NA_character_,
    endorser_party_note  = NA_character_,
    state                = NA_character_,
    district             = NA_character_,
    date_raw             = NA_character_,
    note                 = NA_character_,
    record_type          = "endorsement",
    switch_direction     = NA_character_,
    switch_candidate     = NA_character_,
    parsed_ok            = !is.na(endorser_name) & endorser_name != "" & !is.na(party),
    raw_text             = if_else(parsed_ok, raw_text, paste0("[UNMATCHED] ", raw_text))
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # Ballotpedia-master-table-specific columns (see header comments)
    endorsee_raw, endorsee_party_label, endorser_url, election_raw, stage, outcome,
    multiple_endorsees_same_cycle
  )

# ---- Step 5: Validation checkpoints, report, and write out -----------------

cat("\nRows per cycle and contest:\n")
print(count(df, year, contest_id))

# Expected from manual inspection: 853 / 673 / 495 / 802 rows by cycle, and
# every candidate is in the party lookup table.
stopifnot(
  sum(df$year == 2012) == 853,
  sum(df$year == 2016) == 673,
  sum(df$year == 2020) == 495,
  sum(df$year == 2024) == 802,
  all(!is.na(df$party))
)

cat("\nStage values:\n");   print(count(df, stage))
cat("\nOutcome values:\n"); print(count(df, outcome))
cat("\nRows with no endorser link:", sum(is.na(df$endorser_url)), "\n")
cat("Rows with no source link:", sum(is.na(df$evidence_url)), "\n")
cat("Rows whose endorser backed more than one candidate in a cycle:",
    sum(df$multiple_endorsees_same_cycle), "\n")

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
if (n_failed > 0) print(df %>% filter(!parsed_ok) %>% pull(raw_text) %>% str_trunc(110))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")