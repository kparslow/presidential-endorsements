# ============================================================================
# Extract officials' endorsements from Democracy in Action (2012)
#
# Source page: Democracy in Action / p2012.org "National Endorsements" page.
# Input: data/raw/Democracy in Action/dia_2012_p2012_org.html
# Output: data/raw/Democracy in Action/dia_2012_officials_extracted.csv
#
# This page contains four tables:
#   1. The candidate-organized table (Romney in td[1]; Gingrich, Paul,
#      Santorum, Perry, Bachmann, Cain, and Pawlenty all stacked in td[2],
#      separated by inline bold name headers). This is the only table with
#      per-endorsement dates and evidence links -- extracted below.
#   2-4. "Cross-reference" tables (Governors / Senators / House members)
#      further down the page. Cleaner grids, but no dates or evidence
#      links -- useful later as a completeness/consistency check, not
#      extracted here.
#
# NOTE: Unlike the 2008 page (two columns: Republican and Democratic
# candidates), this page covers only the 2012 Republican primary. Obama
# ran unopposed as the incumbent Democrat, so there is no parallel
# Democratic table to extract, and contest_id below is always "2012R".
#
# NOTE: Unlike the 2008 source (clean nested <tbody>/<tr>/<td> per
# candidate), this page's target table is unstructured text with <br>
# line breaks and inline bold headers. See inline comments for the
# parsing strategy, which necessarily differs from the 2008 script's
# <p>/segment-based approach even though the OUTPUT schema matches it.
# ============================================================================

library(rvest)
library(xml2)
library(stringr)
library(dplyr)
library(purrr)
library(tibble)

# ---- Config ----------------------------------------------------------------
input_path  <- "data/raw/Democracy in Action/dia_2012_p2012_org.html"
output_path <- "data/raw/Democracy in Action/dia_2012_officials_extracted.csv"

# ---- Helper functions -------------------------------------------------------

# Pull the candidate-name headers straight from the markup rather than
# hand-typing them. Candidate names are marked with <big> tags; a few <big>
# tags elsewhere in the cell are just decorative spacing (empty text), so
# blank ones are dropped. Deriving this list from the HTML itself -- instead
# of a hardcoded vector of candidate names -- avoids exact-string-match
# typos silently misattributing one candidate's entries to another.
get_candidate_headers <- function(td) {
  nodes <- xml_find_all(td, ".//big")
  texts <- str_squish(html_text2(nodes))
  texts[texts != ""]
}

# <td> -> vector of clean lines, one endorsement entry per line.
#
# Earlier version used html_text2(td) to convert <br> into line breaks,
# trusting it to mimic browser rendering. It doesn't, reliably: some <br>
# tags in this file carry a style attribute (<br style="color: ...">), and
# html_text2() silently drops the line break for some of these -- and for
# some plain <br> tags that sit right before a closing tag, e.g.
# <big>Mitt Romney<br></big> -- fusing the candidate header directly onto
# the next endorser's text with no separator at all ("Mitt RomneyGov. Jan
# Brewer..."). That's a genuine limitation of the rendering-simulation
# approach, not something str_squish() can clean up after the fact.
#
# The fix: don't rely on any function's internal <br>-handling heuristics.
# Replace every literal <br ...> tag in the raw markup with an unambiguous
# marker BEFORE any tag-stripping happens, then strip tags and collapse
# other (accidental/formatting) whitespace afterward. This can't miss a
# <br> or mis-handle one based on where it sits in the tag tree, because
# it isn't reasoning about tag position at all -- just literal text.
td_to_lines <- function(td) {
  html_str <- as.character(td)
  html_str <- str_replace_all(html_str, "<br\\b[^>]*>", "@@BR@@")
  # Re-wrap in a minimal valid table so a bare <td> string parses cleanly.
  frag <- read_html(paste0("<table><tr>", html_str, "</tr></table>"))
  txt <- xml_text(frag)
  txt <- str_replace_all(txt, "\u00a0", " ")  # nbsp -> ordinary space
  txt <- str_replace_all(txt, "\\s+", " ")     # collapse other whitespace/newlines
  lines <- str_split(txt, fixed("@@BR@@"))[[1]]
  lines <- str_trim(lines)
  lines[lines != ""]
}

