# ============================================================================
# Extract labor-organization endorsements from Democracy in Action (2004)
#
# Source page: "Labor Endorsements in the Race for the 2004 Democratic
# Nomination"
# Input: data/raw/Democracy in Action/dia_2004_labor.html
# Output: data/raw/Democracy in Action/extracted/dia_2004_labor_extracted.csv
#
# The page states that it "only reflects endorsements during the period when
# the nomination was being contested, up through to the AFL-CIO's
# endorsement of Sen. Kerry on February 19, 2004."
#
# This page has three regions, handled in three passes:
#   1. The AFL-CIO's own endorsement of Kerry, written as an intro paragraph
#      under "Supporting Kerry" rather than as a table row -- extracted as
#      its own row.
#   2. National unions -- seven <table cols="2"> blocks. Each row is one
#      union: logo in td[1]; in td[2] a short name (first line), a grey
#      "XX Organization:" line (leadership), then a narrative paragraph with
#      the endorsement date. Tables sit under two levels of heading:
#        candidate:  "Supporting Kerry", "Supporting Edwards",
#                    "Supported Dean", "Supported Gephardt"  (<u>, size +1)
#        subsection: "AFL-CIO Affiliated National Unions", "Also",
#                    "Independent National Unions (and Groups)"  (<b><u>)
#      Both are found with "preceding::" XPath (nearest heading above the
#      table), the same approach as the 2008 labor script.
#   3. State and Locals -- one line per organization under an underlined
#      candidate name, usually ending "...announced <date>".
#
# NOTE on dates (national section): date_raw is the first date in the first
# sentence that names the section's candidate (e.g. "On February 9, 2004 the
# Amalgamated Transit Union endorsed Sen. John Kerry"). Every date found is
# kept in all_dates so the choice can be checked.
#
# NOTE on context lines (State and Locals): a line ending in ":" introduces
# the lines after it -- "Recommendations of:" (Edwards) and "A coalition of
# Connecticut labor unions endorsed Sen. Joe Lieberman on June 10, 2003:".
# That text is copied into `note` for each following row in the same
# paragraph, and the coalition's date is used as date_raw for its members.
# Small-print follow-up lines (<font size=-2>, e.g. the CTA explanation) are
# appended to the previous row's note.
#
# Decisions applied in this script (Oct. 2026):
#   - Retractions are coded: AFSCME's "Withdrew endorsement on February 7,
#     2004" becomes a second AFSCME row with record_type = "retraction".
#   - Rows covering several endorsers are split ("UFCW Local 328, UFCW Local
#     1459, UFCW Local 56" -> 3 rows).
#   - endorsee and switch_candidate use standardized full names ("John
#     Kerry"); the page's own heading is kept in section_heading.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - AFSCME and SEIU are listed under "Supported Dean"; AFSCME withdrew
#     (see the retraction row above).
#   - Amalgamated Transit Union appears twice: under Gephardt (Oct. 1, 2003)
#     and under Kerry (Feb. 9, 2004, "had endorsed Rep. Dick Gephardt"), so
#     the Kerry row gets switch_direction = "from", switch_candidate =
#     "Gephardt". Same for the Alliance for Economic Justice.
#   - The IAFF cell is followed by a separate table row holding only
#     "www.firefightersforkerry.com10/22/03" -- added to the IAFF row's note.
#   - Plumbers and Pipefitters (Kerry) and MEBA (Gephardt) give no date.
#   - The three UFCW locals (Kerry) have no date.
#   - "Laborers' Local 383 (Phoenix) - Lieberman" is a separate paragraph
#     after the Connecticut coalition list, so it does NOT inherit the
#     coalition's note or date.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2004_labor.html"
output_path <- "data/raw/Democracy in Action/extracted/dia_2004_labor_extracted.csv"

# ---- Helper functions -------------------------------------------------------

# Marker technique shared with the other DIA scripts: rewrite links and
# breaks as plain-text markers before stripping tags. Links become
# "text@@URL[href]@@". `marks` (optional) keeps chosen tags visible.
link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
                       dotall = TRUE, ignore_case = TRUE)
