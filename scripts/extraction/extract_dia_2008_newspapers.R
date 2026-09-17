# ============================================================================
# Extract newspaper endorsements from Democracy in Action (2008)
#
# Source page: "Endorsements by Newspapers and Magazines in the 2008 Primary
# Campaign"
# Input: data/raw/Democracy In Action/dia_2008_p2008_newspapers.html
# Output: data/raw/Democracy In Action/dia_2008_newspapers_extracted.csv
#
# This page is considerably messier than the 2012 sources: 2008-era tag soup
# mixing <font>/<u>/<b>/<span style="..."> for the same semantic roles
# (sometimes a section header is <b>, sometimes inline "font-weight: bold"
# styling, sometimes just a <big> with no weight styling at all), two
# different date formats side by side ("12/22/07" and "Dec. 21, 2007"), and
# a handful of outright malformed dates in the source itself (e.g. "01/ /08"
# where the day was left blank, "01//25/08" with a stray extra slash).
#
# Content is organized as: a candidate header (an ALL-CAPS surname, e.g.
# "CLINTON", "OBAMA", "McCAIN") introduces a run of newspaper-endorsement
# lines until the next header of any kind. Candidates are grouped within
# two side-by-side <td> columns per state/contest, but since headers and
# entries are walked in DOCUMENT ORDER regardless of column layout, the
# <table>/<td> structure itself doesn't need to be parsed explicitly -- the
# same flat "track the last header seen" approach used for the 2012
# newspaper page works here too, once every header is reliably recognized.
#
# Development note: getting reliable header recognition took several
# iterations against the actual page (see conversation) because this page's
# markup is inconsistent in ways the 2012 pages were not. Two bugs are
# worth flagging for future maintainers touching this script:
#   1. Splitting only on <br> is NOT enough here -- some headers and the
#      entries that follow them are separated only by a <p>/<div>/<td>
#      boundary with no <br> at all, and treating only <br> as a line break
#      merged them, corrupting which candidate an entry got attributed to.
#      Fix: <p>/<div>/<tr>/<td>/<table> boundaries are tokenized as line
#      breaks too, not just <br>.
#   2. <br> itself sometimes carries an attribute (<br style="...">), which
#      a naive "<br\\s*/?\\s*>"-style regex misses. Fix: match <br\\b[^>]*>.
#
# Section/state headers (decorative text, not data) are recognized against
# an explicit, hand-verified list (BOLD_HEADERS below) rather than any
# single structural rule, because this document uses at least three
# different (and overlapping) styling conventions for the same kind of
# header, and none of them is used exclusively for headers -- e.g. matching
# on "starts with a known header string" was tried and rejected because it
# collided with the real newspaper "Washington Blade" (which starts with
# the state name "Washington"). Anything not recognized as a header, a
# candidate, or a sub-category, while a candidate is active, is treated as
# a genuine entry -- even when it has no date, since several papers in the
# source are listed without one (some explicitly marked "not yet
# confirmed", most just omitted).
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ------------------------------------------------------------
input_path  <- "data/raw/Democracy In Action/dia_2008_p2008_newspapers.html"
output_path <- "data/raw/Democracy In Action/dia_2008_newspapers_extracted.csv"

# ---- Helper: flatten the whole <body> into <br>-and-block-separated lines --
link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', dotall = TRUE)

body_to_lines <- function(body_node) {
  html_str <- as.character(body_node)
  html_str <- str_replace_all(html_str, link_token_re, "\\2@@URL[\\1]@@")
  html_str <- str_replace_all(html_str, "<br\\b[^>]*>", "@@BR@@")
  html_str <- str_replace_all(html_str, "</?(?:p|div|tr|td|table)\\b[^>]*>", "@@BR@@")
  html_str <- str_remove_all(html_str, "<[^>]+>")
  for (pair in list(c("&nbsp;", " "), c("&amp;", "&"), c("&oacute;", "o"),
                    c("&gt;", ">"), c("&lt;", "<"), c("&copy;", "(c)"),
                    c("&rsquo;", "'"))) {
    html_str <- str_replace_all(html_str, fixed(pair[1]), pair[2])
  }
  html_str <- str_replace_all(html_str, "\\s+", " ")
  
  lines <- str_split(html_str, fixed("@@BR@@"))[[1]]
  lines <- str_trim(lines)
  lines[lines != ""]
}

