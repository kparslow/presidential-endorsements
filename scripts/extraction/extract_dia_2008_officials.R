# ============================================================================
# Extract officials' endorsements from Democracy in Action (2008)
#
# Source page: "Endorsements by Congressmen, Senators, and Governors" (2008)
# Input: data/raw/Democracy In Action/dia_2008_p2008_org.html
# Output: data/raw/Democracy In Action/dia_2008_officials_extracted.csv
#
# This page lists officials (Governors/Senators/Representatives) who endorsed
# a 2008 presidential candidate, grouped by party then by candidate. Each
# entry is a text line like:
#   "U.S. Rep John Linder (GA-7) (Nov. 11, 2007; switched from Romney)"
# sometimes followed by a "+" link to a press release/news article.
# 
# NOTE: This page is a cumulative snapshot as of a report date, not organized
# by individual state contest the way Sources 1 and 2 are. There is no 
# per-row "contest" (e.g. state primary) to extract -- only party and 
# candidate. contest_id below is assigned generically as "2008D"/"2008R".
#
# NOTE: This script is specific to this page's HTML structure. Other
# Democracy in Action pages (different years, or the newpapaer/organization
# pages) will need their own extraction scripts -- see docs/data_sources.md
# for the decision on scope.
# ============================================================================

library(rvest)        # web scraping in R
library(xml2)         # node-by-node control for messy table
library(stringr)      # regex and text-cleaning
library(dplyr)        # data-shaping steps
library(purrr)         # check that removing this doesn't break anything
library(tibble)       # builds rows of extracted data

# ---- Config ----------------------------------------------------------------
input_path <- "data/raw/Democracy In Action/dia_2008_p2008_org.html"
output_path <- "data/raw/Democracy In Action/dia_2008_officials_extracted.csv"

# ---- Helper functions ------------------------------------------------------

# Split a <p> node's children into segments, breaking at each <br>.
# Mirrors how the source HTML separates on endorser entry from the next
# within a single <p> block.
extract_segments <- function(p_node) {
  contents <- xml_contents(p_node)
  segments <- list()
  current <- list()
  
  for (node in contents) {
    is_br <- xml_type(node) == "element" && xml_name(node) == "br"
    if (is_br) {
      segments[[length(segments) + 1]] <- current
      current <- list()
    } else {
      current[[length(current) + 1]] <- node
    }
  }
  if (length(current) > 0) segments[[length(segments) + 1]] <- current
  segments
}

# Find the first href within a segment (used to capture the "+" link to a
# press release or news article -> becomes `evidence_url`)
find_href <- function(node) {
  if (xml_type(node) != "element") return(NA_character_)
  a_nodes <- xml_find_all(node, ".//a | self::a")
  if (length(a_nodes) == 0) return(NA_character_)
  xml_attr(a_nodes[[1]], "href")
}

# Collapse a segment's nodes into a single cleaned text string, plus any link
segment_text_and_link <- function(seg) {
  if (length(seg) == 0) return(list(text = "", href = NA_character_))
  texts <- vapply(seg, xml_text, character(1))
  text <- str_squish(paste(texts, collapse = ""))
  hrefs <- vapply(seg, find_href, character(1))
  hrefs <- hrefs[!is.na(hrefs)]
  href <- if (length(hrefs) > 0) hrefs[1] else NA_character_
  list(text = text, href = href)
}

# ---- Step 1: Read HTML and extract raw (party, endorsee, text, link) rows ---

doc <- read_html(input_path, encoding = "ISO-8859-1")

# The page's two party columns are the two <td> cells in the first <tr> of
# the <table cols="2> element
outer_table <- html_element(doc, "table[cols='2']")
tds <- xml_find_all(outer_table, ".//tr[1]/td")

party_labels <- c("R", "D") # order matches the page: Republicans, then Democracts
rows <- list()

