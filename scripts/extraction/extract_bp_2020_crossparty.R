# ============================================================================
# Extract endorsements from Ballotpedia: "Presidential election endorsements,
# 2020"
#
# Input: data/raw/Ballotpedia/bp_2020_crossparty.html
# Output: data/raw/Ballotpedia/extracted/bp_2020_crossparty_extracted.csv
#
# Despite the file name, this page has two parts, recorded in `page_section`:
#   1. "Noteworthy cross-party endorsements" -- two bulleted lists
#      (Republicans endorsing Joe Biden: 32; Democrats endorsing Donald
#      Trump: 8). General-election endorsements. Each item reads like
#      "Former Gov. John Kasich (Ohio)[3]": title, name, state, footnote.
#   2. "Democratic primary endorsements" -- three tables (governors 10,
#      U.S. senators 22, U.S. representatives 211) with columns
#      Name | State | Party | Candidate | Date (+ "source" link).
#
# NOTE on switches: Ballotpedia lists an endorser once per candidate they
# endorsed, so a person appearing twice in one table switched candidates
# (e.g. Ruben Gallego: Swalwell -> Harris -> Biden). Within each table,
# each endorser's rows are put in date order and every row after the first
# gets switch_direction = "from" and switch_candidate = the previous
# candidate. 50 rows are switches.
#
# NOTE on dates: the list items have no endorsement date. The footnote's
# citation (news outlet, headline, date) is kept in `citation`, and the
# first date in it in `source_date`; date_raw is left blank for these rows.
#
# Column conventions follow the Democracy in Action scripts: `party` and
# `contest_id` are the CANDIDATE's party (2020D / 2020R); the endorser's own
# party goes in endorser_party_note. Candidate names are standardized
# ("Kamala D. Harris" -> "Kamala Harris"); the page's form is kept in
# endorsee_raw. record_type = "endorsement" for every row.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - "Harbors Mayor Chris Swanson" -- the town is Two Harbors, MN; the six
#     Minnesota mayors have no state in parentheses, so state is blank.
#   - List items give states as written ("Ill.", "Penn.", "Texas"); these
#     are converted to postal codes, with the original kept in raw_text.
#   - Delegates (e.g. Stacey Plaskett, USVI) and Kamala Harris as a senator
#     have a blank State cell on the page.
#   - The tables have no district numbers; district is blank.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Ballotpedia/bp_2020_crossparty.html"
output_path <- "data/raw/Ballotpedia/extracted/bp_2020_crossparty_extracted.csv"
year <- 2020

# ---- Helper functions -------------------------------------------------------

node_text <- function(x) str_squish(str_replace_all(xml_text(x), "\u00a0", " "))

# Candidate names as Ballotpedia writes them -> standardized names
candidate_names <- setNames(
  c("Kamala Harris", "Julian Castro"),
  c("Kamala D. Harris", "Juli\u00e1n Castro")
)
standardize_name <- function(x) unname(ifelse(x %in% names(candidate_names), candidate_names[x], x))

# Candidate (standardized) -> party of the nomination contest
candidate_party <- c(
  "Joe Biden" = "D", "Michael Bennet" = "D", "Michael Bloomberg" = "D",
  "Cory Booker" = "D", "Steve Bullock" = "D", "Pete Buttigieg" = "D",
  "Julian Castro" = "D", "John Delaney" = "D", "Kirsten Gillibrand" = "D",
  "Kamala Harris" = "D", "Jay Inslee" = "D", "Amy Klobuchar" = "D",
  "Beto O'Rourke" = "D", "Bernie Sanders" = "D", "Eric Swalwell" = "D",
  "Elizabeth Warren" = "D", "Donald Trump" = "R"
)

# "July 2, 2019" -> Date, without depending on the computer's locale
long_date_re <- "(?:January|February|March|April|May|June|July|August|September|October|November|December) \\d{1,2}, \\d{4}"
parse_long_date <- function(x) {
  m <- str_match(x, "^([A-Z][a-z]+) (\\d{1,2}), (\\d{4})$")
  mon <- match(m[, 2], month.name)
  as.Date(ifelse(is.na(mon), NA, sprintf("%s-%02d-%02d", m[, 4], mon, as.integer(m[, 3]))))
}