# Ordered list of "+" evidence-link URLs from a <td>. After tag-stripping,
# an evidence link <a href="URL">+</a> becomes just the character "+" in the
# flattened text -- the URL is lost. But hrefs appear in the same
# left-to-right, top-to-bottom order as the "+" marks in the text, so we
# zip them back together positionally in parse_td() below.
get_evidence_urls <- function(td) {
  anchors <- html_nodes(td, "a")
  is_evidence <- html_text(anchors, trim = TRUE) == "+"
  html_attr(anchors[is_evidence], "href")
}

entry_start_re <- regex("^\\*?(Gov|Sen|Rep)\\.\\s")

# Parse one <td> into one row per endorsement (or flagged non-matching line).
parse_td <- function(td) {
  headers <- get_candidate_headers(td)
  lines <- td_to_lines(td)
  evidence_urls <- get_evidence_urls(td)
  url_ptr <- 0  # advances each time we consume a run of "+" characters
  
  current_candidate <- NA_character_
  records <- list()
  buffer <- NULL
  
  flush_buffer <- function() {
    if (!is.null(buffer)) {
      records[[length(records) + 1]] <<- list(
        candidate = current_candidate,
        raw_text  = buffer
      )
    }
    buffer <<- NULL
  }
  
  for (line in lines) {
    if (line %in% headers) {
      flush_buffer()
      current_candidate <- line
    } else if (str_detect(line, entry_start_re)) {
      flush_buffer()
      buffer <- line
    } else if (!is.null(buffer)) {
      # Defensive: continues an open entry rather than starting a new one.
      buffer <- str_squish(paste(buffer, line))
    } else {
      # No open entry and no header match: summary labels like "19
      # Senators", "...78 House members", the off-schema Gov. Bentley
      # aside, and the unconfirmed Herman Cain tweet all land here.
      # NOTE: this uses plain `<-`, not `<<-` -- this branch runs directly
      # in the for loop, which shares parse_td()'s own frame (for loops
      # don't create a new scope), so `<-` is already writing to the right
      # "records". Using `<<-` here (as an earlier draft did) skips that
      # frame and looks further up, causing "object 'records' not found".
      records[[length(records) + 1]] <- list(
        candidate = current_candidate,
        raw_text  = paste0("[UNMATCHED] ", line)
      )
    }
  }
  flush_buffer()
  
  map_dfr(records, function(r) {
    n_plus <- str_count(r$raw_text, fixed("+"))
    urls <- if (n_plus > 0) {
      idx <- (url_ptr + 1):(url_ptr + n_plus)
      url_ptr <<- url_ptr + n_plus
      evidence_urls[idx]
    } else {
      character(0)
    }
    tibble(
      endorsee     = r$candidate,
      raw_text     = r$raw_text,
      evidence_url = if (length(urls) > 0) paste(urls, collapse = "; ") else NA_character_
    )
  })
}

# ---- Step 1: Read HTML and extract raw (endorsee, text, link) rows ---------

doc <- read_html(input_path)

# Table 1 is the only table styled width:96%; the other three (Governors /
# Senators / House cross-reference grids) are width:100%. It's also simply
# the first <table> node in the document.
table1 <- html_nodes(doc, "table")[[1]]
tds <- html_nodes(table1, "td")
stopifnot(length(tds) == 2)  # td[1] = Romney, td[2] = all other candidates

raw_df <- map_dfr(tds, parse_td)
cat("Total entries extracted:", nrow(raw_df), "\n")

# ---- Step 2: Parse each entry into structured fields ------------------------
# Expected pattern: "<Title>. <Name> (<State/District>) <date and/or note> [+]"

entry_re <- regex(
  "^(?<star>\\*)?(?<title>Gov|Sen|Rep)\\.\\s*(?<name>.+?)\\s*\\((?<code>[A-Za-z]{2,4}-?[A-Za-z0-9]*)\\)\\s*(?<remainder>.*)$"
)

m <- str_match(raw_df$raw_text, entry_re)