url_token_re <- regex("@@URL\\[([^\\]]*)\\]@@")

# ---- Known candidates and their party ------------------------------------
candidate_party <- c(
  "BIDEN" = "D", "CLINTON" = "D", "EDWARDS" = "D", "OBAMA" = "D", "RICHARDSON" = "D",
  "FTHOMPSON" = "R", "GIULIANI" = "R", "HUCKABEE" = "R", "McCAIN" = "R",
  "PAUL" = "R", "ROMNEY" = "R"
)

# Decorative section/contest headers on this page (state names, "Super-Duper
# Tuesday", month/date labels, the page's own title, etc.), hand-verified
# against the source -- see the file-level comment above for why this is an
# explicit list rather than a structural (bold/underline) rule.
bold_headers <- c(
  "Alabama", "Alaska", "An Example of a No-Endorsement", "April", "April 22",
  "Arizona", "Arkansas", "California", "Colorado", "Connecticut", "Delaware",
  "District of Columbia",
  "Endorsements by Newspapers and Magazines in the 2008 Primary Campaign",
  "Feb. 12 States", "Feb. 19 States", "Feb. 9 States",
  "Florida Primary (Jan. 29, 2008)", "Georgia", "Hawaii (Dem.)", "Idaho",
  "Illinois", "Indiana", "Iowa Caucuses (Jan. 3, 2007)",
  "Iowa Caucuses (Jan. 3, 2007) 2004",  # header + a "2004" cross-reference link, no separator in source
  "Kansas", "Kentucky", "Oregon",
  "Louisiana", "Maine Caucuses (Feb. 1-3 (R) and Feb. 10 (D))",
  "March 11", "March 4", "March States",
  "Massachusetts", "Massachusetts see also NH Primary", "Maryland",
  "May", "May 6 States", "May 13", "May 20",
  "Michigan Primary (Jan. 15, 2008)", "Minnesota", "Mississippi", "Missouri",
  "More February States", "National", "Nebraska", "Nevada Caucuses (Jan. 19, 2008)",
  "New Hampshire Primary (Jan. 8, 2007)",
  "New Hampshire Primary (Jan. 8, 2007) 2004",  # same cross-reference pattern as Iowa above
  "New Jersey", "New Mexico", "New York",
  "North Carolina", "North Dakota", "Notes", "Ohio", "Oklahoma", "Pennsylvania",
  "Rhode Island",
  "South Carolina (Republican Primary Jan. 19, 2008; Democratic Primary Jan. 26, 2008)",
  "Super-Duper Tuesday - Feb. 5, 2008", "Tennessee", "Texas", "Utah", "Vermont",
  "Virginia", "Washington", "West Virginia", "Wisconsin"
)

stop_sections <- c("An Example of a No-Endorsement")  # nothing after this is real data

# "Alternative" stands alone as a continuation sub-header in a few sections
# (a second split after an earlier "Weeklies" header within the same
# candidate's list), distinct from "Weeklies and Alternative" appearing as
# one combined header elsewhere -- both forms are recognized. "not yet
# confirmed:" is the source's own hedge label for rumored-but-unconfirmed
# endorsements; papers listed under it are still captured as rows, just
# with that noted and (since they're unconfirmed) usually no date.
subcategory_re <- regex(
  "^(Dailies|Weeklies and Alternative|Weeklies|Alternative|Specialty|Weekly|not yet confirmed:?)\\b",
  ignore_case = TRUE
)
connector_words <- c("and", "or")  # stray connector words sitting on their own line in the source

# ---- Date patterns ---------------------------------------------------------
# Three formats appear on this page: numeric MM/DD/YY (most common, and
# tolerant of the source's own malformed variants -- a blank day, or a
# stray extra slash), "Month Day, Year", and a bare "Month Year" fallback
# for the handful of entries with no day given (e.g. "July-Aug. 2007").
numeric_date_re <- "\\d{1,2}\\s*/+\\s*\\d{0,2}\\s*/+\\s*\\d{2,4}"
mdy_date_re      <- "[A-Za-z]+\\.?\\s+\\d{1,2},?\\s*\\d{4}"
my_date_re       <- "[A-Za-z]+(?:-[A-Za-z]+)?\\.?\\s+\\d{4}"
date_re <- regex(paste0("(?:", numeric_date_re, ")|(?:", mdy_date_re, ")|(?:", my_date_re, ")"))

