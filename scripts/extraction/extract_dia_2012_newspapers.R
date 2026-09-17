# =============================================================================
# Extract newspaper endorsements from Democracy in Action (2012)
#
# Source page: "Newspaper Endorsements in the 2012 Primary Campaign" (2012)
# Input: data/raw/Democracy in Action/dia_2012_p2012_newspapers.html
# Output: data/raw/Democracy in Action/dia_2012_newspapers_extracted.csv
#
# The page is organized as one <p class="blurb> block per rough section,
# with three kinds of content mixed together as <br>-separated lines:
#   1. Contest headers, e.g. "Iowa Caucuses (Jan. 3, 2012)" -- state primary/
#     caucus name plus its date.
#   2. Bare state-name sub-headers with no date of their own (Georgia/Ohio/
#     Oklahoma under the "Super Tuesday" contest), and the standalone 
#     "National" section.
#   3. Candidate headers (e.g. "Mitt Romney"), which each introduce a run of
#     newspaper-endorsement lines until the next header of any kind.
#   4. Newspaper entries themselves, e.g.:
#         "Denver Post (Feb. 3, 2012)"
#         "Eagle-Tribune [North Andover, MA] (Jan. 6, 2012)"
#
# Unlike the officials pages, this page's content is organized by per-state
# contest. That structure i still tracked internally below, but contest_name/contest_date
# are not written to the output.
#
# NOTE: This page's <br> tags are inconsistently nested -- some sit directly
# inside the <p>, others inside a wrapping <big> or <span> a level down.
# Splitting only on direct-child <br>s would silently miss those and fuse two
# lines together. Following the 2012 officials script's fix for the same class 
# problem, I tokenize <br> (and links) in the raw HTML STING before any tag-stripping,
# so nesting depth can't hide a line break.
# =============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2012_p2012_newspapers.html"
output_path <- "data/raw/Democracy in Action/dia_2012_newspapers_extracted.csv"

# ---- Helper: split one <p> node into (visible-text, evidence-url) lines ----
#
# Works on the <p>'s raw HTML string rather than its parsed node tree:
#   1. Tokenize every <a href="URL">TEXT</a> as "TEXT@@URL[URL]@@" -- this
#      keeps the visible anchor text in place (a paper's name is often
#      itself the link) while parking its href in an unambiguous marker
#      immediately after it, so later steps can find "the link for this
#      line" without caring how deep the <a> was nested.
#   2. Tokenize every <br ...> (regardless of attributes or nesting depth)
#      as "@@BR@@".
#   3. Strip all remaining tags, decode the page's handful of entities, and
#      collapse whitespace (including the literal newlines the source HTML
#      wraps long headers across, e.g. "Alabama\nPrimary\n(March\n13,\n2012)").
#   4. Split on the "@@BR@@" marker into individual lines.
link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', dotall = TRUE)

p_to_lines <- function(p_node) {
  html_str <- as.character(p_node)
  html_str <- str_replace_all(html_str, link_token_re, "\\2@@URL[\\1]@@")
  html_str <- str_replace_all(html_str, "<br\\b[^>]*>", "@@BR@@")
  html_str <- str_remove_all(html_str, "<[^>]+>")
  html_str <- str_replace_all(html_str, "&nbsp;", " ")
  html_str <- str_replace_all(html_str, "&amp;", "&")
  html_str <- str_replace_all(html_str, "\\s+", " ")
  
  lines <- str_split(html_str, fixed("@@BR@@"))[[1]]
  lines <- str_trim(lines)
  lines[lines != ""]
}

# ---- Helper: parse one newspaper-entry line into structured fields --------
#
# Expected shape: "<Name> [optional bracketed location] (<date>[; extra note])"
# sometimes with a leading "...aside text" between the name and the date, and
# occasionally a second, non-date parenthetical describing the paper itself
# (e.g. "Times Daily (Florence) (March 9, 2012)"). Rather than one big regex
# (which can't tell a date-parenthetical from a description-parenthetical
# apart), this walks the line in steps: find every "(...)" group, identify
# the one that actually contains a date, and treat everything else -- other
# parens, a bracketed location, a "..." aside -- as descriptive text that
# gets folded into `note`.
url_token_re      <- regex("@@URL\\[([^\\]]*)\\]@@")
date_re           <- regex("[A-Za-z]+\\.?\\s+\\d{1,2},\\s*\\d{4}")
paren_span_re     <- "\\([^()]*\\)"
bracket_re        <- regex("\\[([^\\]]*)\\]")
state_suffix_re   <- regex("(?:^|,\\s*)([A-Z]{2})$")

