# ============================================================================
# Extract national-organization endorsements from Democracy in Action (2008)
#
# Source page: "Endorsements by National Organizations in the 2008
# Presidential Primaries"
# Input: data/raw/Democracy In Action/dia_2008_p2008_organizations.html
# Output: data/raw/Democracy In Action/dia_2008_organizations_extracted.csv
#
# Much simpler and cleaner than the 2008 newspaper page -- one small table
# with two columns (Democratic candidates on the left, Republican on the
# right), each holding a candidate header (bold+underlined, e.g. "Clinton",
# "Obama", "F.Thompson") followed by a run of entries shaped like:
#   "<a href=...>Org Name</a> (Month Day, Year)"
# with an occasional plain-text entry (no link) or an abbreviation
# parenthetical alongside the date, e.g. "Republicans for Environmental
# Protection (REP) (Oct. 14, 2007)".
#
# Reuses the same body-level line-flattening approach as the 2008 newspaper
# script (tokenize <a>/<br>, and treat <p>/<div>/<tr>/<td>/<table>
# boundaries as line breaks too, since <br> alone is not always present
# between a header and its first entry on these 2008-era pages).
#
# NOTE on source quirks:
#   - "Republicans for Environmental Protection (REP)" and "U.S. Airport and
#     Seaport Police, a member of the International Association of Airport
#     and Seaport Police (IAASP)" each carry a second, non-date parenthetical
#     (an abbreviation) alongside the date -- kept in `note`, not discarded.
#   - "National Women's Political Caucus (April 2007)" has no day, just a
#     month and year, and no link -- both are handled: the date pattern
#     accepts a bare "Month Year", and evidence_url is simply blank when no
#     link exists.
#   - A stray, text-less <a href="...ahsa041608pr.html"></a> repeats the
#     American Hunters and Shooters Association link right after that
#     section closes -- dropped, same as the equivalent artifact handled in
#     the 2012 organizations script.
#   - This page covers both parties (Clinton/Edwards/Obama are Democratic;
#     Giuliani/Huckabee/McCain/F.Thompson are Republican), so contest_id and
#     party are set per-candidate, as with the 2012 organizations script.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ------------------------------------------------------------
input_path  <- "data/raw/Democracy In Action/dia_2008_p2008_organizations.html"
output_path <- "data/raw/Democracy In Action/dia_2008_organizations_extracted.csv"

# ---- Helper: flatten the whole <body> into <br>-and-block-separated lines --
link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>', dotall = TRUE)

body_to_lines <- function(body_node) {
  html_str <- as.character(body_node)
  html_str <- str_replace_all(html_str, link_token_re, "\\2@@URL[\\1]@@")
  html_str <- str_replace_all(html_str, "<br\\b[^>]*>", "@@BR@@")
  html_str <- str_replace_all(html_str, "</?(?:p|div|tr|td|table)\\b[^>]*>", "@@BR@@")
  html_str <- str_remove_all(html_str, "<[^>]+>")
  for (pair in list(c("&nbsp;", " "), c("&amp;", "&"), c("&copy;", "(c)"))) {
    html_str <- str_replace_all(html_str, fixed(pair[1]), pair[2])
  }
  html_str <- str_replace_all(html_str, "\\s+", " ")
  
  lines <- str_split(html_str, fixed("@@BR@@"))[[1]]
  lines <- str_trim(lines)
  lines[lines != ""]
}

url_token_re <- regex("@@URL\\[([^\\]]*)\\]@@")

candidate_party <- c(
  "Clinton" = "D", "Edwards" = "D", "Obama" = "D",
  "Giuliani" = "R", "Huckabee" = "R", "McCain" = "R", "F.Thompson" = "R"
)
skip_exact <- c("Endorsements by National Organizations in the 2008 Presidential Primaries")

# Dates on this page are "Month Day, Year" (most entries) or a bare
# "Month Year" with no day (one entry, "National Women's Political Caucus").
mdy_date_re <- "[A-Za-z]+\\.?\\s+\\d{1,2},\\s*\\d{4}"
my_date_re  <- "[A-Za-z]+\\.?\\s+\\d{4}"
date_re <- regex(paste0("(?:", mdy_date_re, ")|(?:", my_date_re, ")"))
paren_span_re <- "\\([^()]*\\)"