url_token_re  <- regex("@@URL\\[([^\\]]*)\\]@@")
block_tag_re  <- regex("</?(?:p|div|tr|td|th|table|tbody|li|ul|center|blockquote|h1|h2|h3)\\b[^>]*>",
                       ignore_case = TRUE)

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
  frag <- read_html(paste0("<html><body><div>", html_str, "</div></body></html>"),
                    encoding = "UTF-8")
  txt <- xml_text(frag)
  txt <- str_replace_all(txt, "\u00a0", " ")
  txt <- str_replace_all(txt, "\\s+", " ")
  lines <- str_trim(str_split(txt, fixed("@@BR@@"))[[1]])
  lines[lines != ""]
}

strip_urls <- function(x) str_squish(str_remove_all(x, url_token_re))

collect_urls <- function(lines) {
  urls <- unlist(map(lines, ~ str_match_all(.x, url_token_re)[[1]][, 2]))
  urls <- unique(urls[!is.na(urls) & urls != ""])
  if (length(urls) == 0) NA_character_ else paste(urls, collapse = "; ")
}

# Dates: "February 9, 2004" (national) and "Dec. 6, 2003" (state/local)
month_re <- "(?:January|February|March|April|May|June|July|August|September|October|November|December|Jan\\.|Feb\\.|Mar\\.|Apr\\.|Aug\\.|Sept\\.|Sep\\.|Oct\\.|Nov\\.|Dec\\.)"
date_re  <- regex(paste0(month_re, "\\s+\\d{1,2},\\s*\\d{4}"))

all_dates <- function(text) {
  d <- str_extract_all(text, date_re)[[1]]
  if (length(d) == 0) NA_character_ else paste(d, collapse = "; ")
}

# Split prose into sentences without breaking on "Sen.", "Rep.", "Jan.",
# "U.S." etc.: protect those periods, split, then restore them.
abbrev_re <- regex("\\b(Sen|Rep|Gov|Jr|Sr|Dr|Mr|Mrs|Ms|St|Jan|Feb|Mar|Apr|Aug|Sept|Sep|Oct|Nov|Dec|Inc|No|Ave)\\.")
split_sentences <- function(text) {
  protected <- str_replace_all(text, abbrev_re, "\\1<DOT>")
  protected <- str_replace_all(protected, fixed("U.S."), "U<DOT>S<DOT>")
  pieces <- str_split(protected, "(?<=[.!?\\]])\\s+(?=[A-Z(\\[])")[[1]]
  str_replace_all(pieces, fixed("<DOT>"), ".")
}

# First date in the first sentence mentioning the candidate; else first date.
pick_date <- function(text, surname) {
  for (s in split_sentences(text)) {
    if (str_detect(s, fixed(surname)) && str_detect(s, date_re)) {
      return(str_extract(s, date_re))
    }
  }
  str_extract(text, date_re)
}

# "ATU had endorsed Rep. Dick Gephardt", "had previously backed Rep. Dick Gephardt".
# Only the leading phrase is case-insensitive; the name part is not.
switch_from_re <- regex(
  "(?i:originally endorsed|had endorsed|had previously backed|previously backed)\\s+(?:former\\s+)?(?:Sen\\.|Rep\\.|Gov\\.)?\\s*(?:[A-Z][a-z]+\\s+)?([A-Z][a-z]+)"
)
detect_switch_from <- function(text) str_match(text, switch_from_re)[1, 2]

# Candidate surnames on the page -> standardized full names.
# Names not in this table are returned unchanged.
candidate_names <- c(
  "CLARK" = "Wesley Clark", "DEAN" = "Howard Dean", "EDWARDS" = "John Edwards",
  "GEPHARDT" = "Dick Gephardt", "KERRY" = "John Kerry",
  "KUCINICH" = "Dennis Kucinich", "LIEBERMAN" = "Joe Lieberman"
)
standardize_name <- function(x) {
  key <- toupper(x)
  unname(ifelse(!is.na(key) & key %in% names(candidate_names), candidate_names[key], x))
}

# ---- Step 1: Read HTML ------------------------------------------------------

doc <- read_html(input_path, encoding = "ISO-8859-1")