parse_entry <- function(raw_line) {
  # 1. Pull the evidence-link token (if any) out of the line
  url_match <- str_match(raw_line, url_token_re)
  evidence_url <- url_match[1, 2]
  text <- str_remove(raw_line, url_token_re)
  
  # 2. Strip stray "+" evidence markers left over from the anchor text
  text <- str_squish(str_remove_all(text, "\\+"))
  
  # 3. Find every "(...)" group and identify the one holding a date
  spans <- str_locate_all(text, paren_span_re)[[1]]
  if (nrow(spans) == 0) return(list(parsed_ok = FALSE))
  
  paren_texts    <- str_sub(text, spans[, "start"], spans[, "end"])
  paren_contents <- str_match(paren_texts, "^\\(([^()]*)\\)$")[, 2]
  has_date <- str_detect(paren_contents, date_re)
  if (!any(has_date)) return(list(parsed_ok = FALSE))
  
  date_idx     <- which(has_date)[1]
  date_content <- paren_contents[date_idx]
  date_raw     <- str_extract(date_content, date_re)
  
  note_in_date_paren <- str_remove(date_content, fixed(date_raw))
  note_in_date_paren <- str_remove(note_in_date_paren, "^[.;,\\s]+")
  note_in_date_paren <- str_remove(note_in_date_paren, "[.;,\\s]+$")
  
  # 4. Remove the date-paren (with its parens) from the text
  remainder <- paste0(
    str_sub(text, 1, spans[date_idx, "start"] - 1),
    str_sub(text, spans[date_idx, "end"] + 1, str_length(text))
  )
  remainder <- str_squish(remainder)
  
  # 5. Any other leftover "(...)" groups (e.g. "(Gainesville)", "(Florence)")
  # describe the paper, not the endorsement date -- fold into note
  other_paren_matches <- str_match_all(remainder, paren_span_re)[[1]]
  other_notes <- if (length(other_paren_matches) > 0) {
    str_sub(other_paren_matches[, 1], 2, -2)  # strip the outer "(" ")"
  } else {
    character(0)
  }
  remainder <- str_squish(str_remove_all(remainder, paren_span_re))
  
  # 6. Split off a "..." aside, if present (e.g. "...student newspaper")
  if (str_detect(remainder, fixed("..."))) {
    dots_at  <- str_locate(remainder, fixed("..."))[1, "start"]
    name_part <- str_sub(remainder, 1, dots_at - 1)
    aside     <- str_sub(remainder, dots_at + 3, str_length(remainder))
    aside     <- str_remove(str_trim(aside), "^[.\\s]+")
  } else {
    name_part <- remainder
    aside <- NA_character_
  }
  
  # 7. Extract a bracketed location, e.g. "[MA]" or "[North Andover, MA]" --
  # a trailing two-letter code becomes `state`; anything else (a bare city,
  # or a city name ahead of the state code) becomes part of `note`
  state <- NA_character_
  bracket_note <- NA_character_
  bracket_content <- str_match(name_part, bracket_re)[1, 2]
  if (!is.na(bracket_content)) {
    state_match <- str_match(bracket_content, state_suffix_re)[1, 2]
    if (!is.na(state_match)) {
      state <- state_match
      city_part <- str_trim(str_remove(bracket_content, state_suffix_re))
      city_part <- str_remove(city_part, ",$")
      if (str_length(city_part) > 0) bracket_note <- city_part
    } else {
      bracket_note <- bracket_content
    }
    name_part <- str_remove(name_part, bracket_re)
  }
  
  name <- str_squish(name_part)
  name <- str_remove(name, "^-\\s*")
  name <- str_remove(name, "\\s*-$")
  
  note_pieces <- c(note_in_date_paren, bracket_note, aside, other_notes)
  note_pieces <- note_pieces[!is.na(note_pieces) & str_length(note_pieces) > 0]
  note <- if (length(note_pieces) > 0) paste(note_pieces, collapse = "; ") else NA_character_
  
  list(
    endorser_name = name,
    state         = state,
    date_raw      = date_raw,
    note          = note,
    evidence_url  = evidence_url,
    parsed_ok     = TRUE
  )
}

# ---- Step 1: Read HTML and flatten every <p class="blurb"> into lines -----

doc <- read_html(input_path)
overview <- html_element(doc, "#overview")
p_nodes  <- html_elements(overview, "p.blurb")

