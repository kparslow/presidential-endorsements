# ============================================================================
# Extract national-organization endorsements from Democracy in Action (2016)
#
# Source page: "Endorsements by National Organizations in the 2016
# Presidential Campaign" (page footer: updated September 26, 2016)
# Input: data/raw/Democracy in Action/dia_2016_organizations.html
# Output: data/raw/Democracy in Action/extracted/dia_2016_organizations_extracted.csv
#
# Same layout as the 2012 organizations page: one main table whose first
# cell is a run of <br>-separated entries shaped like
#   "<a href=...>Org Name</a>&nbsp; <i>MM/DD/YY</i>"
# under bold candidate headers. Clinton's list is split by two sub-headers
# ("Labor Endorsements", "Other Organizations"), mapped to
# endorser_description = "Labor Union" / "National Organization" exactly as
# the 2012 script maps "Organized Labor".
#
# NOTE: this page covers BOTH parties and BOTH the general election and the
# primaries, in three blocks, recorded in `page_section`:
#   "nominees"           -- Hillary Clinton and Donald Trump. Many of these
#                           endorsements are dated after the nominations
#                           were settled (e.g. Teamsters for Clinton,
#                           08/26/16; Fraternal Order of Police for Trump,
#                           09/16/16).
#   "primary candidates" -- Sanders, Cruz, Kasich, Paul (the page's own
#                           "primary candidates..." label).
#   "no endorsement"     -- "No Endorsement, At Least for Now": Teamsters
#                           (09/30/15). A non-endorsement, so excluded.
#
# Decisions applied in this script (Oct. 2026): non-endorsements excluded;
# post-primary endorsements kept as-is (a post-primary indicator is added
# later); record_type = "endorsement" for every row. Candidate names on this
# page are already full names.
#
# NOTE on source quirks (kept in output rather than silently "corrected"):
#   - "date uncertain: International Association of Heat and Frost
#     Insulators and Allied Workers" (Clinton labor) has no date and no
#     link; date_raw is blank and note = "date uncertain".
#   - "Gun Owners of America" (Cruz) is split across two <a> tags with the
#     same href ("G" + "un Owners of America"); the text is rejoined and the
#     duplicate link collapsed to one evidence_url.
#   - The "Hillary Clinton" header contains an empty link to the IAM press
#     release (iam081415pr.html) -- a markup artifact, ignored.
#   - Some press-release file names do not match the displayed date (e.g.
#     IATSE iatse011315pr.html shown 01/13/16; MoveOn moveon010516pr.html
#     shown 01/12/16; CWA cwa120715pr.html shown 12/17/15). date_raw is
#     always the displayed date.
#   - The logo table below the main table (Planned Parenthood, NEA, NNU
#     images) repeats endorsements already listed -- not extracted.
#   - Sanders' list mixes unions (UE, ILWU, ATU, CWA, APWU, NNU) with other
#     groups under no sub-header, so all are "National Organization" here.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2016_organizations.html"
output_path <- "data/raw/Democracy in Action/extracted/dia_2016_organizations_extracted.csv"

# ---- Helper functions -------------------------------------------------------
# Marker technique shared with the other DIA scripts: rewrite links and
# breaks as plain-text markers before stripping tags.

link_token_re <- regex('<a\\s+[^>]*?href="([^"]*)"[^>]*>(.*?)</a>',
                       dotall = TRUE, ignore_case = TRUE)
url_token_re  <- regex("@@URL\\[([^\\]]*)\\]@@")
block_tag_re  <- regex("</?(?:p|div|tr|td|th|table|tbody|li|ul|center|blockquote|h1|h2|h3)\\b[^>]*>",
                       ignore_case = TRUE)