for (i in seq_along(tds)) {
  td <- tds[[i]]
  party <- party_labels[i]
  ps <- xml_find_all(td, "./p")
  candidate <- NA_character_
  
  for (p in ps) {
    # A bold header at the top of a <p> introduces a new candidate; if a <p>
    # has no bold header, it continues the previous candidate's list
    b_node <- xml_find_first(p, ".//b")
    b_text <- if (!is.na(b_node)) str_squish(xml_text(b_node)) else ""
    if (nzchar(b_text)) candidate <- b_text
    
    for (seg in extract_segments(p)) {
      res <- segment_text_and_link(seg)
      if (!nzchar(res$text)) next
      if (identical(res$text, candidate)) next # skip the header segment itself
      
      rows[[length(rows) + 1]] <- tibble(
        party = party,
        endorsee = candidate,
        raw_text = res$text,
        evidence_url = res$href
      )
    }
  }
}

raw_df <- bind_rows(rows)
cat("Total entries extracted:", nrow(raw_df), "\n")

# ---- Step 2: Parse each entry into structured fields ------------------------
# Expected pattern: "<Title> <Name> (<State/District>) (<Data>; <note>)"

pattern <- paste0(
  "^(U\\.S\\.\\s+Rep\\.|U\\.S\\.\\s+Sen\\.|Lt\\.\\s+Gov\\.|Gov\\.|Sen\\.|Rep\\.)\\s+",
  "(.+?)\\s*\\(([^)]+)\\)\\s*",
  "(?:\\(([^)]+)\\))?\\s*\\+?\\s*$"
)

parsed <- str_match(raw_df$raw_text, pattern)

df <- raw_df %>%
  mutate(
    title = parsed[, 2],
    name = str_trim(parsed[, 3]),
    loc = parsed[, 4],
    paren2 = parsed[, 5],
    parsed_ok = !is.na(parsed[, 2])
  )

# ---- Step 3: Split location into state + district ---------------------------
# Handles "SD" (state only), "AR-3" (state-district), "I-CT" (independent
# party prefix, not a district)

df <- df %>%
  mutate(
    district = str_extract(loc, "(?<=-)\\d+$"),
    state = case_when(
      str_detect(loc, "-\\d+$") ~ str_remove(loc, "-\\d+$"),
      str_detect(loc, "^I-") ~ str_remove(loc, "I-"),
      TRUE ~ loc
    ),
    endorser_party_note = if_else(str_detect(loc, "^I-"), "Independent", NA_character_)
  )

# ---- Step 4: Split data/note, and detect endorsement switches ---------------

df <- df %>%
  mutate(
    date_raw = str_trim(str_extract(paren2, "^[^;]+")),
    note = str_trim(str_remove(paren2, "^[^;]+;?")),
    note = na_if(note, "")
  ) %>%
  mutate(
    switch_direction = case_when(
      str_detect(note, regex("switched from", ignore_case = TRUE)) ~ "from",
      str_detect(note, regex("switched (support )?to", ignore_case = TRUE)) ~ "to",
      TRUE ~ NA_character_
    ),
    switch_candidate = str_match(
      note,
      regex("switched (?:support )?(?:from|to) ([A-Za-z.\\- ]+?)(?:[,.]|$)", ignore_case = TRUE)
    )[, 2] %>% str_trim()
  )

# ---- Step 5: Map title -> a plain-language endorser description --------------

df <- df %>%
  mutate(
    endorser_description = case_when(
      title == "Gov." ~ "Governor",
      title == "Lt. Gov." ~ "Lieutenant Governor",
      title == "U.S. Sen." ~ "U.S. Senator",
      title == "U.S. Rep." ~ "U.S. Representative",
      title %in% c("Sen.", "Rep.") ~ title,
      TRUE ~ NA_character_
    )
  )

# ---- Step 6: Assign contest_id and finalize column order ---------------------

df <- df %>%
  mutate(
    contest_id = paste0("2008", party),
    year = 2008
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name = name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text
  )

# ---- Step 7: Report and write out --------------------------------------------

n_failed <- sum(!df$parsed_ok)
cat("Successfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "rows did not match the expected pattern and need manual review\n")
cat("(these are kept in output with parsed_ok = FALSE and raw_text preserved\n")

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")