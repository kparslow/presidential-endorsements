# ============================================================================
# Extract labor-organization endorsements from Democracy in Action (2008)
#
# Source page: "Labor Endorsements in the 2008 Primary Campaigns"
# Input: data/raw/Democracy in Action/dia_2008_labor.html
# Output: data/raw/Democracy in Action/extracted/dia_2008_labor_extracted.csv
#
# This page has four regions, handled in three passes:
#   1. Logo grid at the top (images only) -- skipped; it carries no text.
#   2. National endorsements -- six <table cellpadding="0"> blocks, each
#      preceded by an underlined heading (CLINTON, OBAMA, DODD, EDWARDS,
#      HUCKABEE, NO NATIONAL ENDORSEMENT). Each non-blank row's second <td>
#      is one union: name (first line), a grey "Organization:" line
#      (leadership), then free-text narrative with the endorsement date.
#   3. State/Local -- loose <p> paragraphs under all-caps underlined
#      candidate headings. Each entry starts with ">", the endorser is in
#      <b>, and the endorsee as written is in <u>.
#   4. Notes -- bulleted prose (Change to Win, USW, CWA, "favorite son"
#      resolutions). These describe non-endorsements and are excluded (see
#      keep_favorite_son_resolutions in Config for the one borderline case).
#
# Decisions applied in this script (Oct. 2026):
#   - Non-endorsements are excluded: the NO NATIONAL ENDORSEMENT table and
#     the Notes section.
#   - Rows covering several endorsers are split: TCU out of the IAM cell,
#     "Ten SEIU State Councils" into 10 rows, "SEIU Locals 1199 and 32BJ"
#     into 2 rows.
#   - endorsee and switch_candidate use standardized full names ("Hillary
#     Clinton"); the page's own heading is kept in section_heading.
#   - record_type is "endorsement" for every row (no retractions here).
#
# NOTE on the HTML: HTML 4 does not allow a <table> inside a <p>, so the
# parser closes each <p> before its table. The candidate heading and its
# table are therefore siblings, not parent/child -- which is why the heading
# is found with the XPath "preceding::u[1]" (nearest underlined text above
# the table) rather than by walking up from the table.
#
# NOTE on dates: national-section narratives often contain several dates
# (founding dates, earlier endorsements, forum dates). date_raw is the first
# date that follows a mention of the section's candidate within 160
# characters (e.g. "...endorsement of Sen. Obama on May 21, 2008"); if no
# date follows the candidate's name, the first date in the narrative is
# used. Every date found is kept in all_dates so the choice can be checked.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - The IAM cell under CLINTON also describes the Transportation
#     Communications Union (TCU) endorsement of Clinton (same date), in a
#     paragraph starting "Additionally, the ..."; that paragraph becomes
#     its own TCU row.
#   - IAM appears under both CLINTON and HUCKABEE (a dual endorsement), so
#     it produces two rows by design.
#   - The SEIU cell under OBAMA narrates the earlier state-council
#     endorsements that are also listed under State/Local; date_raw picks
#     the Feb. 15, 2008 national endorsement.
#   - RWDSU (under CLINTON) has no separate name line; its name is taken
#     from the start of the paragraph up to "(RWDSU)". Its date is
#     month-only ("May 2007").
#   - Several organization homepage links on this page point to the wrong
#     union's site, so the first link in each national cell (the name link)
#     is not used as evidence_url. Only links in the narrative are kept.
#   - Source typos are left as-is (e.g. "Mar. 17, 2007" in the Notes for a
#     2008 USW letter).
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2008_labor.html"
output_path <- "data/raw/Democracy in Action/extracted/dia_2008_labor_extracted.csv"

# The Notes section is excluded (it describes non-endorsements). Set this to
# TRUE to keep the one borderline case, the New York State AFL-CIO's May 3,
# 2007 resolution declaring Clinton its "favorite sister", as a row.
keep_favorite_son_resolutions <- FALSE

# ---- Helper functions -------------------------------------------------------

# Same marker technique as the 2012 scripts: rewrite links and line breaks
# as plain-text markers BEFORE stripping tags, so no break or link is lost to
# a parser's rendering heuristics. Links become "text@@URL[href]@@".
link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
                       dotall = TRUE, ignore_case = TRUE)
url_token_re  <- regex("@@URL\\[([^\\]]*)\\]@@")
block_tag_re  <- regex("</?(?:p|div|tr|td|th|table|tbody|li|ul|center|blockquote|h1|h2|h3)\\b[^>]*>",
                       ignore_case = TRUE)