# ---- Step 2: AFL-CIO intro paragraph ----------------------------------------

intro_node <- xml_find_first(
  doc, "//font[starts-with(normalize-space(.), 'On February 19, 2004 the General Board')]"
)
stopifnot(!inherits(intro_node, "xml_missing"))
intro_lines <- flatten_html(as.character(intro_node))
intro_text  <- strip_urls(paste(intro_lines, collapse = " "))

intro_df <- tibble(
  section = "National", section_heading = "Supporting Kerry",
  subsection = "Intro paragraph",
  endorsee = "Kerry", endorser_name = "AFL-CIO",
  endorser_description = "National Labor Federation",
  org_info = NA_character_,
  date_raw = str_extract(intro_text, date_re),
  all_dates = all_dates(intro_text),
  note = NA_character_,
  record_type = "endorsement",
  switch_direction = NA_character_, switch_candidate = NA_character_,
  evidence_url = collect_urls(intro_lines),
  parsed_ok = TRUE,
  raw_text = intro_text
)

# ---- Step 3: National tables ------------------------------------------------

national_tables <- xml_find_all(doc, "//table")
stopifnot(length(national_tables) == 7)

parse_national_cell <- function(td, heading, subsection) {
  lines <- flatten_html(as.character(td))
  clean <- strip_urls(lines)
  keep  <- clean != ""
  lines <- lines[keep]
  clean <- clean[keep]
  if (length(clean) == 0) return(NULL)
  
  endorsee <- word(heading, -1)   # "Supporting Kerry" -> "Kerry"
  endorser_name <- clean[1]
  
  # Leadership text: the "XX Organization:" line, plus any wrapped
  # continuation lines before the narrative starts (BCTGM's wraps).
  org_lines <- character(0)
  narrative_lines <- character(0)
  for (ln in clean[-1]) {
    is_org <- str_detect(ln, fixed("Organization:"))
    continues_org <- length(org_lines) > 0 && length(narrative_lines) == 0 &&
      !str_detect(ln, "endors|Withdrew|backed|^On ")
    if (is_org || continues_org) {
      org_lines <- c(org_lines, ln)
    } else {
      narrative_lines <- c(narrative_lines, ln)
    }
  }
  narrative <- paste(narrative_lines, collapse = " ")
  switch_from <- detect_switch_from(narrative)
  has_org_line <- length(org_lines) > 0
  
  main <- tibble(
    section          = "National",
    section_heading  = heading,
    subsection       = subsection,
    endorsee         = endorsee,
    endorser_name    = endorser_name,
    endorser_description = "National Labor Organization",
    org_info         = if (has_org_line) paste(org_lines, collapse = " ") else NA_character_,
    date_raw         = pick_date(narrative, endorsee),
    all_dates        = all_dates(narrative),
    note             = NA_character_,
    record_type      = "endorsement",
    switch_direction = if (!is.na(switch_from)) "from" else NA_character_,
    switch_candidate = switch_from,
    evidence_url     = collect_urls(lines[-1]),   # excludes the union homepage link
    # A real union cell always has an "Organization:" line; the stray
    # firefightersforkerry.com row does not (it is folded into IAFF later).
    parsed_ok        = has_org_line,
    raw_text         = paste(clean, collapse = " ")
  )
  
  # "Withdrew endorsement on February 7, 2004." (AFSCME, under Dean) -> an
  # extra retraction row with the withdrawal date and its own link.
  withdraw_idx <- which(str_starts(clean, "Withdrew endorsement"))
  if (length(withdraw_idx) == 1) {
    retraction <- main %>% mutate(
      record_type  = "retraction",
      date_raw     = str_extract(clean[withdraw_idx], date_re),
      all_dates    = date_raw,
      note         = clean[withdraw_idx],
      evidence_url = collect_urls(lines[withdraw_idx])
    )
    return(bind_rows(main, retraction))
  }
  main
}

national_df <- map_dfr(national_tables, function(tbl) {
  heading    <- str_squish(xml_text(xml_find_first(tbl, "preceding::u[.//font[@size='+1']][1]")))
  subsection <- str_squish(xml_text(xml_find_first(tbl, "preceding::b[u][1]")))
  cells <- xml_find_all(tbl, "./tr/td[2] | ./tbody/tr/td[2]")
  map_dfr(cells, parse_national_cell, heading = heading, subsection = subsection)
})
cat("National table rows extracted:", nrow(national_df), "\n")