flatten_html <- function(html_str) {
  html_str <- str_remove_all(html_str, regex("<script\\b.*?</script>", dotall = TRUE, ignore_case = TRUE))
  # An empty link may serialize as self-closing <a href="..."/>; drop it so
  # the link pattern cannot run on to the next </a>.
  html_str <- str_remove_all(html_str, regex("<a\\b[^>]*/>", ignore_case = TRUE))
  html_str <- str_replace_all(html_str, link_token_re, "\\2@@URL[\\1]@@")
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

collect_urls <- function(line) {
  urls <- str_match_all(line, url_token_re)[[1]][, 2]
  urls <- unique(urls[!is.na(urls) & urls != ""])
  if (length(urls) == 0) NA_character_ else paste(urls, collapse = "; ")
}

# ---- Step 1: Read HTML and flatten the main table into lines ---------------

doc <- read_html(input_path, encoding = "UTF-8")
main_table <- xml_find_first(doc, "//div[@id='margin']//table")
stopifnot(!inherits(main_table, "xml_missing"))

all_lines <- flatten_html(as.character(main_table))
cat("Total lines found:", length(all_lines), "\n")

# ---- Step 2: Walk the lines as a state machine ------------------------------

candidate_party <- c(
  "Hillary Clinton" = "D", "Bernie Sanders" = "D",
  "Donald Trump" = "R", "Ted Cruz" = "R", "John Kasich" = "R", "Rand Paul" = "R"
)
subcategory_headers <- c("Labor Endorsements", "Other Organizations")
entry_re <- regex("^(?<name>.+?)\\s+(?<date>\\d{1,2}/\\d{1,2}/\\d{2})$")

current_candidate   <- NA_character_
current_party       <- NA_character_
current_subcategory <- NA_character_
current_section     <- "nominees"
n_excluded <- 0
rows <- list()

for (line in all_lines) {
  clean_line <- strip_urls(line)
  
  # Page furniture, not data
  if (clean_line %in% c("", "ADVERTISEMENT")) next
  if (str_detect(clean_line, "^[_\\s]+$")) next
  
  if (clean_line %in% names(candidate_party)) {
    current_candidate   <- clean_line
    current_party       <- candidate_party[[clean_line]]
    current_subcategory <- NA_character_
    next
  }
  if (clean_line %in% subcategory_headers) {
    current_subcategory <- clean_line
    next
  }
  if (clean_line == "primary candidates...") {
    current_section <- "primary candidates"
    next
  }
  if (clean_line == "No Endorsement, At Least for Now") {
    current_section     <- "no endorsement"
    current_candidate   <- NA_character_
    current_party       <- NA_character_
    current_subcategory <- NA_character_
    next
  }
  
  # Non-endorsements are excluded (Teamsters, "No Endorsement, At Least
  # for Now", 09/30/15).
  if (current_section == "no endorsement") {
    n_excluded <- n_excluded + 1
    next
  }
  
  description <- if (identical(current_subcategory, "Labor Endorsements")) "Labor Union" else "National Organization"
  m <- str_match(clean_line, entry_re)
  
  if (str_starts(clean_line, fixed("date uncertain:"))) {
    endorser_name <- str_squish(str_remove(clean_line, fixed("date uncertain:")))
    date_raw <- NA_character_
    note <- "date uncertain"
    ok <- TRUE
  } else if (!is.na(m[1, 1])) {
    endorser_name <- str_trim(m[1, "name"])
    date_raw <- m[1, "date"]
    note <- NA_character_
    ok <- TRUE
  } else {
    endorser_name <- NA_character_
    date_raw <- NA_character_
    note <- NA_character_
    ok <- FALSE
  }
  
  raw_text <- if (ok) clean_line else paste0("[UNMATCHED] ", clean_line)
  
  rows[[length(rows) + 1]] <- tibble(
    contest_id           = if (!is.na(current_party)) paste0("2016", current_party) else NA_character_,
    year                 = 2016,
    party                = current_party,
    endorsee             = current_candidate,
    endorser_name        = endorser_name,
    endorser_description = description,
    endorser_party_note  = NA_character_,
    state                = NA_character_,
    district             = NA_character_,
    date_raw             = date_raw,
    note                 = note,
    record_type          = "endorsement",
    switch_direction     = NA_character_,
    switch_candidate     = NA_character_,
    evidence_url         = collect_urls(line),
    parsed_ok            = ok,
    raw_text             = raw_text,
    page_section         = current_section
  )
}

df <- bind_rows(rows)

# ---- Step 3: Validation checkpoints, report, and write out -----------------
# Expected counts from manual inspection of the page:
#   Clinton 50 (34 labor incl. Heat and Frost Insulators, 16 other),
#   Trump 6, Sanders 12, Cruz 7, Kasich 1, Paul 1 = 77
#   (plus 1 excluded "No Endorsement" row).

cat("\nEndorsements per candidate and page section:\n")
print(count(df, page_section, endorsee))

cat("\nEndorsements per endorser_description:\n")
print(count(df, endorser_description))

cat("\nExcluded non-endorsement rows:", n_excluded, "\n")

stopifnot(
  nrow(df) == 77,
  n_excluded == 1,
  sum(df$endorsee == "Hillary Clinton", na.rm = TRUE) == 50,
  sum(df$endorsee == "Hillary Clinton" & df$endorser_description == "Labor Union", na.rm = TRUE) == 34
)

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "row(s) need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text))

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("Written to:", output_path, "\n")