# html_str -> vector of non-empty text lines. `marks` is an optional named
# vector of regex = replacement pairs applied first (used below to keep
# <b> and <u> visible as {{...}} and [[...]] in the State/Local section).
flatten_html <- function(html_str, marks = NULL) {
  html_str <- str_remove_all(html_str, regex("<script\\b.*?</script>", dotall = TRUE, ignore_case = TRUE))
  # An empty link may serialize as self-closing <a href="..."/>; drop it so
  # the link pattern cannot run on to the next </a>.
  html_str <- str_remove_all(html_str, regex("<a\\b[^>]*/>", ignore_case = TRUE))
  html_str <- str_replace_all(html_str, link_token_re, "\\2@@URL[\\1]@@")
  if (!is.null(marks)) {
    for (pattern in names(marks)) {
      html_str <- str_replace_all(html_str, regex(pattern, ignore_case = TRUE), marks[[pattern]])
    }
  }
  html_str <- str_replace_all(html_str, regex("<br\\b[^>]*>", ignore_case = TRUE), "@@BR@@")
  html_str <- str_replace_all(html_str, block_tag_re, "@@BR@@")
  # Re-parse so entities (&amp;, &nbsp;, curly quotes) decode correctly.
  frag <- read_html(paste0("<html><body><div>", html_str, "</div></body></html>"),
                    encoding = "UTF-8")
  txt <- xml_text(frag)
  txt <- str_replace_all(txt, "\u00a0", " ")
  txt <- str_replace_all(txt, "\\s+", " ")
  lines <- str_trim(str_split(txt, fixed("@@BR@@"))[[1]])
  lines[lines != ""]
}

strip_urls <- function(x) str_squish(str_remove_all(x, url_token_re))

# All hrefs found in a vector of lines, collapsed to one "; "-separated string.
collect_urls <- function(lines) {
  urls <- unlist(map(lines, ~ str_match_all(.x, url_token_re)[[1]][, 2]))
  urls <- unique(urls[!is.na(urls) & urls != ""])
  if (length(urls) == 0) NA_character_ else paste(urls, collapse = "; ")
}

# Dates on this page: "Aug. 30, 2007", "April 16, 2008", "Sept. 2007", "May 2007".
month_re <- "(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\\.?"
date_re  <- regex(paste0(month_re, "\\s+\\d{1,2},\\s*\\d{4}|", month_re, "\\s+\\d{4}"))

all_dates <- function(text) {
  d <- str_extract_all(text, date_re)[[1]]
  if (length(d) == 0) NA_character_ else paste(d, collapse = "; ")
}

# First date preceded (within 160 characters) by the candidate's surname;
# falls back to the first date in the text. See header NOTE on dates.
pick_date <- function(text, surname) {
  locs <- str_locate_all(text, date_re)[[1]]
  if (nrow(locs) == 0) return(NA_character_)
  dates <- str_sub(text, locs[, "start"], locs[, "end"])
  if (!is.na(surname)) {
    for (i in seq_len(nrow(locs))) {
      window <- str_sub(text, max(1, locs[i, "start"] - 160), locs[i, "start"] - 1)
      if (str_detect(window, regex(surname, ignore_case = TRUE))) return(dates[i])
    }
  }
  dates[1]
}

# "Originally endorsed Sen. Edwards", "which had endorsed Sen. John Edwards"
# Only the leading phrase is case-insensitive ("(?i:...)"); the name part
# must stay case-sensitive so "[A-Z]" cannot match a lowercase word like "in".
switch_from_re <- regex(
  "(?i:originally endorsed|had endorsed|previously backed)\\s+(?:former\\s+)?(?:Sen\\.|Rep\\.|Gov\\.)?\\s*(?:[A-Z][a-z]+\\s+)?([A-Z][a-z]+)"
)
detect_switch_from <- function(text) {
  m <- str_match(text, switch_from_re)
  m[1, 2]
}

heading_party <- c(
  "BIDEN" = "D", "CLINTON" = "D", "DODD" = "D", "EDWARDS" = "D",
  "OBAMA" = "D", "RICHARDSON" = "D", "HUCKABEE" = "R"
)