# Rows without an "Organization:" line are not unions -- in practice the
# stray "www.firefightersforkerry.com10/22/03" row right after IAFF. Its text
# is added to the previous row's note, then the row is dropped.
stray <- which(!national_df$parsed_ok)
stopifnot(length(stray) == 1)
for (i in rev(stray)) {
  stopifnot(i > 1)
  national_df$note[i - 1] <- paste(na.omit(c(national_df$note[i - 1], national_df$raw_text[i])),
                                   collapse = " | ")
}
national_df <- national_df[-stray, ]

# ---- Step 4: State and Locals -------------------------------------------------
# Cut the section out of the <body> markup (from its heading to the
# copyright line) and flatten it, keeping:
#   <u> as [[...]]           -> candidate headings
#   <p> as @@PARA@@          -> paragraph starts (context lines reset here)
#   <font size="-2"> as ~~SMALL~~ -> small-print follow-up lines

body_html <- as.character(xml_find_first(doc, "//body"))
start_pos <- str_locate(body_html, fixed(">State and Locals<"))[1, "end"]
end_pos   <- str_locate(str_sub(body_html, start_pos), fixed("Copyright"))[1, "start"] + start_pos - 1
stopifnot(!is.na(start_pos), !is.na(end_pos))
region_html <- str_sub(body_html, start_pos, end_pos - 1)

region_lines <- flatten_html(
  region_html,
  marks = c(
    "<p\\b[^>]*>" = "@@BR@@@@PARA@@",
    "<font\\b[^>]*size=\"-2\"[^>]*>" = "~~SMALL~~",
    "<u\\b[^>]*>" = "[[", "</u>" = "]]"
  )
)

# "...announced Dec. 6, 2003", "...recommendation announced ...",
# "...endorsement formally announced ...", ". ..announced ..."
announced_re <- regex("\\s*\\.?\\s*\\.{2,3}\\s*([a-z ]*announced)\\s+(.+?)\\s*$")
# A trailing "(...)" detail group, allowing one level of nested parentheses
trailing_paren_re <- regex("^(.*?)\\s*\\(([^()]*(?:\\([^()]*\\)[^()]*)*)\\)$")

current_candidate <- NA_character_
current_context   <- NA_character_
local_rows <- list()

for (line in region_lines) {
  is_para  <- str_detect(line, fixed("@@PARA@@"))
  is_small <- str_detect(line, fixed("~~SMALL~~"))
  marked   <- strip_urls(str_remove_all(line, "@@PARA@@|~~SMALL~~"))
  plain    <- str_squish(str_remove_all(marked, "\\[\\[|\\]\\]"))
  
  if (is_para) current_context <- NA_character_   # context ends at a new <p>
  if (plain == "") next
  
  header_match <- str_match(marked, "^\\[\\[\\s*(.+?)\\s*\\]\\]$")
  if (!is.na(header_match[1, 2])) {
    current_candidate <- header_match[1, 2]
    current_context   <- NA_character_
    next
  }
  
  if (str_ends(plain, ":")) {          # introduces the lines after it
    current_context <- plain
    next
  }
  
  if (is_small && length(local_rows) > 0) {   # follow-up note to previous row
    n <- length(local_rows)
    local_rows[[n]]$note <- paste(na.omit(c(local_rows[[n]]$note, plain)), collapse = " | ")
    local_rows[[n]]$raw_text <- paste(local_rows[[n]]$raw_text, plain)
    next
  }
  
  tail_match <- str_match(plain, announced_re)
  name_part  <- if (!is.na(tail_match[1, 1])) str_sub(plain, 1, str_length(plain) - str_length(tail_match[1, 1])) else plain
  name_part  <- str_squish(name_part)
  
  # Move a trailing "(...)" detail (leadership, membership, location) into
  # `note`, except "(Local ...)" / "(District ...)", which are part of the name.
  paren_match <- str_match(name_part, trailing_paren_re)
  if (!is.na(paren_match[1, 1]) && !str_detect(paren_match[1, 3], "^(Local|District)\\b")) {
    endorser_name <- str_squish(paren_match[1, 2])
    detail        <- paren_match[1, 3]
  } else {
    endorser_name <- name_part
    detail        <- NA_character_
  }
  
  date_raw <- if (!is.na(tail_match[1, 3])) tail_match[1, 3] else NA_character_
  if (is.na(date_raw) && !is.na(current_context)) date_raw <- str_extract(current_context, date_re)
  
  note_parts <- c(current_context, detail,
                  if (!is.na(tail_match[1, 2]) && tail_match[1, 2] != "announced") tail_match[1, 2] else NA)
  note_parts <- note_parts[!is.na(note_parts)]
  
  local_rows[[length(local_rows) + 1]] <- list(
    section = "State and Locals", section_heading = current_candidate,
    subsection = NA_character_,
    endorsee = current_candidate, endorser_name = endorser_name,
    endorser_description = "State/Local Labor Organization",
    org_info = NA_character_,
    date_raw = date_raw, all_dates = all_dates(paste(plain, current_context)),
    note = if (length(note_parts) > 0) paste(note_parts, collapse = " | ") else NA_character_,
    record_type = "endorsement",
    switch_direction = NA_character_, switch_candidate = NA_character_,
    evidence_url = collect_urls(line),
    parsed_ok = !is.na(current_candidate),
    raw_text = plain
  )
}