paren_span_re   <- "\\([^()]*\\)"
bracket_re      <- regex("\\[([^\\]]*)\\]")
state_suffix_re <- regex("(?:^|\\s)([A-Z]{2})$")

# ---- Helper: parse one newspaper-entry line --------------------------------
parse_entry <- function(raw_line) {
  url_match <- str_match(raw_line, url_token_re)
  evidence_url <- url_match[1, 2]
  text <- str_remove(raw_line, url_token_re)
  text <- str_remove_all(text, ">")  # stray ">" evidence-link marker text
  text <- str_squish(text)
  
  spans <- str_locate_all(text, paren_span_re)[[1]]
  date_idx <- NA_integer_
  if (nrow(spans) > 0) {
    paren_texts    <- str_sub(text, spans[, "start"], spans[, "end"])
    paren_contents <- str_match(paren_texts, "^\\(([^()]*)\\)$")[, 2]
    has_date <- str_detect(paren_contents, date_re)
    if (any(has_date)) date_idx <- which(has_date)[1]
  }
  
  if (is.na(date_idx)) {
    # No date at all -- a genuinely undated entry (either explicitly
    # "not yet confirmed" or just omitted in the source). Still a real
    # row: keep the name, leave date_raw blank rather than dropping it.
    remainder <- text
    date_raw <- NA_character_
    note_in_date_paren <- NA_character_
  } else {
    date_content <- str_sub(text, spans[date_idx, "start"] + 1, spans[date_idx, "end"] - 1)
    dm_start <- str_locate(date_content, date_re)[1, "start"]
    dm_end   <- str_locate(date_content, date_re)[1, "end"]
    date_raw <- str_sub(date_content, dm_start, dm_end)
    before <- str_remove(str_sub(date_content, 1, dm_start - 1), "[.;,\\s]+$")
    after  <- str_remove(str_sub(date_content, dm_end + 1, str_length(date_content)), "^[.;,\\s]+")
    before <- str_trim(before)
    after  <- str_trim(after)
    note_in_date_paren <- paste(c(before, after)[nzchar(c(before, after))], collapse = "; ")
    if (!nzchar(note_in_date_paren)) note_in_date_paren <- NA_character_
    
    remainder <- paste0(
      str_sub(text, 1, spans[date_idx, "start"] - 1),
      str_sub(text, spans[date_idx, "end"] + 1, str_length(text))
    )
    remainder <- str_squish(remainder)
  }
  
  other_notes <- character(0)
  other_matches <- str_match_all(remainder, paren_span_re)[[1]]
  if (length(other_matches) > 0) other_notes <- str_sub(other_matches[, 1], 2, -2)
  remainder <- str_squish(str_remove_all(remainder, paren_span_re))
  
  # Extract a bracketed location/descriptor BEFORE checking for a "..."
  # aside -- some brackets contain their own "..." internally (e.g.
  # "[Seacoast Media Group...Exeter News-Letter, Hampton Union...]"), and
  # splitting on "..." first would break the bracket in half.
  bracket_note <- NA_character_
  bracket_content <- str_match(remainder, bracket_re)[1, 2]
  if (!is.na(bracket_content)) {
    bracket_note <- str_trim(bracket_content)
    remainder <- str_squish(str_remove(remainder, bracket_re))
  }
  
  aside <- NA_character_
  if (str_detect(remainder, fixed("..."))) {
    dots_at   <- str_locate(remainder, fixed("..."))[1, "start"]
    name_part <- str_sub(remainder, 1, dots_at - 1)
    aside     <- str_remove(str_trim(str_sub(remainder, dots_at + 3, str_length(remainder))), "^[.\\s]+")
  } else {
    name_part <- remainder
  }
  
  # A bare trailing two-letter state code (observed only in the National
  # section, e.g. "Irish Voice NY", "Washington Blade DC")
  state <- NA_character_
  sm <- str_match(str_trim(name_part), state_suffix_re)[1, 2]
  if (!is.na(sm)) {
    state <- sm
    name_part <- str_sub(str_trim(name_part), 1, str_locate(str_trim(name_part), state_suffix_re)[1, "start"] - 1)
  }
  
  name <- str_trim(str_squish(name_part), side = "both")
  name <- str_remove(name, "^-\\s*")
  name <- str_remove(name, "\\s*-$")
  if (!nzchar(name) || !str_detect(name, "[A-Za-z]")) {
    return(list(parsed_ok = FALSE))  # nothing left, or pure punctuation noise (e.g. "??")
  }
  
  note_pieces <- c(note_in_date_paren, bracket_note, aside, other_notes)
  note_pieces <- note_pieces[!is.na(note_pieces) & str_length(note_pieces) > 0]
  note <- if (length(note_pieces) > 0) paste(note_pieces, collapse = "; ") else NA_character_
  
  list(
    endorser_name = name, state = state, date_raw = date_raw,
    note = note, evidence_url = evidence_url, parsed_ok = TRUE
  )
}