# Page headings (and surnames used in switch text) -> standardized full names.
# Names not in this table are returned unchanged.
candidate_names <- c(
  "BIDEN" = "Joe Biden", "CLINTON" = "Hillary Clinton", "DODD" = "Chris Dodd",
  "EDWARDS" = "John Edwards", "OBAMA" = "Barack Obama",
  "RICHARDSON" = "Bill Richardson", "HUCKABEE" = "Mike Huckabee"
)
standardize_name <- function(x) {
  key <- toupper(x)
  unname(ifelse(!is.na(key) & key %in% names(candidate_names), candidate_names[key], x))
}

# ---- Step 1: Read HTML ------------------------------------------------------

doc <- read_html(input_path, encoding = "ISO-8859-1")

# ---- Step 2: National section (one row per non-blank table cell) -----------

national_tables <- xml_find_all(doc, "//table[@cellpadding='0']")
stopifnot(length(national_tables) == 6)

parse_national_cell <- function(td, heading) {
  lines <- flatten_html(as.character(td))
  clean <- strip_urls(lines)
  keep  <- clean != "" & clean != "."
  lines <- lines[keep]
  clean <- clean[keep]
  if (length(clean) == 0) return(NULL)
  
  is_candidate <- heading %in% names(heading_party)
  surname <- if (is_candidate) str_to_title(heading) else NA_character_
  
  if (length(clean) > 1) {
    endorser_name <- clean[1]
    body_lines    <- clean[-1]
    body_raw      <- lines[-1]   # excludes the (sometimes mislinked) name link
  } else {
    # Single-paragraph cell (RWDSU): take the name up to its acronym,
    # e.g. "The Retail, Wholesale and Department Store Union (RWDSU), ..."
    endorser_name <- str_match(clean[1], "^(?:The )?(.+?\\([A-Z]{2,}\\))")[1, 2]
    body_lines    <- clean
    body_raw      <- lines
  }
  
  # A second organization introduced with "Additionally, the ..." (TCU,
  # inside the IAM cell) is split off into its own row.
  pieces <- list(list(name = endorser_name, lines = body_lines, raw = body_raw,
                      note = NA_character_))
  add_idx <- which(str_starts(body_lines, fixed("Additionally, the ")))
  if (length(add_idx) == 1) {
    second_name <- str_match(body_lines[add_idx], "^Additionally, the (.+?\\([A-Z]+\\))")[1, 2]
    first_part  <- seq_len(add_idx - 1)
    second_part <- add_idx:length(body_lines)
    pieces <- list(
      list(name = endorser_name, lines = body_lines[first_part], raw = body_raw[first_part],
           note = NA_character_),
      list(name = second_name, lines = body_lines[second_part], raw = body_raw[second_part],
           note = paste0("split from the ", endorser_name, " cell"))
    )
  }
  
  map_dfr(pieces, function(p) {
    is_org_line <- str_starts(p$lines, "Organization:")
    org_info  <- if (any(is_org_line)) paste(p$lines[is_org_line], collapse = " ") else NA_character_
    narrative <- paste(p$lines[!is_org_line], collapse = " ")
    switch_from <- detect_switch_from(narrative)
    
    tibble(
      section          = "National",
      section_heading  = heading,
      endorsee         = if (is_candidate) heading else NA_character_,
      party            = if (is_candidate) heading_party[[heading]] else NA_character_,
      endorser_name    = p$name,
      endorser_description = "National Labor Organization",
      org_info         = org_info,
      date_raw         = pick_date(narrative, surname),
      all_dates        = all_dates(narrative),
      note             = p$note,
      switch_direction = if (!is.na(switch_from)) "from" else NA_character_,
      switch_candidate = switch_from,
      endorsee_mention = NA_character_,
      evidence_url     = collect_urls(p$raw),
      parsed_ok        = !is.na(p$name) & is_candidate,
      raw_text         = paste(c(if (identical(p$name, endorser_name) && length(clean) > 1) clean[1], p$lines),
                               collapse = " ")
    )
  })
}

national_df <- map_dfr(national_tables, function(tbl) {
  heading <- str_squish(xml_text(xml_find_first(tbl, "preceding::u[1]")))
  cells <- xml_find_all(tbl, "./tbody/tr/td[2] | ./tr/td[2]")
  map_dfr(cells, parse_national_cell, heading = heading)
})
cat("National rows extracted:", nrow(national_df), "\n")