parse_entry <- function(raw_line) {
  url_match <- str_match(raw_line, url_token_re)
  evidence_url <- url_match[1, 2]
  text <- str_squish(str_remove(raw_line, url_token_re))
  
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
  
  remainder <- paste0(
    str_sub(text, 1, spans[date_idx, "start"] - 1),
    str_sub(text, spans[date_idx, "end"] + 1, str_length(text))
  )
  remainder <- str_squish(remainder)
  
  # Any other leftover "(...)" -- an abbreviation like "(REP)" or "(IAASP)"
  # -- is kept as a note rather than discarded.
  other_notes <- character(0)
  other_matches <- str_match_all(remainder, paren_span_re)[[1]]
  if (length(other_matches) > 0) other_notes <- str_sub(other_matches[, 1], 2, -2)
  remainder <- str_squish(str_remove_all(remainder, paren_span_re))
  
  name <- str_remove(remainder, "^[,\\s-]+")
  name <- str_remove(name, "[,\\s-]+$")
  if (!nzchar(name)) return(list(parsed_ok = FALSE))
  
  note_pieces <- c(note_in_date_paren, other_notes)
  note_pieces <- note_pieces[!is.na(note_pieces) & str_length(note_pieces) > 0]
  note <- if (length(note_pieces) > 0) paste(note_pieces, collapse = "; ") else NA_character_
  
  list(endorser_name = name, date_raw = date_raw, note = note,
       evidence_url = evidence_url, parsed_ok = TRUE)
}

# ---- Step 1: Read HTML and flatten the whole body into lines --------------

doc  <- read_html(input_path, encoding = "ISO-8859-1")
body <- html_element(doc, "body")

all_lines <- body_to_lines(body)
cat("Total lines found:", length(all_lines), "\n")

# ---- Step 2: Walk the lines as a state machine ----------------------------

current_candidate <- NA_character_
current_party     <- NA_character_
rows <- list()

for (line in all_lines) {
  clean_line <- str_squish(str_remove(line, url_token_re))
  
  if (clean_line %in% skip_exact ||
      str_starts(tolower(clean_line), "see also") ||
      str_starts(tolower(clean_line), "copyright")) next
  if (clean_line == "") next  # stray text-less link artifacts
  
  if (clean_line %in% names(candidate_party)) {
    current_candidate <- clean_line
    current_party     <- candidate_party[[clean_line]]
    next
  }
  
  if (is.na(current_candidate)) {
    rows[[length(rows) + 1]] <- tibble(
      party = NA_character_, endorsee = NA_character_, endorser_name = NA_character_,
      date_raw = NA_character_, note = NA_character_, evidence_url = NA_character_,
      parsed_ok = FALSE, raw_text = paste0("[UNMATCHED] ", clean_line)
    )
    next
  }
  
  parsed <- parse_entry(line)
  if (isTRUE(parsed$parsed_ok)) {
    rows[[length(rows) + 1]] <- tibble(
      party = current_party, endorsee = current_candidate,
      endorser_name = parsed$endorser_name, date_raw = parsed$date_raw, note = parsed$note,
      evidence_url = parsed$evidence_url, parsed_ok = TRUE, raw_text = clean_line
    )
  } else {
    rows[[length(rows) + 1]] <- tibble(
      party = current_party, endorsee = current_candidate, endorser_name = NA_character_,
      date_raw = NA_character_, note = NA_character_, evidence_url = NA_character_,
      parsed_ok = FALSE, raw_text = paste0("[UNMATCHED] ", clean_line)
    )
  }
}

df <- bind_rows(rows) %>%
  mutate(
    contest_id = if_else(!is.na(party), paste0("2008", party), NA_character_),
    year = 2008,
    endorser_description = "National Organization",
    endorser_party_note = NA_character_,
    state = NA_character_,
    district = NA_character_,
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

cat("\nEndorsements per candidate:\n")
print(count(df, endorsee, sort = TRUE))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")