# ---- Step 1: Read HTML and flatten the whole body into lines --------------

doc  <- read_html(input_path, encoding = "ISO-8859-1")
body <- html_element(doc, "body")

all_lines <- body_to_lines(body)
cat("Total lines found:", length(all_lines), "\n")

# ---- Step 2: Walk the lines as a state machine ----------------------------

current_candidate   <- NA_character_
current_party        <- NA_character_
current_subcategory  <- NA_character_
rows <- list()

for (line in all_lines) {
  clean_line <- str_squish(str_remove(line, url_token_re))
  
  if (clean_line %in% stop_sections) break  # nothing after this is real data
  
  if (str_starts(clean_line, "updated ") || str_starts(clean_line, "Organized by") ||
      clean_line %in% bold_headers) next
  
  if (clean_line == "" || tolower(clean_line) %in% connector_words ||
      str_starts(tolower(clean_line), "note:") || str_starts(tolower(clean_line), "also note")) next
  
  if (clean_line %in% names(candidate_party)) {
    current_candidate   <- clean_line
    current_party        <- candidate_party[[clean_line]]
    current_subcategory  <- NA_character_
    next
  }
  
  if (str_detect(clean_line, subcategory_re)) {
    current_subcategory <- str_remove(clean_line, ":$")
    next
  }
  
  if (is.na(current_candidate)) {
    # Nothing recognized this as a header, but no candidate is active
    # either -- can't attribute it to anyone. Flagged rather than
    # dropped, as a safety net for anything bold_headers missed.
    rows[[length(rows) + 1]] <- tibble(
      party = NA_character_, endorsee = NA_character_,
      endorser_name = NA_character_, endorser_description = NA_character_,
      state = NA_character_, date_raw = NA_character_, note = NA_character_,
      evidence_url = NA_character_, parsed_ok = FALSE,
      raw_text = paste0("[UNMATCHED] ", clean_line)
    )
    next
  }
  
  parsed <- parse_entry(line)
  description <- if (!is.na(current_subcategory)) paste0("Newspaper - ", current_subcategory) else "Newspaper"
  
  if (isTRUE(parsed$parsed_ok)) {
    rows[[length(rows) + 1]] <- tibble(
      party = current_party, endorsee = current_candidate,
      endorser_name = parsed$endorser_name, endorser_description = description,
      state = parsed$state, date_raw = parsed$date_raw, note = parsed$note,
      evidence_url = parsed$evidence_url, parsed_ok = TRUE, raw_text = clean_line
    )
  } else {
    rows[[length(rows) + 1]] <- tibble(
      party = current_party, endorsee = current_candidate,
      endorser_name = NA_character_, endorser_description = description,
      state = NA_character_, date_raw = NA_character_, note = NA_character_,
      evidence_url = NA_character_, parsed_ok = FALSE,
      raw_text = paste0("[UNMATCHED] ", clean_line)
    )
  }
}

df <- bind_rows(rows) %>%
  mutate(
    contest_id = if_else(!is.na(party), paste0("2008", party), NA_character_),
    year = 2008,
    district = NA_character_,
    endorser_party_note = NA_character_,
    switch_direction = NA_character_,
    switch_candidate = NA_character_
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text
  )

# ---- Step 3: Validation checkpoints, report, and write out ----------------

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) did not match the expected pattern and need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text))
cat("(these are kept in output with parsed_ok = FALSE and raw_text preserved)\n")

cat("\nRows with no date given in the source:", sum(df$parsed_ok & is.na(df$date_raw)), "\n")

cat("\nEndorsements per candidate:\n")
print(count(df, endorsee, sort = TRUE))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")