# "NO NATIONAL ENDORSEMENT" (UAW, CWA, SEIU before Feb. 2008) records
# non-endorsements -- excluded.
n_no_endorse <- sum(national_df$section_heading == "NO NATIONAL ENDORSEMENT")
national_df <- national_df %>% filter(section_heading != "NO NATIONAL ENDORSEMENT")
cat("Excluded", n_no_endorse, "NO NATIONAL ENDORSEMENT rows\n")

# ---- Step 3: State/Local and Notes sections --------------------------------
# Both sections are loose paragraphs after the last national table, so they
# are cut out of the <body> markup as one string (from the "State/Local"
# heading to the copyright line) and flattened to lines, keeping <b> as
# {{...}} and <u> as [[...]] so the endorser and endorsee survive.

body_html <- as.character(xml_find_first(doc, "//body"))
start_pos <- str_locate(body_html, fixed(">State/Local<"))[1, "end"]
end_pos   <- str_locate(str_sub(body_html, start_pos), fixed("Copyright"))[1, "start"] + start_pos - 1
stopifnot(!is.na(start_pos), !is.na(end_pos))
region_html <- str_sub(body_html, start_pos, end_pos - 1)

region_lines <- flatten_html(
  region_html,
  marks = c("<b\\b[^>]*>" = "{{", "</b>" = "}}", "<u\\b[^>]*>" = "[[", "</u>" = "]]")
)

remove_marks <- function(x) str_squish(str_remove_all(x, "\\{\\{|\\}\\}|\\[\\[|\\]\\]"))

current_section   <- "State/Local"
current_candidate <- NA_character_
entries <- list()

for (line in region_lines) {
  marked <- strip_urls(line)
  plain  <- remove_marks(marked)
  
  if (plain %in% c("", "State/Local")) next
  if (plain == "Notes:") {
    current_section   <- "Notes"
    current_candidate <- NA_character_
    next
  }
  
  # Candidate heading: a line that is only an all-caps underlined name
  header_match <- str_match(marked, "^\\[\\[\\s*([A-Z' ]+?)\\s*\\]\\]$")
  if (current_section == "State/Local" && !is.na(header_match[1, 2])) {
    current_candidate <- header_match[1, 2]
    next
  }
  
  starts_entry <- str_starts(plain, ">") || (current_section == "Notes" && str_starts(plain, "-"))
  if (starts_entry || length(entries) == 0) {
    entries[[length(entries) + 1]] <- list(
      section = current_section, candidate = current_candidate,
      marked = marked, lines = line
    )
  } else {
    # Continuation of the previous entry (e.g. the UFCW Local 1500 entry is
    # split across a <br>, and the AFT Connecticut note spans several lines)
    n <- length(entries)
    entries[[n]]$marked <- paste(entries[[n]]$marked, marked)
    entries[[n]]$lines  <- c(entries[[n]]$lines, line)
  }
}

local_df <- map_dfr(entries, function(e) {
  bold      <- str_match_all(e$marked, "\\{\\{(.*?)\\}\\}")[[1]][, 2]
  underline <- str_match_all(e$marked, "\\[\\[(.*?)\\]\\]")[[1]][, 2]
  plain     <- str_squish(str_remove(remove_marks(e$marked), "^[>-]\\s*"))
  is_note   <- e$section == "Notes"
  cand      <- e$candidate
  switch_from <- detect_switch_from(plain)
  endorser  <- if (length(bold) > 0) str_squish(bold[1]) else NA_character_
  
  tibble(
    section          = e$section,
    section_heading  = if (is_note) "Notes" else cand,
    endorsee         = if (is_note) NA_character_ else cand,
    party            = if (!is_note && cand %in% names(heading_party)) heading_party[[cand]] else NA_character_,
    endorser_name    = endorser,
    endorser_description = if (is_note) NA_character_ else "State/Local Labor Organization",
    org_info         = NA_character_,
    date_raw         = str_extract(plain, date_re),
    all_dates        = all_dates(plain),
    note             = NA_character_,
    switch_direction = if (!is.na(switch_from)) "from" else NA_character_,
    switch_candidate = switch_from,
    endorsee_mention = if (length(underline) > 0) paste(str_squish(underline), collapse = "; ") else NA_character_,
    evidence_url     = collect_urls(e$lines),
    parsed_ok        = !is_note & !is.na(endorser),
    raw_text         = if (is_note) paste0("[NOTE] ", plain) else plain
  )
})
cat("State/Local and Notes rows extracted:", nrow(local_df), "\n")