df <- raw_df %>%
  mutate(
    post_primary  = !is.na(m[, "star"]),
    title         = m[, "title"],
    endorser_name = str_trim(m[, "name"]),
    loc           = m[, "code"],
    remainder     = str_squish(str_remove_all(m[, "remainder"], "\\+")),
    parsed_ok     = !is.na(m[, "title"])
  )

# ---- Step 3: Split location into state + district ---------------------------
# Mirrors the 2008 script's approach, extended to allow alpha district codes
# (e.g. "AL" for at-large, as in "WY-AL"), not just numeric ones.
#
# NOTE: three House entries use "CD-##" instead of a state abbreviation
# (CD-41, CD-44, CD-50) -- looks like a source-file inconsistency (all three
# are California seats). Flagged here for the known-issues log rather than
# silently corrected.

df <- df %>%
  mutate(
    district = str_extract(loc, "(?<=-)[A-Za-z0-9]+$"),
    state = str_remove(loc, "-[A-Za-z0-9]+$"),
    endorser_party_note = NA_character_  # no independents on this page
  )

# ---- Step 4: Split date vs. note text, and endorsement-switch fields --------
# This source's Table 1 doesn't use "switched from/to" language the way the
# 2008 page does, so switch_direction/switch_candidate are always NA here --
# kept as columns purely for schema consistency with the 2008 output.

df <- df %>%
  mutate(
    date_raw = str_extract(remainder, "\\d{1,2}/\\d{1,2}/\\d{2}"),
    note = if_else(!is.na(date_raw), str_remove(remainder, fixed(date_raw)), remainder),
    note = str_squish(note),
    # A few notes (e.g. the Hatch entry) are wrapped in their own parens,
    # separate from the location parens already stripped above -- drop a
    # single enclosing pair so `note` is plain text, matching 2008's output.
    note = str_remove(note, "^\\("),
    note = str_remove(note, "\\)$"),
    note = na_if(str_squish(note), ""),
    switch_direction = NA_character_,
    switch_candidate = NA_character_
  )

# ---- Step 5: Map title -> a plain-language endorser description ------------

df <- df %>%
  mutate(
    endorser_description = case_when(
      title == "Gov" ~ "Governor",
      title == "Sen" ~ "U.S. Senator",
      title == "Rep" ~ "U.S. Representative",
      TRUE ~ NA_character_
    )
  )

# ---- Step 6: Assign contest_id/party/year and finalize column order --------

df <- df %>%
  mutate(
    contest_id = "2012R",
    year = 2012,
    party = "R"
  ) %>%
  select(
    contest_id, year, party, endorsee,
    endorser_name, endorser_description, endorser_party_note,
    state, district,
    date_raw, note, switch_direction, switch_candidate,
    evidence_url,
    parsed_ok, raw_text,
    post_primary   # 2012-specific: endorsed after suspending primary campaign
  )

# ---- Step 7: Validation checkpoints, report, and write out -----------------
# The page's own intro text states expected Romney totals: 10 governors
# (+3 territorial), 19 U.S. Senators, 78 U.S. House members. Cross-check
# the extraction against these before trusting the rest of the output.

romney <- df %>% filter(endorsee == "Mitt Romney", parsed_ok)
cat("Romney governors:", sum(romney$endorser_description == "Governor"), "(expect 13: 10 + 3 territorial)\n")
cat("Romney senators: ", sum(romney$endorser_description == "U.S. Senator"), "(expect 19)\n")
cat("Romney house:    ", sum(romney$endorser_description == "U.S. Representative"), "(expect 78)\n")

cat("\nEndorsements per candidate:\n")
print(count(df, endorsee, sort = TRUE))

n_failed <- sum(!df$parsed_ok)
cat("\nSuccessfully parsed:", sum(df$parsed_ok), "/", nrow(df), "\n")
cat(n_failed, "rows did not match the expected pattern and need manual review:\n")
print(df %>% filter(!parsed_ok) %>% pull(raw_text))
cat("(these are kept in output with parsed_ok = FALSE and raw_text preserved)\n")

dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write.csv(df, output_path, row.names = FALSE, na = "")

cat("Written to:", output_path, "\n")