# State names and AP-style abbreviations -> postal codes
state_lookup <- c(
  setNames(state.abb, state.name),
  "Ala." = "AL", "Ariz." = "AZ", "Ark." = "AR", "Calif." = "CA", "Colo." = "CO",
  "Conn." = "CT", "Del." = "DE", "Fla." = "FL", "Ga." = "GA", "Ill." = "IL",
  "Ind." = "IN", "Kan." = "KS", "Ky." = "KY", "La." = "LA", "Md." = "MD",
  "Mass." = "MA", "Mich." = "MI", "Minn." = "MN", "Miss." = "MS", "Mo." = "MO",
  "Mont." = "MT", "Neb." = "NE", "Nev." = "NV", "N.H." = "NH", "N.J." = "NJ",
  "N.M." = "NM", "N.Y." = "NY", "N.C." = "NC", "N.D." = "ND", "Okla." = "OK",
  "Ore." = "OR", "Pa." = "PA", "Penn." = "PA", "R.I." = "RI", "S.C." = "SC",
  "S.D." = "SD", "Tenn." = "TN", "Vt." = "VT", "Va." = "VA", "Wash." = "WA",
  "W.Va." = "WV", "Wis." = "WI", "Wyo." = "WY"
)

# Title at the start of a list item, then the name, then "(State)"
list_item_re <- regex(paste0(
  "^((?:Former )?(?:\\d{4} presidential candidate|Vice President|Lieutenant Governor|",
  "Lt\\. Gov\\.|Gov\\.|U\\.S\\. Sen\\.|Sen\\.|U\\.S\\. Rep\\.|Rep\\.|Secretary of State|",
  "Comptroller|State Sen\\.|State Rep\\.|State Assembly(?:wo)?man)|",
  "[A-Z][A-Za-z ]*? (?:State Rep\\.|Mayor))\\s+(.+?)\\s*(?:\\(([^)]+)\\))?$"
))

# ---- Step 1: Read HTML ------------------------------------------------------

doc <- read_html(input_path, encoding = "UTF-8")

# ---- Step 2: Tables ("Democratic primary endorsements") --------------------

tables <- xml_find_all(doc, "//table[contains(@class, 'endorsementTable')]")
stopifnot(length(tables) == 3)

office_from_title <- function(title) {
  case_when(
    str_detect(title, "by governors")             ~ "Governor",
    str_detect(title, "by U\\.S\\. senators")      ~ "U.S. Senator",
    str_detect(title, "by U\\.S\\. representatives") ~ "U.S. Representative",
    TRUE ~ NA_character_
  )
}

parse_table <- function(tbl) {
  rows    <- xml_find_all(tbl, ".//tr")
  title   <- node_text(rows[[1]])
  header  <- node_text(xml_find_all(rows[[2]], "./th"))
  section <- node_text(xml_find_first(tbl, "preceding::h2[1]"))
  data_rows <- rows[-(1:2)]
  
  map_dfr(data_rows, function(r) {
    cells <- xml_find_all(r, "./td")
    vals  <- setNames(node_text(cells), header)
    tibble(
      page_section         = section,
      source_table         = title,
      endorsee_raw         = vals[["Candidate"]],
      endorser_name        = vals[["Name"]],
      endorser_description = office_from_title(title),
      endorser_party_note  = vals[["Party"]],
      state                = na_if(vals[["State"]], ""),
      date_raw             = str_squish(str_remove(vals[["Date"]], "\\s*source$")),
      evidence_url         = xml_attr(xml_find_first(cells[[length(cells)]], ".//a"), "href"),
      endorser_url         = xml_attr(xml_find_first(cells[[1]], ".//a"), "href"),
      citation             = NA_character_,
      source_date          = NA_character_,
      raw_text             = paste(vals, collapse = " | ")
    )
  })
}

table_df <- map_dfr(tables, parse_table)
cat("Table rows extracted:", nrow(table_df), "\n")

# Switches: an endorser listed more than once in the same table
table_df <- table_df %>%
  mutate(endorsee = standardize_name(endorsee_raw),
         .date = parse_long_date(date_raw), .row = row_number()) %>%
  group_by(source_table, endorser_url) %>%
  arrange(.date, .by_group = TRUE) %>%
  mutate(
    switch_direction = if_else(row_number() > 1, "from", NA_character_),
    switch_candidate = if_else(row_number() > 1, lag(endorsee), NA_character_)
  ) %>%
  ungroup() %>%
  arrange(.row) %>%
  select(-.date, -.row)