# Notes describe non-endorsements (Change to Win roster, USW holding off,
# CWA holding off, AFT Connecticut's "favorite son" resolution) -- excluded,
# except the NY AFL-CIO resolution when keep_favorite_son_resolutions = TRUE.
favorite_sister <- local_df %>%
  filter(section == "Notes", endorser_name == "New York State AFL-CIO") %>%
  mutate(
    section = "State/Local", section_heading = "CLINTON",
    endorsee = "CLINTON", party = "D",
    endorser_description = "State/Local Labor Organization",
    note = 'resolution declaring Clinton its "favorite sister"; not a formal endorsement',
    parsed_ok = TRUE,
    raw_text = str_remove(raw_text, "^\\[NOTE\\] ")
  )
cat("Excluded", sum(local_df$section == "Notes"), "Notes rows\n")
local_df <- local_df %>% filter(section != "Notes")
if (keep_favorite_son_resolutions) local_df <- bind_rows(local_df, favorite_sister)

# Split paragraphs that announce several endorsers at once:
#   "Ten SEIU State Councils ... California (656,000 members), ..." -> 10 rows
#   "SEIU Locals 1199 and 32BJ"                                       -> 2 rows
expand_local_row <- function(row) {
  if (identical(row$endorser_name, "Ten SEIU State Councils")) {
    m <- str_match_all(row$raw_text, "([A-Z][a-z]+(?: [A-Z][a-z]+)?) \\(([0-9,]+) members\\)")[[1]]
    stopifnot(nrow(m) == 10)
    return(row[rep(1, nrow(m)), ] %>%
             mutate(endorser_name = paste0("SEIU ", m[, 2], " State Council"),
                    note = paste0(m[, 3], " members; one of ten SEIU state councils announced together")))
  }
  locals <- str_match(row$endorser_name, "^(.+?) Locals (\\S+) and (\\S+)$")
  if (!is.na(locals[1, 1])) {
    return(row[c(1, 1), ] %>%
             mutate(endorser_name = paste0(locals[1, 2], " Local ", c(locals[1, 3], locals[1, 4])),
                    note = "announced together in one paragraph"))
  }
  row
}
local_df <- map_dfr(seq_len(nrow(local_df)), ~ expand_local_row(local_df[.x, ]))

# ---- Step 4: Combine, add constant fields, order columns -------------------

df <- bind_rows(national_df, local_df) %>%
  mutate(
    endorsee = standardize_name(endorsee),
    switch_candidate = standardize_name(switch_candidate),
    record_type = "endorsement",   # no retractions on this page
    contest_id = if_else(!is.na(party), paste0("2008", party), NA_character_),
    year = 2008,
    endorser_party_note = NA_character_,
    state = NA_character_,
    district = NA_character_,
    raw_text = if_else(!parsed_ok & !str_starts(raw_text, fixed("[NOTE]")),
                       paste0("[UNMATCHED] ", raw_text), raw_text)
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # 2008-labor-specific columns (kept for review; see header comments).
    # section_heading keeps the candidate heading exactly as on the page.
    section, section_heading, endorsee_mention, org_info, all_dates
  )

# ---- Step 5: Validation checkpoints, report, and write out -----------------
# Expected counts from manual inspection of the page:
#   National: 32 -- Clinton 15 (13 logo rows + RWDSU + TCU split from IAM),
#     Obama 11, Edwards 4, Dodd 1, Huckabee 1. (3 NO NATIONAL ENDORSEMENT
#     rows excluded.)
#   State/Local: 41 -- Biden 6, Clinton 7 (SEIU 1199 and 32BJ split),
#     Edwards 14 (Ten SEIU State Councils split), Obama 13, Richardson 1.
#     (+1 Clinton if keep_favorite_son_resolutions = TRUE.)
#   Notes: 0 (excluded).

cat("\nRows per section and candidate:\n")
print(count(df, section, endorsee))

stopifnot(
  sum(df$section == "National") == 32,
  sum(df$section == "State/Local") == 41 + keep_favorite_son_resolutions,
  sum(df$section == "Notes") == 0,
  all(!is.na(df$endorsee))
)

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) need manual review (no endorsee, no endorser, or a Notes row):\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text) %>% str_trunc(110))

cat("\nParsed rows with no date found:\n")
print(df %>% filter(parsed_ok, is.na(date_raw)) %>% select(endorsee, endorser_name))

cat("\nRows with a detected switch:\n")
print(df %>% filter(!is.na(switch_direction)) %>% select(section, endorsee, endorser_name, switch_candidate))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")