all_lines <- unlist(map(p_nodes, p_to_lines))
cat("Total <br>-separated lines found:", length(all_lines), "\n")

# ---- Step 2: Walk the lines as a state machine, classifying each one ------
#
# Three kinds of header line update the running state and are then dropped
# (they aren't endorsement rows themselves); everything else is treated as
# a newspaper-entry line and handed to parse_entry().

known_candidates <- c("Ron Paul", "Mitt Romney", "Newt Gingrich", "Jon Huntsman", "Rick Santorum")

contest_re <- regex(paste0(
  "^(?<name>.*(?:Primary|Caucus(?:es)?|Tuesday).*?)\\s*",
  "\\((?<date>[A-Za-z]+\\.?\\s+\\d{1,2},\\s*\\d{4})\\)$"
))

current_contest      <- NA_character_
current_contest_date <- NA_character_
current_candidate    <- NA_character_
rows <- list()
contest_log <- character(0)  # parallel to `rows`, for the per-contest report only -- not written to output

for (line in all_lines) {
  clean_line <- str_trim(str_remove(line, url_token_re))
  
  # Page metadata line ("updated March 31, 2012"), not data -- skip
  if (str_starts(clean_line, "updated ")) next
  
  # Contest header, e.g. "Iowa Caucuses (Jan. 3, 2012)"
  m <- str_match(clean_line, contest_re)
  if (!is.na(m[1, 1])) {
    current_contest      <- str_trim(m[1, "name"])
    current_contest_date <- str_trim(m[1, "date"])
    current_candidate    <- NA_character_
    next
  }
  
  # Candidate header
  if (clean_line %in% known_candidates) {
    current_candidate <- clean_line
    next
  }
  
  # Bare state/section sub-header with no date of its own -- the "Georgia" /
  # "Ohio" / "Oklahoma" subsections under "Super Tuesday", and the
  # standalone "National" section. Source-specific heuristic (single
  # capitalized word, no digits, no punctuation), checked against this
  # page's actual content rather than assumed in general.
  if (clean_line == "National" ||
      str_detect(clean_line, "^[A-Z][a-zA-Z]+$")) {
    current_contest      <- clean_line
    current_contest_date <- NA_character_
    current_candidate    <- NA_character_
    next
  }
  
  # Otherwise: a newspaper-endorsement entry line
  parsed <- parse_entry(line)
  visible_text <- str_squish(str_remove(line, url_token_re))
  contest_log <- c(contest_log, current_contest)
  
  if (isTRUE(parsed$parsed_ok)) {
    rows[[length(rows) + 1]] <- tibble(
      contest_id            = "2012R",
      year                  = 2012,
      party                 = "R",
      endorsee              = current_candidate,
      endorser_name         = parsed$endorser_name,
      endorser_description  = "Newspaper",
      endorser_party_note   = NA_character_,
      state                 = parsed$state,
      district              = NA_character_,
      date_raw              = parsed$date_raw,
      note                  = parsed$note,
      switch_direction      = NA_character_,
      switch_candidate      = NA_character_,
      evidence_url          = parsed$evidence_url,
      parsed_ok             = TRUE,
      raw_text              = visible_text
    )
  } else {
    # No date found in the line at all -- flagged for manual review rather
    # than guessed at (mirrors the officials scripts' [UNMATCHED] convention).
    # The only line that lands here on this page is "National Review - not
    # Gingrich": a refusal-to-endorse note, not an actual endorsement.
    rows[[length(rows) + 1]] <- tibble(
      contest_id            = "2012R",
      year                  = 2012,
      party                 = "R",
      endorsee              = current_candidate,
      endorser_name         = NA_character_,
      endorser_description  = "Newspaper",
      endorser_party_note   = NA_character_,
      state                 = NA_character_,
      district              = NA_character_,
      date_raw              = NA_character_,
      note                  = NA_character_,
      switch_direction      = NA_character_,
      switch_candidate      = NA_character_,
      evidence_url          = NA_character_,
      parsed_ok             = FALSE,
      raw_text              = paste0("[UNMATCHED] ", visible_text)
    )
  }
}

df <- bind_rows(rows) %>%
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

cat("\nEndorsements per candidate:\n")
print(count(df, endorsee, sort = TRUE))

cat("\nEndorsements per contest (contest_name/contest_date are not written to\n")
cat("output -- tracked here only to sanity-check the extraction):\n")
print(sort(table(contest_log), decreasing = TRUE))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")