# ---- Step 3: Bulleted lists ("Noteworthy cross-party endorsements") ---------
# Endorsement list items are the <li> elements that carry a footnote
# (<sup class="reference">) and sit under the cross-party <h2>.

footnote <- function(ref_id) {
  li <- xml_find_first(doc, sprintf("//li[@id='%s']", ref_id))
  if (inherits(li, "xml_missing")) return(list(text = NA_character_, url = NA_character_))
  list(
    text = node_text(xml_find_first(li, ".//span[contains(@class, 'reference-text')]")),
    url  = xml_attr(xml_find_first(li, ".//span[contains(@class, 'reference-text')]//a"), "href")
  )
}

all_items <- xml_find_all(doc, "//li[sup[contains(@class, 'reference')]]")
in_crossparty <- map_lgl(all_items, function(li) {
  str_detect(node_text(xml_find_first(li, "preceding::h2[1]")), "cross-party")
})
items <- all_items[in_crossparty]

list_df <- map_dfr(items, function(li) {
  heading <- node_text(xml_find_first(li, "preceding::h3[1]"))   # "Republicans endorsing Joe Biden"
  text    <- str_squish(str_remove_all(node_text(li), "\\[\\d+\\]"))
  m       <- str_match(text, list_item_re)
  ref_ids <- str_remove(xml_attr(xml_find_all(li, ".//sup[contains(@class, 'reference')]//a"), "href"), "^#")
  notes   <- map(ref_ids, footnote)
  cites   <- map_chr(notes, "text")
  urls    <- map_chr(notes, "url")
  state_written <- m[1, 4]
  
  tibble(
    page_section         = node_text(xml_find_first(li, "preceding::h2[1]")),
    source_table         = heading,
    endorsee_raw         = str_match(heading, "endorsing (.+)$")[1, 2],
    endorser_name        = m[1, 3],
    endorser_description = m[1, 2],
    endorser_party_note  = str_match(heading, "^(.+?) endorsing")[1, 2],
    state                = if (!is.na(state_written) && state_written %in% names(state_lookup)) state_lookup[[state_written]] else NA_character_,
    date_raw             = NA_character_,
    evidence_url         = if (any(!is.na(urls))) paste(na.omit(urls), collapse = "; ") else NA_character_,
    endorser_url         = xml_attr(xml_find_first(li, "./a"), "href"),
    citation             = if (any(!is.na(cites))) paste(na.omit(cites), collapse = " | ") else NA_character_,
    source_date          = str_extract(paste(cites, collapse = " "), long_date_re),
    raw_text             = text,
    switch_direction     = NA_character_,
    switch_candidate     = NA_character_
  )
}) %>%
  mutate(endorsee = standardize_name(endorsee_raw))
cat("Cross-party list items extracted:", nrow(list_df), "\n")

# ---- Step 4: Combine, add constant fields, order columns -------------------

stopifnot(all(unique(c(table_df$endorsee, list_df$endorsee)) %in% names(candidate_party)))

df <- bind_rows(list_df, table_df) %>%
  mutate(
    party       = unname(candidate_party[endorsee]),
    contest_id  = paste0(year, party),
    year        = year,
    district    = NA_character_,
    note        = NA_character_,
    record_type = "endorsement",
    endorser_url = if_else(str_starts(endorser_url, "/"), paste0("https://ballotpedia.org", endorser_url), endorser_url),
    parsed_ok   = !is.na(endorser_name) & !is.na(endorsee),
    raw_text    = if_else(parsed_ok, raw_text, paste0("[UNMATCHED] ", raw_text))
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # Ballotpedia-specific columns (see header comments)
    endorsee_raw, page_section, source_table, endorser_url, citation, source_date
  )

# ---- Step 5: Validation checkpoints, report, and write out -----------------
# Expected from manual inspection: 40 list items (32 + 8) and 243 table rows
# (10 + 22 + 211), of which 50 are switches.

cat("\nRows per section and table:\n")
print(count(df, page_section, source_table))

stopifnot(
  nrow(list_df) == 40,
  nrow(table_df) == 243,
  sum(!is.na(df$switch_direction)) == 50,
  all(df$parsed_ok)
)

cat("\nList items whose state could not be converted to a postal code:\n")
print(df %>% filter(page_section != "Democratic primary endorsements", is.na(state)) %>% pull(raw_text))

cat("\nEndorsements per candidate:\n")
print(count(df, endorsee, sort = TRUE))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")