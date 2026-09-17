# ============================================================================
# Extract national-organization endorsements from Democracy in Action (2012)
#
# Source page: "Endorsements by National Organizations in the 2012 Campaign"
# Input: data/raw/Democracy in Action/dia_2012_p2012_organizations.html
# Output: data/raw/Democracy in Action/dia_2012_organizations_extracted.csv
#
# Much simpler structure than the officials/newspaper pages: each entry is
# one <br>-separated line of the shape
#   "<a href=...>Org Name</a>&nbsp; <date MM/DD/YY>"
# grouped under a candidate header (<big>Barack Obama</big>, etc.), with one
# sub-grouping label -- "Organized Labor" -- splitting Obama's labor-union
# endorsements out from his other organizational endorsements. There's no
# per-state contest structure here (everything is a single national
# endorsement), so -- unlike the newspaper page -- there's no contest-level
# metadata to track or drop.
#
# NOTE: unlike the newspaper/officials pages (Republican-only or single-
# schema), this page covers BOTH parties: Obama (D, general election
# incumbent) and Romney/Gingrich/Santorum (R). contest_id and party are
# therefore assigned per-candidate rather than being constant for the file.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - "Sierra Club, League of Conservation Voters, Environment Action, Clean
#     Water Action" is one <a> covering four organizations with a single
#     shared date -- kept as one row, name uncleaned, same as how the
#     newspaper script kept "Seacoast Media Group - Portsmouth Herald,
#     Hampton Union and Exeter News-Letter" as a single compound entry.
#   - "National Right to LIfe" has a second, empty <a href="abc022212pr.html">
#     immediately after it in the source -- an apparent copy-paste artifact
#     (that same href is the real link for "Associated Builders and
#     Contractors" a few lines later). Only the FIRST link on a line is kept
#     as evidence_url, so this doesn't miscount as separate lines.
#   - A stray, text-less <a href="../../interestg/hrcpac052611pr.html"></a>
#     sits right after the Obama org list closes -- a leftover duplicate of
#     the Human Rights Campaign link with no visible text. Lines with no
#     visible content after link-tokens are stripped are dropped entirely
#     (they're markup noise, not a missed data row).
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2012_p2012_organizations.html"
output_path <- "data/raw/Democracy in Action/dia_2012_organizations_extracted.csv"

# ---- Helper: split one <p> node into <br>-separated lines, tokenizing
# links first -- identical technique to the newspaper script, reused here
# because this page also nests some content (the Obama/Romney headers) a
# level down from the <p>, so a direct-child-only <br> split isn't safe.
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

url_token_re <- regex("@@URL\\[([^\\]]*)\\]@@")

# ---- Step 1: Read HTML and flatten every <p class="blurb"> into lines -----

doc <- read_html(input_path)
overview <- html_element(doc, "#overview")
p_nodes  <- html_elements(overview, "p.blurb")

all_lines <- unlist(map(p_nodes, p_to_lines))
cat("Total <br>-separated lines found:", length(all_lines), "\n")

# ---- Step 2: Walk the lines as a state machine ----------------------------
#
# Candidate headers set both the endorsee and (since this page spans both
# parties) the party/contest_id; the "Organized Labor" sub-header only
# resets when a new candidate header appears, matching the source's actual
# grouping (it's specific to the Obama section on this page).

candidate_party <- c(
  "Barack Obama"  = "D",
  "Mitt Romney"   = "R",
  "Newt Gingrich" = "R",
  "Rick Santorum" = "R"
)
skip_lines        <- c("Endorsements by Organizations", "primaries")
subcategory_headers <- c("Organized Labor")
entry_re <- regex("^(?<name>.+?)\\s+(?<date>\\d{1,2}/\\d{1,2}/\\d{2})$")

current_candidate    <- NA_character_
current_party        <- NA_character_
current_subcategory  <- NA_character_
rows <- list()

for (line in all_lines) {
  clean_line <- str_squish(str_remove_all(line, url_token_re))
  
  # Page metadata / section-label lines, not data -- skip
  if (str_starts(clean_line, "updated ") || clean_line %in% skip_lines) next
  
  # Stray markup artifact: a link token with no visible text at all
  if (str_length(clean_line) == 0) next
  
  # Candidate header -- also fixes party/contest_id for everything that follows
  if (clean_line %in% names(candidate_party)) {
    current_candidate   <- clean_line
    current_party       <- candidate_party[[clean_line]]
    current_subcategory <- NA_character_
    next
  }
  
  # Sub-category header (currently just "Organized Labor", under Obama)
  if (clean_line %in% subcategory_headers) {
    current_subcategory <- clean_line
    next
  }
  
  # Otherwise: an organization-endorsement entry line
  url_matches  <- str_match_all(line, url_token_re)[[1]]
  evidence_url <- if (nrow(url_matches) > 0) url_matches[1, 2] else NA_character_
  
  m <- str_match(clean_line, entry_re)
  
  if (!is.na(m[1, 1])) {
    rows[[length(rows) + 1]] <- tibble(
      contest_id            = paste0("2012", current_party),
      year                  = 2012,
      party                 = current_party,
      endorsee              = current_candidate,
      endorser_name         = str_trim(m[1, "name"]),
      endorser_description  = if (identical(current_subcategory, "Organized Labor")) "Labor Union" else "National Organization",
      endorser_party_note   = NA_character_,
      state                 = NA_character_,
      district              = NA_character_,
      date_raw              = m[1, "date"],
      note                  = NA_character_,
      switch_direction      = NA_character_,
      switch_candidate      = NA_character_,
      evidence_url          = evidence_url,
      parsed_ok             = TRUE,
      raw_text              = clean_line
    )
  } else {
    # No trailing MM/DD/YY date found -- flagged for manual review rather
    # than guessed at (mirrors the officials/newspaper scripts' convention).
    # Not expected to fire on this page; kept as a safety net.
    rows[[length(rows) + 1]] <- tibble(
      contest_id            = if (!is.na(current_party)) paste0("2012", current_party) else NA_character_,
      year                  = 2012,
      party                 = current_party,
      endorsee              = current_candidate,
      endorser_name         = NA_character_,
      endorser_description  = if (identical(current_subcategory, "Organized Labor")) "Labor Union" else "National Organization",
      endorser_party_note   = NA_character_,
      state                 = NA_character_,
      district              = NA_character_,
      date_raw              = NA_character_,
      note                  = NA_character_,
      switch_direction      = NA_character_,
      switch_candidate      = NA_character_,
      evidence_url          = evidence_url,
      parsed_ok             = FALSE,
      raw_text              = paste0("[UNMATCHED] ", clean_line)
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

cat("\nEndorsements per endorser_description:\n")
print(count(df, endorser_description, sort = TRUE))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")