local_df <- bind_rows(map(local_rows, as_tibble))
cat("State and Locals rows extracted:", nrow(local_df), "\n")

# One line naming several locals ("UFCW Local 328, UFCW Local 1459, UFCW
# Local 56") -> one row per local.
expand_local_row <- function(row) {
  parts <- str_split(row$endorser_name, ",\\s*")[[1]]
  if (length(parts) > 1 && all(str_detect(parts, "\\bLocal \\d+$"))) {
    return(row[rep(1, length(parts)), ] %>%
             mutate(endorser_name = parts, note = "listed together in one line"))
  }
  row
}
local_df <- map_dfr(seq_len(nrow(local_df)), ~ expand_local_row(local_df[.x, ]))

# ---- Step 5: Combine, add constant fields, order columns -------------------

df <- bind_rows(intro_df, national_df, local_df) %>%
  mutate(
    endorsee = standardize_name(endorsee),
    switch_candidate = standardize_name(switch_candidate),
    contest_id = "2004D",
    year = 2004,
    party = "D",
    endorser_party_note = NA_character_,
    state = NA_character_,
    district = NA_character_,
    raw_text = if_else(parsed_ok, raw_text, paste0("[UNMATCHED] ", raw_text))
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, record_type, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    # 2004-labor-specific columns (kept for review; see header comments).
    # section_heading keeps the page's heading, e.g. "Supported Dean".
    section, section_heading, subsection, org_info, all_dates
  )

# ---- Step 6: Validation checkpoints, report, and write out -----------------
# Expected counts from manual inspection of the page:
#   Intro: 1 (AFL-CIO).
#   National: 37 -- Kerry 11, Edwards 1, Dean 4 (3 endorsements + the
#     AFSCME retraction), Gephardt 21. (The stray IAFF website row is
#     folded into the IAFF note.)
#   State and Locals: 40 -- Clark 1, Dean 6, Edwards 3, Gephardt 13,
#     Kerry 8 (UFCW locals split into 3), Kucinich 1, Lieberman 8.

cat("\nRows per section, candidate and record type:\n")
print(count(df, section, endorsee, record_type))

stopifnot(
  nrow(intro_df) == 1,
  nrow(national_df) == 37,
  nrow(local_df) == 40,
  sum(df$record_type == "retraction") == 1
)

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text) %>% str_trunc(110))

cat("\nParsed rows with no date found:\n")
print(df %>% filter(parsed_ok, is.na(date_raw)) %>% select(section, endorsee, endorser_name))

cat("\nRows with a detected switch:\n")
print(df %>% filter(!is.na(switch_direction)) %>% select(endorsee, endorser_name, switch_candidate))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")